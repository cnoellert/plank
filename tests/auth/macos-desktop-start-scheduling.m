// SPDX-License-Identifier: GPL-3.0-or-later
// Execute the production scheduler with synthetic console records, tasks and
// delayed callbacks. Never launches a command or registers a real OS observer.
#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <unistd.h>
#include <assert.h>
#include <errno.h>

static NSDictionary *consoleRecord;
static NSMutableArray *tasks, *delayed;
static BOOL failLaunch;
static unsigned checks;
#define CHECK(x) do { assert(x); ++checks; } while (0)

@interface PLANKStartTestTask : NSObject
@property NSURL *executableURL;
@property NSArray *arguments;
@property id standardInput, standardOutput, standardError;
@property(copy) void (^terminationHandler)(PLANKStartTestTask *);
@property BOOL running;
@property NSTaskTerminationReason terminationReason;
@property int terminationStatus;
- (BOOL)launchAndReturnError:(NSError **)error;
- (void)terminate;
- (void)complete:(int)status;
@end
@implementation PLANKStartTestTask
- (BOOL)launchAndReturnError:(NSError **)error {
    CHECK([self.executableURL.path isEqual:@"/bin/launchctl"]);
    CHECK(self.arguments.count == 2 && [self.arguments[0] isEqual:@"kickstart"]);
    NSString *job = [NSString stringWithFormat:@"gui/%u/la.instinctual.PLANK.Host.desktop",
        [consoleRecord[@"UID"] unsignedIntValue]];
    CHECK([self.arguments[1] isEqual:job]);
    [tasks addObject:self];
    if (failLaunch) {
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:EAGAIN userInfo:nil];
        return NO;
    }
    self.running = YES; return YES;
}
- (void)complete:(int)status {
    self.running = NO; self.terminationStatus = status;
    self.terminationReason = NSTaskTerminationReasonExit;
    self.terminationHandler(self);
}
- (void)terminate { [self complete:15]; }
@end

static SCDynamicStoreRef fakeCreate(CFAllocatorRef allocator, CFStringRef name,
        SCDynamicStoreCallBack callback, SCDynamicStoreContext *context) {
    (void)allocator; (void)name; (void)callback; (void)context;
    return (SCDynamicStoreRef)CFBridgingRetain(@{});
}
static CFPropertyListRef fakeCopy(SCDynamicStoreRef store, CFStringRef key) {
    (void)store; (void)key; return CFBridgingRetain(consoleRecord);
}
static Boolean fakeKeys(SCDynamicStoreRef store, CFArrayRef keys, CFArrayRef patterns) {
    (void)store; (void)keys; (void)patterns; return true;
}
static Boolean fakeQueue(SCDynamicStoreRef store, dispatch_queue_t queue) {
    (void)store; (void)queue; return true;
}
static uid_t fakeUID(void) { return 0; }
static void fakeAfter(dispatch_time_t deadline, dispatch_queue_t queue, dispatch_block_t block) {
    (void)deadline; (void)queue; [delayed addObject:[block copy]];
}
static void fakeAsync(dispatch_queue_t queue, dispatch_block_t block) { (void)queue; block(); }

#define NSTask PLANKStartTestTask
#define SCDynamicStoreCreate fakeCreate
#define SCDynamicStoreCopyValue fakeCopy
#define SCDynamicStoreSetNotificationKeys fakeKeys
#define SCDynamicStoreSetDispatchQueue fakeQueue
#define getuid fakeUID
#define dispatch_after fakeAfter
#define dispatch_async fakeAsync
#import "../../apps/host/macos/session/desktop-start.m"
#undef dispatch_async

static NSDictionary *console(unsigned uid, unsigned audit) {
    return @{@"Name": @"example", @"UID": @(uid), @"SessionInfo": @[
        @{@"kCGSSessionOnConsoleKey": @YES, @"kCGSessionLoginDoneKey": @YES,
          @"kCGSSessionUserIDKey": @(uid), @"kCGSSessionAuditIDKey": @(audit)}]};
}

