// SPDX-License-Identifier: GPL-3.0-or-later
// Operator-directed, bounded, listen-only mouse/focus diagnostic. No key mask,
// text, window titles, screenshots, input posting, focus changes or TCC prompts.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <unistd.h>

static unsigned sequence;
static double started;
static double elapsed(void) { return CFAbsoluteTimeGetCurrent() - started; }

static void foreground(unsigned click, const char *phase) {
    NSRunningApplication *app = NSWorkspace.sharedWorkspace.frontmostApplication;
    printf("t=%.3f click=%u phase=%s foreground_pid=%d bundle=%s\n", elapsed(),
        click, phase, app.processIdentifier, app.bundleIdentifier.UTF8String ?: "unknown");
}

static void target(unsigned click, CGPoint point) {
    // AX is queried outside the event-tap callback. A slow/unresponsive target
    // must not stall the input path. Never fetch AXValue, title or document URL.
    AXUIElementRef system = AXUIElementCreateSystemWide(), element = NULL;
    AXUIElementSetMessagingTimeout(system, 0.1f);
    AXError result = AXUIElementCopyElementAtPosition(system, point.x, point.y, &element);
    pid_t pid = 0;
    if (result == kAXErrorSuccess && element) {
        AXUIElementSetMessagingTimeout(element, 0.1f);
        AXUIElementGetPid(element, &pid);
    }
    printf("t=%.3f click=%u target_ax_result=%d target_pid=%d target_bundle=%s\n",
        elapsed(), click, result, pid,
        pid ? ([NSRunningApplication runningApplicationWithProcessIdentifier:pid].bundleIdentifier.UTF8String ?: "unknown") : "unknown");
    if (element) CFRelease(element);
    CFRelease(system);
}

static CGEventRef observe(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *context) {
    (void)proxy; (void)context;
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        printf("t=%.3f tap_disabled=%u trace_stopping=1\n", elapsed(), type);
        CFRunLoopStop(CFRunLoopGetMain());
        return event;
    }
    BOOL down = type == kCGEventLeftMouseDown || type == kCGEventRightMouseDown || type == kCGEventOtherMouseDown;
    CGPoint point = CGEventGetLocation(event);
    unsigned click = down ? ++sequence : sequence;
    // Capture only scalar mouse metadata while the event exists. Do not retain
    // event objects or inspect keyboard payloads in a global observer.
    uint64_t flags = CGEventGetFlags(event);
    int64_t sourcePID = CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID);
    int64_t sourceState = CGEventGetIntegerValueField(event, kCGEventSourceStateID);
    int64_t button = CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
    int64_t clicks = CGEventGetIntegerValueField(event, kCGMouseEventClickState);
    int64_t window = CGEventGetIntegerValueField(event, kCGMouseEventWindowUnderMousePointer);
    int64_t handler = CGEventGetIntegerValueField(event, kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent);
    CGEventTimestamp timestamp = CGEventGetTimestamp(event);
    dispatch_async(dispatch_get_main_queue(), ^{
        printf("t=%.3f click=%u mouse_type=%u x=%.1f y=%.1f flags=0x%llx source_pid=%lld source_state=%lld button=%lld count=%lld window=%lld handler=%lld timestamp=%llu\n",
            elapsed(), click, type, point.x, point.y, (unsigned long long)flags,
            (long long)sourcePID, (long long)sourceState, (long long)button,
            (long long)clicks, (long long)window, (long long)handler, (unsigned long long)timestamp);
        foreground(click, "observed");
        if (down) {
            target(click, point);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                foreground(click, "after-500ms");
            });
        }
    });
    return event; // listen-only tap cannot alter delivery
}

int main(void) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        NSDictionary *session = CFBridgingRelease(CGSessionCopyCurrentDictionary());
        if (!session || ![session[(__bridge NSString *)kCGSessionOnConsoleKey] boolValue] ||
            [session[(__bridge NSString *)kCGSessionUserIDKey] unsignedIntValue] != getuid() || getuid() == 0) {
            fprintf(stderr, "trace_requires_current_nonroot_console_user\n"); return 2;
        }
        started = CFAbsoluteTimeGetCurrent();
        printf("trace_seconds=120 keyboard_mask=0 posting=0 focus_changes=0 ax_trusted=%d listen_access=%d\n",
            AXIsProcessTrusted(), CGPreflightListenEventAccess());
        CGEventMask mask = CGEventMaskBit(kCGEventLeftMouseDown) | CGEventMaskBit(kCGEventLeftMouseUp) |
            CGEventMaskBit(kCGEventRightMouseDown) | CGEventMaskBit(kCGEventRightMouseUp) |
            CGEventMaskBit(kCGEventOtherMouseDown) | CGEventMaskBit(kCGEventOtherMouseUp);
        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGTailAppendEventTap,
            kCGEventTapOptionListenOnly, mask, observe, NULL);
        if (!tap) { fprintf(stderr, "mouse_trace_permission_unavailable\n"); return 3; }
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        if (!source) { CFRelease(tap); return 4; }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        id observer = [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidActivateApplicationNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            (void)note; foreground(0, "activation-notification");
        }];
        foreground(0, "initial");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            CFRunLoopStop(CFRunLoopGetMain());
        });
        printf("trace_ready=1\n");
        CFRunLoopRun();
        [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:observer];
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CFMachPortInvalidate(tap); CFRelease(source); CFRelease(tap);
        printf("trace_finished=1 clicks=%u\n", sequence);
    }
    return 0;
}
