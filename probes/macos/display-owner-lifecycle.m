// SPDX-License-Identifier: GPL-3.0-or-later
// Qualification only: parent survives normal/crashed virtual-display owners.
#import "virtual-display-probe.h"
#include <mach-o/dyld.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>
#include <limits.h>

typedef struct { uint32_t magic, display, width, height, status; } OwnerReport;
static const uint32_t reportMagic = 0x504c4e4b;

static int runOwner(void) {
    @autoreleasepool {
        PLANKVirtualDisplay *display = createProbeDisplay(3840, 2160);
        if (!display) return 3;
        CGDirectDisplayID target = display.displayID;
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
        OwnerReport message = {reportMagic, target, 0, 0, 4};
        if (!CGDisplayIsInMirrorSet(target)) {
            message.width = CGDisplayPixelsWide(target) == 3840 ? 1920 : 3840;
            message.height = message.width == 1920 ? 1080 : 2160;
            CFArrayRef modes = CGDisplayCopyAllDisplayModes(target, NULL);
            if (modes && CFArrayGetCount(modes) < 128) {
                for (CFIndex i = 0; i < CFArrayGetCount(modes); ++i) {
                    CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
                    if (CGDisplayModeGetPixelWidth(mode) == message.width &&
                        CGDisplayModeGetPixelHeight(mode) == message.height &&
                        CGDisplayModeGetWidth(mode) == message.width &&
                        CGDisplayModeGetHeight(mode) == message.height &&
                        fabs(CGDisplayModeGetRefreshRate(mode) - 60) < 0.01) {
                        message.status = CGDisplaySetDisplayMode(target, mode, NULL) == kCGErrorSuccess ? 0 : 4;
                        break;
                    }
                }
            }
            if (modes) CFRelease(modes);
        }
        if (write(STDOUT_FILENO, &message, sizeof(message)) != sizeof(message)) return 4;
        if (message.status) return (int)message.status;
        // Permit the parent to observe the real mode change before exit/kill.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            CFRunLoopStop(CFRunLoopGetMain());
        });
        CFRunLoopRun();
        display = nil;
    }
    return 0;
}

static BOOL runParentCase(NSString *executable, BOOL crashOwner) {
    NSPipe *pipe = [NSPipe pipe];
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:executable];
    task.arguments = @[@"--owner"];
    task.standardOutput = pipe;
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    NSError *error = nil;
    int descriptor = pipe.fileHandleForReading.fileDescriptor;
    int flags = fcntl(descriptor, F_GETFL);
    if (flags < 0 || fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) < 0 ||
        ![task launchAndReturnError:&error]) return NO;
    __block OwnerReport message = {0};
    __block size_t received = 0;
    __block unsigned int ticks = 0;
    __block BOOL observedLive = NO, killed = NO, passed = NO;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, NSEC_PER_MSEC * 100, NSEC_PER_MSEC * 10);
    dispatch_source_set_event_handler(timer, ^{
        ticks++;
        if (received < sizeof(message)) {
            ssize_t count = read(descriptor, (uint8_t *)&message + received, sizeof(message) - received);
            if (count > 0) received += (size_t)count;
        }
        BOOL valid = received == sizeof(message) && message.magic == reportMagic && message.status == 0 &&
                     message.display != kCGNullDirectDisplay &&
                     ((message.width == 1920 && message.height == 1080) ||
                      (message.width == 3840 && message.height == 2160));
        if (valid && task.running && onlineState(message.display) == 1 &&
            CGDisplayPixelsWide(message.display) == message.width &&
            CGDisplayPixelsHigh(message.display) == message.height) observedLive = YES;
        if (crashOwner && observedLive && task.running && !killed) {
            // Only this NSTask child, never a searched PID or another service.
            killed = kill(task.processIdentifier, SIGKILL) == 0;
        }
        if (valid && observedLive && !task.running && onlineState(message.display) == 0) {
            passed = crashOwner ? killed && task.terminationReason == NSTaskTerminationReasonUncaughtSignal &&
                                  task.terminationStatus == SIGKILL :
                                  task.terminationReason == NSTaskTerminationReasonExit && task.terminationStatus == 0;
            CFRunLoopStop(CFRunLoopGetMain());
        } else if (ticks >= 120 || (!task.running && !valid)) CFRunLoopStop(CFRunLoopGetMain());
    });
    dispatch_resume(timer);
    CFRunLoopRun();
    dispatch_source_cancel(timer);
    if (task.running) { (void)kill(task.processIdentifier, SIGKILL); [task waitUntilExit]; }
    [pipe.fileHandleForReading closeFile];
    [pipe.fileHandleForWriting closeFile];
    printf("owner_lifecycle case=%s live_mode_verified=%d child_stopped=%d display_removed=%d parent_survived=1 passed=%d\n",
        crashOwner ? "sigkill" : "normal", observedLive, !task.running,
        received == sizeof(message) && message.magic == reportMagic && onlineState(message.display) == 0, passed);
    return passed;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--owner") == 0) return runOwner();
        if (argc != 1) return 2;
        setbuf(stdout, NULL);
        char path[PATH_MAX];
        uint32_t size = sizeof(path);
        if (_NSGetExecutablePath(path, &size)) return 2;
        NSString *executable = [[NSString stringWithUTF8String:path] stringByStandardizingPath];
        if (!runParentCase(executable, NO)) return 7;
        return runParentCase(executable, YES) ? 0 : 7;
    }
}
