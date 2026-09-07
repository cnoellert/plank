// SPDX-License-Identifier: GPL-3.0-or-later
#import "display-owner-probe.h"
#import "virtual-display-probe.h"
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct { uint32_t magic, display, width, height, status; } DisplayReport;
static const uint32_t displayReportMagic = 0x504c4e4b;

// These waits pump the graphical run loop. Probe-only deadlines, not a blocking
// API intended for the eventual Host's UI or connection/control thread.
static BOOL waitFor(NSTimeInterval seconds, BOOL (^condition)(void)) {
    __block BOOL passed = NO;
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + seconds;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC, 5 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        passed = condition();
        if (passed || NSProcessInfo.processInfo.systemUptime >= deadline) CFRunLoopStop(CFRunLoopGetMain());
    });
    dispatch_resume(timer);
    CFRunLoopRun();
    dispatch_source_cancel(timer);
    return passed;
}

static BOOL selectMode(CGDirectDisplayID display, unsigned int width, unsigned int height) {
    if (CGDisplayIsInMirrorSet(display)) return NO;
    CFArrayRef modes = CGDisplayCopyAllDisplayModes(display, NULL);
    BOOL selected = NO;
    if (modes && CFArrayGetCount(modes) < 128) {
        for (CFIndex i = 0; i < CFArrayGetCount(modes); ++i) {
            CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
            if (CGDisplayModeGetPixelWidth(mode) == width && CGDisplayModeGetPixelHeight(mode) == height &&
                CGDisplayModeGetWidth(mode) == width && CGDisplayModeGetHeight(mode) == height &&
                fabs(CGDisplayModeGetRefreshRate(mode) - 60) < 0.01) {
                selected = CGDisplaySetDisplayMode(display, mode, NULL) == kCGErrorSuccess;
                break;
            }
        }
    }
    if (modes) CFRelease(modes);
    return selected;
}

int PLANKRunDisplayOwner(unsigned int width, unsigned int height, BOOL handoff) {
    // Never run a display owner accidentally from a Terminal with no parent.
    struct stat input, output;
    if (fstat(STDIN_FILENO, &input) || fstat(STDOUT_FILENO, &output) ||
        !S_ISFIFO(input.st_mode) || !S_ISFIFO(output.st_mode)) return 2;
    if (!((width == 1920 && height == 1080) || (width == 3840 && height == 2160))) return 2;
    signal(SIGPIPE, SIG_IGN);
    PLANKVirtualDisplay *display = createProbeDisplay(width, height);
    if (!display) return 3;
    CGDirectDisplayID target = display.displayID;
    // Give WindowServer its normal asynchronous registration interval.
    NSTimeInterval readyAt = NSProcessInfo.processInfo.systemUptime + 2;
    (void)waitFor(3, ^BOOL{ return NSProcessInfo.processInfo.systemUptime >= readyAt; });
    BOOL selected = onlineState(target) == 1 && selectMode(target, width, height);
    DisplayReport message = {displayReportMagic, target, width, height, selected ? 0 : 4};
    if (write(STDOUT_FILENO, &message, sizeof(message)) != sizeof(message) || !selected) return 4;
    int flags = fcntl(STDIN_FILENO, F_GETFL);
    if (flags < 0 || fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK) < 0) return 4;
    // EOF is the only control message. Parent exit also closes this pipe.
    // Independent deadline bounds an abandoned owner even if a FD leaked.
    BOOL closed = waitFor(handoff ? 200 : 32, ^BOOL{
        char byte;
        ssize_t count = read(STDIN_FILENO, &byte, 1);
        return count == 0;
    });
    // Keep the object strongly alive across all waits under ARC.
    fprintf(stderr, "display_owner_exit display=%u control_eof=%d\n", display.displayID, closed);
    return closed ? 0 : 5;
}

@interface PLANKDisplayOwnerProbe ()
@property(nonatomic) CGDirectDisplayID displayID;
@property(nonatomic, strong) NSTask *task;
@property(nonatomic, strong) NSPipe *control, *reportPipe;
@property(nonatomic) BOOL forcedCrash;
@end

