// SPDX-License-Identifier: GPL-3.0-or-later
// Test-only OS observations and process-local notification centers. Never lock,
// switch users, send distributed notifications or grant actual GUI authority.
#import "graphical-authority.h"
#import "authentication-session.h"
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Security/AuthSession.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <objc/runtime.h>
#include <membership.h>
#include <unistd.h>

static unsigned checks;
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "scope lifecycle failed line %d\n", __LINE__); exit(1); } ++checks; } while (0)
static BOOL onConsole = YES, loginDone = YES, locked, graphicAccess = YES, available = YES;
static SecuritySessionId auditSession = 42;
static uid_t consoleUID;
static uint8_t accountVersion = 1;
static NSNotificationCenter *workspaceCenter, *distributedCenter;

@interface PLANKFakeWorkspace : NSObject
- (NSNotificationCenter *)notificationCenter;
@end
@implementation PLANKFakeWorkspace
- (NSNotificationCenter *)notificationCenter { return workspaceCenter; }
@end
static PLANKFakeWorkspace *workspace;
static id fakeWorkspace(id object, SEL selector) { (void)object; (void)selector; return workspace; }
static id fakeDistributed(id object, SEL selector) { (void)object; (void)selector; return distributedCenter; }

OSStatus SessionGetInfo(SecuritySessionId requested, SecuritySessionId *actual, SessionAttributeBits *attributes) {
    (void)requested; *actual = auditSession;
    *attributes = graphicAccess ? sessionHasGraphicAccess : 0;
    return errSecSuccess;
}
CFDictionaryRef CGSessionCopyCurrentDictionary(void) {
    if (!available) return NULL;
    return CFBridgingRetain(@{(__bridge NSString *)kCGSessionOnConsoleKey: @(onConsole),
        (__bridge NSString *)kCGSessionLoginDoneKey: @(loginDone),
        (__bridge NSString *)kCGSessionUserIDKey: @(consoleUID),
        @"CGSSessionScreenIsLocked": @(locked)});
}
CFStringRef SCDynamicStoreCopyConsoleUser(SCDynamicStoreRef store, uid_t *uid, gid_t *gid) {
    (void)store; if (uid) *uid = consoleUID; if (gid) *gid = getgid();
    return CFBridgingRetain(@"example");
}
int mbr_uid_to_uuid(uid_t uid, uuid_t uuid) {
    (void)uid; memset(uuid, 0, sizeof(uuid_t)); uuid[0] = accountVersion; return 0;
}
PLANKMacAuthenticationResult PLANKMacVerifyAccountIsolated(
        NSString *name, NSMutableData *password, PLANKMacAccountIdentity *identity) {
    (void)name; [password resetBytesInRange:NSMakeRange(0, password.length)];
    *identity = (PLANKMacAccountIdentity){getuid(), {1}};
    return PLANKMacAuthenticationVerified;
}

int main(void) {
    alarm(15);
    @autoreleasepool {
        CHECK(getuid() != 0 && getuid() == geteuid());
        workspaceCenter = [NSNotificationCenter new]; distributedCenter = [NSNotificationCenter new];
        workspace = [PLANKFakeWorkspace new];
        Method workspaceMethod = class_getClassMethod(NSWorkspace.class, @selector(sharedWorkspace));
        Method distributedMethod = class_getClassMethod(NSDistributedNotificationCenter.class, @selector(defaultCenter));
        IMP oldWorkspace = method_setImplementation(workspaceMethod, (IMP)fakeWorkspace);
        IMP oldDistributed = method_setImplementation(distributedMethod, (IMP)fakeDistributed);
        // Exercise the real authority/auth owner. No fixture hooks enter the app.
        for (unsigned scenario = 0; scenario < 9; ++scenario) {
            consoleUID = getuid(); auditSession = 42; accountVersion = 1;
            onConsole = loginDone = graphicAccess = available = YES; locked = NO;
            PLANKMacGraphicalAuthority *authority = [[PLANKMacGraphicalAuthority alloc] initWithPhase:PLANKMacScopeDesktop];
            PLANKMacGraphicalIdentity original = authority.snapshot;
            CHECK(original.active);
            PLANKMacAuthenticationSession *auth = [[PLANKMacAuthenticationSession alloc]
                initWithGraphicalSnapshot:^{ return authority.snapshot; }];
            NSData *peer = [NSData dataWithBytes:"test" length:4];
            NSDictionary *start = [auth startForPeer:peer username:@"example"];
            CHECK([start[@"state"] isEqual:@"challenge"]);
            NSDictionary *response = [auth respondForPeer:peer conversation:start[@"conversation_id"]
                password:[NSMutableData dataWithBytes:"test" length:4]];
            CHECK([response[@"state"] isEqual:@"authenticated"]);
            PLANKMacStreamLease *lease = [auth claimToken:response[@"session_token"] peer:peer];
            CHECK(lease && [auth activateStreamLease:lease]);
            PLANKMacAccountIdentity identity;
            // Saver/lock/unlock preserve this exact generation, lease and account.
            for (NSString *notification in @[@"com.apple.screensaver.didstart", @"com.apple.screenIsLocked",
                    @"com.apple.screenIsUnlocked", @"com.apple.screensaver.didstop"]) {
                if ([notification isEqual:@"com.apple.screenIsLocked"]) locked = YES;
                if ([notification isEqual:@"com.apple.screenIsUnlocked"]) locked = NO;
                [distributedCenter postNotificationName:notification object:nil];
                CHECK(plank_macos_same_graphical_scope(original, authority.snapshot));
                CHECK([auth authorizeStreamLease:lease identity:&identity]);
                CHECK(identity.uid == getuid());
            }
            // A lock/unlock notification must not mask or reverse real revocation.
            switch (scenario) {
                case 0: [workspaceCenter postNotificationName:NSWorkspaceSessionDidResignActiveNotification object:nil]; break;
                case 1: [workspaceCenter postNotificationName:NSWorkspaceWillSleepNotification object:nil]; break;
                case 2: onConsole = NO; break;
                case 3: loginDone = NO; break;
                case 4: ++consoleUID; break;
                case 5: ++auditSession; break;
                case 6: ++accountVersion; break;
                case 7: graphicAccess = NO; break;
                case 8: available = NO; break;
            }
            CHECK(!authority.snapshot.active);
            CHECK(![auth authorizeStreamLease:lease identity:&identity]);
            consoleUID = getuid(); auditSession = 42; accountVersion = 1;
            onConsole = loginDone = graphicAccess = available = YES;
            [distributedCenter postNotificationName:@"com.apple.screenIsUnlocked" object:nil];
            CHECK(!authority.snapshot.active);
            CHECK(![auth authorizeStreamLease:lease identity:&identity]);
            CHECK(![[auth startForPeer:peer username:@"example"][@"state"] isEqual:@"challenge"]);
            [auth revokeAll];
        }
        method_setImplementation(workspaceMethod, oldWorkspace);
        method_setImplementation(distributedMethod, oldDistributed);
        printf("macos_graphical_lifecycle=pass checks=%u synthetic_os=1 lock_continuity=1 revocation_latched=1\n", checks);
    }
    return 0;
}