static void exercise(void) {
    tasks = [NSMutableArray array]; delayed = [NSMutableArray array];
    consoleRecord = console(901, 100009);
    PLANKMacDesktopStart *starter = [PLANKMacDesktopStart new];
    CHECK([starter start] && tasks.count == 1);
    [tasks.lastObject complete:0];
    NSUInteger pending = delayed.count;
    [starter desktopProcessExitedForUID:901 audit:100009];
    CHECK(delayed.count == pending + 1);
    dispatch_block_t retry = delayed.lastObject;
    [starter desktopProcessExitedForUID:901 audit:100009];
    [starter refresh]; [starter retry];
    CHECK(delayed.count == pending + 1 && tasks.count == 1);
    retry();
    CHECK(tasks.count == 2);

    // Exit beats kickstart completion; the late success cannot lose recovery.
    [starter desktopProcessExitedForUID:901 audit:100009];
    pending = delayed.count;
    [tasks.lastObject complete:0];
    CHECK(delayed.count == pending + 1);
    retry = delayed.lastObject;
    consoleRecord = console(902, 100010);
    [starter refresh];
    CHECK(tasks.count == 3);
    [tasks.lastObject complete:0];
    pending = delayed.count;
    retry();
    [starter desktopProcessExitedForUID:901 audit:100009];
    CHECK(tasks.count == 3 && delayed.count == pending);

    // Same UID's new audit session also invalidates old delayed work.
    [starter desktopProcessExitedForUID:902 audit:100010];
    retry = delayed.lastObject;
    consoleRecord = console(902, 100011);
    [starter refresh];
    CHECK(tasks.count == 4);
    retry();
    CHECK(tasks.count == 4);
    [tasks.lastObject complete:1];
    retry = delayed.lastObject;
    [starter stop]; retry();
    CHECK(tasks.count == 4);

    // Console changes while launchctl is still running: its old completion
    // cannot mark the new account started or prevent that account's request.
    tasks = [NSMutableArray array]; delayed = [NSMutableArray array];
    consoleRecord = console(901, 100014);
    starter = [PLANKMacDesktopStart new];
    CHECK([starter start]);
    consoleRecord = console(902, 100015); [starter refresh];
    CHECK(tasks.count == 1);
    [tasks.lastObject complete:0];
    retry = delayed.lastObject; retry();
    CHECK(tasks.count == 2);
    [tasks.lastObject complete:0]; [starter stop];

    // A permanently unavailable port cannot produce an endless demand loop.
    tasks = [NSMutableArray array]; delayed = [NSMutableArray array];
    consoleRecord = console(903, 100012);
    starter = [PLANKMacDesktopStart new];
    CHECK([starter start]);
    for (unsigned attempt = 1; attempt <= 10; ++attempt) {
        CHECK(tasks.count == attempt);
        [tasks.lastObject complete:0];
        pending = delayed.count;
        [starter desktopProcessExitedForUID:903 audit:100012];
        CHECK(delayed.count == pending + (attempt < 10));
        if (attempt < 10) { retry = delayed.lastObject; retry(); }
    }
    [starter refresh]; [starter retry];
    CHECK(tasks.count == 10);
    consoleRecord = nil; [starter refresh];
    [starter desktopProcessExitedForUID:903 audit:100012];
    CHECK(tasks.count == 10);
    consoleRecord = console(904, 100013); [starter refresh];
    CHECK(tasks.count == 11);
    // A task timeout is bounded; its delayed retry is inert after stop.
    dispatch_block_t timeout = delayed.lastObject;
    timeout();
    CHECK(![(PLANKStartTestTask *)tasks.lastObject running]);
    retry = delayed.lastObject;
    [starter stop]; retry();
    CHECK(tasks.count == 11);

    // Invocation failure consumes an attempt and remains asynchronous.
    tasks = [NSMutableArray array]; delayed = [NSMutableArray array];
    failLaunch = YES;
    starter = [PLANKMacDesktopStart new];
    CHECK([starter start] && tasks.count == 1 && delayed.count == 1);
    retry = delayed.lastObject; failLaunch = NO; retry();
    CHECK(tasks.count == 2);
    [tasks.lastObject complete:0];
    [starter stop];
    printf("macos_desktop_start_scheduling=pass checks=%u synthetic_os=1 real_launchd_changes=0\n", checks);
}

int main(void) {
    alarm(10);
    dispatch_async(dispatch_get_main_queue(), ^{ @autoreleasepool { exercise(); exit(0); } });
    dispatch_main();
}