@implementation PLANKDisplayOwnerProbe
- (BOOL)running { return self.task.running; }
- (BOOL)crashForQualification {
    if (!self.running || self.forcedCrash) return NO;
    self.forcedCrash = kill(self.task.processIdentifier, SIGKILL) == 0;
    printf("media_owner_injected_crash=%d\n", self.forcedCrash);
    return self.forcedCrash;
}
- (BOOL)startWidth:(unsigned int)width height:(unsigned int)height {
    if (self.task || !((width == 1920 && height == 1080) || (width == 3840 && height == 2160))) return NO;
    self.control = [NSPipe pipe];
    self.reportPipe = [NSPipe pipe];
    self.task = [[NSTask alloc] init];
    self.task.executableURL = NSBundle.mainBundle.executableURL;
    self.task.arguments = @[self.handoffQualification ? @"--handoff-display-owner" : @"--display-owner", [NSString stringWithFormat:@"%u", width],
                           [NSString stringWithFormat:@"%u", height]];
    self.task.standardInput = self.control;
    self.task.standardOutput = self.reportPipe;
    int descriptor = self.reportPipe.fileHandleForReading.fileDescriptor;
    int flags = fcntl(descriptor, F_GETFL);
    NSError *error = nil;
    if (flags < 0 || fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) < 0 || ![self.task launchAndReturnError:&error]) {
        fprintf(stderr, "display_owner_launch_failed=%ld\n", (long)error.code);
        self.task = nil;
        [self stop];
        return NO;
    }
    [self.control.fileHandleForReading closeFile];
    [self.reportPipe.fileHandleForWriting closeFile];
    __block DisplayReport message = {0};
    __block size_t received = 0;
    __block BOOL ready = NO;
    (void)waitFor(7, ^BOOL{
        if (received < sizeof(message)) {
            ssize_t count = read(descriptor, (uint8_t *)&message + received, sizeof(message) - received);
            if (count > 0) received += (size_t)count;
        }
        BOOL valid = received == sizeof(message) && message.magic == displayReportMagic &&
                     message.display != kCGNullDirectDisplay && message.width == width && message.height == height;
        if (valid) self.displayID = message.display;
        // On this beta mode objects can be unavailable for newly added IDs even
        // in the parent. Query live pixel geometry, never substitute the request.
        if (valid && !message.status && self.running && onlineState(message.display) == 1) {
            CGRect bounds = CGDisplayBounds(message.display);
            ready = CGDisplayPixelsWide(message.display) == width && CGDisplayPixelsHigh(message.display) == height &&
                    bounds.size.width == width && bounds.size.height == height && CGDisplayIsActive(message.display);
        }
        return ready || !self.running || (valid && message.status);
    });
    printf("media_owner_ready=%d display=%u requested=%ux%u parent_verified=1\n", ready, self.displayID, width, height);
    if (!ready && self.displayID) {
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(self.displayID);
        fprintf(stderr, "media_owner_not_ready report_status=%u running=%d online=%d active=%d pixels=%zux%zu logical=%zux%zu hz=%.3f\n",
            message.status, self.running, onlineState(self.displayID), CGDisplayIsActive(self.displayID),
            mode ? CGDisplayModeGetPixelWidth(mode) : 0, mode ? CGDisplayModeGetPixelHeight(mode) : 0,
            mode ? CGDisplayModeGetWidth(mode) : 0, mode ? CGDisplayModeGetHeight(mode) : 0,
            mode ? CGDisplayModeGetRefreshRate(mode) : 0);
        if (mode) CGDisplayModeRelease(mode);
    }
    if (!ready) [self stop];
    return ready;
}
- (BOOL)stop {
    [self.control.fileHandleForWriting closeFile];
    BOOL stopped = waitFor(5, ^BOOL{ return !self.running && (!self.displayID || onlineState(self.displayID) == 0); });
    BOOL normal = self.task && !self.running && self.task.terminationReason == NSTaskTerminationReasonExit && self.task.terminationStatus == 0;
    BOOL expectedCrash = self.forcedCrash && !self.running &&
        self.task.terminationReason == NSTaskTerminationReasonUncaughtSignal && self.task.terminationStatus == SIGKILL;
    if (self.running) {
        (void)kill(self.task.processIdentifier, SIGKILL);
        [self.task waitUntilExit];
    }
    [self.reportPipe.fileHandleForReading closeFile];
    self.control = nil;
    self.reportPipe = nil;
    printf("media_owner_cleanup child_stopped=%d display_removed=%d normal_exit=%d expected_crash=%d parent_survived=1\n",
        !self.running, self.displayID && onlineState(self.displayID) == 0, normal, expectedCrash);
    return stopped && (normal || expectedCrash) && self.displayID != kCGNullDirectDisplay;
}
@end
