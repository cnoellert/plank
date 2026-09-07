// SPDX-License-Identifier: GPL-3.0-or-later
// Bounded system-event delivery to our own test window, never login credentials.
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ApplicationServices/ApplicationServices.h>
#include <math.h>

static const int64_t probeTag = 0x504c414e4b;

static void stopApp(void) {
    [NSApp stop:nil];
    // Wake AppKit if stop was requested from a dispatch callback, not an event.
    [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined
        location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0
        context:nil subtype:0 data1:0 data2:0] atStart:NO];
}

@interface PLANKInputView : NSView
@property(nonatomic) unsigned int received;
@end

@implementation PLANKInputView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)record:(NSEvent *)event bit:(unsigned int)bit {
    CGEventRef cg = event.CGEvent;
    // Never record user keystrokes or unrelated events.
    if (!cg || CGEventGetIntegerValueField(cg, kCGEventSourceUserData) != probeTag) return;
    self.received |= bit;
    printf("received_test_event=%u\n", bit);
}
- (void)mouseMoved:(NSEvent *)event { [self record:event bit:1]; }
- (void)mouseDown:(NSEvent *)event { [self record:event bit:2]; }
- (void)mouseDragged:(NSEvent *)event { [self record:event bit:4]; }
- (void)mouseUp:(NSEvent *)event { [self record:event bit:8]; }
- (void)rightMouseDown:(NSEvent *)event { [self record:event bit:16]; }
- (void)rightMouseUp:(NSEvent *)event { [self record:event bit:32]; }
- (void)scrollWheel:(NSEvent *)event { [self record:event bit:64]; }
- (void)keyDown:(NSEvent *)event { [self record:event bit:128]; }
- (void)keyUp:(NSEvent *)event { [self record:event bit:256]; }
@end

static BOOL postAt(CGEventRef event, CGEventTapLocation tap) {
    if (!event) return NO;
    CGEventSetFlags(event, 0);
    CGEventSetIntegerValueField(event, kCGEventSourceUserData, probeTag);
    CGEventPost(tap, event);
    CFRelease(event);
    return YES;
}

static BOOL post(CGEventRef event) { return postAt(event, kCGHIDEventTap); }

static BOOL mouseAt(CGEventSourceRef source, CGEventType type, CGPoint point, CGEventTapLocation tap) {
    CGMouseButton button = (type == kCGEventRightMouseDown || type == kCGEventRightMouseUp)
        ? kCGMouseButtonRight : kCGMouseButtonLeft;
    CGEventRef event = CGEventCreateMouseEvent(source, type, point, button);
    if (event) CGEventSetIntegerValueField(event, kCGMouseEventClickState, 1);
    return postAt(event, tap);
}

static BOOL mouse(CGEventSourceRef source, CGEventType type, CGPoint point) {
    return mouseAt(source, type, point, kCGHIDEventTap);
}

/** Global motion-only test: no focus change, keys, buttons, or permission prompt. */
int PLANKRunPointerProbe(CGEventSourceStateID state, CGEventTapLocation tap) {
    if (!CGPreflightPostEventAccess()) return 2;
    CGEventRef initial = CGEventCreate(NULL);
    CGEventSourceRef source = CGEventSourceCreate(state);
    printf("pointer_source_requested=%d actual=%d available=%d\n", state,
           source ? CGEventSourceGetSourceStateID(source) : -99, source != NULL);
    printf("pointer_post_location=%u\n", (unsigned int)tap);
    if (!initial || !source) {
        if (initial) CFRelease(initial);
        if (source) CFRelease(source);
        return 3;
    }
    CGPoint original = CGEventGetLocation(initial);
    CFRelease(initial);
    CGRect bounds = CGDisplayBounds(CGMainDisplayID());
    if (CGRectIsEmpty(bounds)) { CFRelease(source); return 3; }
    CGPoint targets[] = {
        CGPointMake(CGRectGetMinX(bounds) + bounds.size.width * 0.25,
                    CGRectGetMinY(bounds) + bounds.size.height * 0.25),
        CGPointMake(CGRectGetMinX(bounds) + bounds.size.width * 0.75,
                    CGRectGetMinY(bounds) + bounds.size.height * 0.75),
        original
    };
    BOOL passed = YES;
    for (unsigned int i = 0; i < 3; i++) {
        passed &= mouseAt(source, kCGEventMouseMoved, targets[i], tap);
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
        CGEventRef current = CGEventCreate(NULL);
        BOOL matches = NO;
        if (current) {
            CGPoint actual = CGEventGetLocation(current);
            matches = hypot(actual.x - targets[i].x, actual.y - targets[i].y) <= 2;
            CFRelease(current);
        }
        printf("pointer_target=%u observed_match=%d restore=%d\n", i, matches, i == 2);
        passed &= matches;
    }
    CFRelease(source);
    return passed ? 0 : 5;
}

int PLANKRunInputProbe(void) {
    if (!CGPreflightPostEventAccess() || !AXIsProcessTrusted()) {
        fprintf(stderr, "input_permission_denied\n");
        return 2;
    }
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSRunningApplication *previous = NSWorkspace.sharedWorkspace.frontmostApplication;
    CGEventRef initial = CGEventCreate(NULL);
    // Inventory source creation separately from event delivery. No fallback is
    // inferred: this probe explicitly uses Apple's daemon/device-driver source.
    CGEventSourceStateID states[] = { kCGEventSourceStatePrivate,
        kCGEventSourceStateCombinedSessionState, kCGEventSourceStateHIDSystemState };
    for (NSUInteger i = 0; i < sizeof(states) / sizeof(states[0]); i++) {
        CGEventSourceRef candidate = CGEventSourceCreate(states[i]);
        printf("event_source_state=%d available=%d\n", states[i], candidate != NULL);
        if (candidate) CFRelease(candidate);
    }
    CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    if (!initial || !source) {
        fprintf(stderr, "input_initialization_failed current_event=%d event_source=%d\n",
                initial != NULL, source != NULL);
        if (initial) CFRelease(initial);
        if (source) CFRelease(source);
        return 3;
    }
    CGPoint original = CGEventGetLocation(initial);
    CFRelease(initial);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 400)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.title = @"PLANK — bounded input delivery test";
    // Public AppKit opt-in for this temporary pre-login receiver window.
    window.canBecomeVisibleWithoutLogin = YES;
    window.releasedWhenClosed = NO;
    window.acceptsMouseMovedEvents = YES;
    PLANKInputView *view = [[PLANKInputView alloc] initWithFrame:NSMakeRect(0, 0, 640, 400)];
    window.contentView = view;
    [window center];
    [window makeKeyAndOrderFront:nil];
    [window makeFirstResponder:view];
    // Use the same explicit activation as the existing permission-setup window.
    [NSApp activateIgnoringOtherApps:YES];

    __block int ticks = 0;
    __block int result = 5;
    __block BOOL posted = YES;
    __block BOOL moved = NO;
    __block BOOL positionPassed = NO;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
        0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                              NSEC_PER_SEC / 4, NSEC_PER_MSEC * 10);
    dispatch_source_set_event_handler(timer, ^{
        // Avoid sending any keys/buttons into a foreign app or LoginWindow.
        if (!NSApp.active || !window.keyWindow || window.firstResponder != view) {
            fprintf(stderr, "input_test_refused_no_owned_focus active=%d key=%d\n",
                    NSApp.active, window.keyWindow);
            result = 6;
            stopApp();
            return;
        }
        NSPoint cocoa = [window convertPointToScreen:NSMakePoint(320, 200)];
        CGPoint point = CGPointMake(cocoa.x, CGRectGetHeight(CGDisplayBounds(CGMainDisplayID())) - cocoa.y);
        switch (ticks++) {
            case 0:
                posted &= mouse(source, kCGEventMouseMoved, point);
                moved = YES;
                break;
            case 1: {
                CGEventRef current = CGEventCreate(NULL);
                if (current) {
                    CGPoint actual = CGEventGetLocation(current);
                    positionPassed = hypot(actual.x - point.x, actual.y - point.y) <= 2;
                    CFRelease(current);
                }
                printf("absolute_pointer_position_verified=%d\n", positionPassed);
                // Down/drag/up are paired in one invocation even if focus changes later.
                posted &= mouse(source, kCGEventLeftMouseDown, point);
                posted &= mouse(source, kCGEventLeftMouseDragged, CGPointMake(point.x + 20, point.y + 10));
                posted &= mouse(source, kCGEventLeftMouseUp, point);
                break;
            }
            case 2:
                posted &= mouse(source, kCGEventRightMouseDown, point);
                posted &= mouse(source, kCGEventRightMouseUp, point);
                break;
            case 3:
                posted &= post(CGEventCreateScrollWheelEvent(source, kCGScrollEventUnitPixel, 1, 20));
                break;
            case 4:
                posted &= post(CGEventCreateKeyboardEvent(source, 0, true));
                posted &= post(CGEventCreateKeyboardEvent(source, 0, false));
                break;
            default:
                if (view.received == 511 || ticks >= 20) {
                    result = posted && positionPassed && view.received == 511 ? 0 : 5;
                    stopApp();
                }
                break;
        }
    });
    dispatch_resume(timer);
    [NSApp run];
    dispatch_source_cancel(timer);
    [window orderOut:nil];
    [window close];
    if (moved) (void)mouse(source, kCGEventMouseMoved, original);
    CFRelease(source);
    if (previous && previous.processIdentifier != NSProcessInfo.processInfo.processIdentifier)
        [previous activateWithOptions:0];
    printf("input_received_mask=%u expected_mask=511 result=%d\n", view.received, result);
    return result;
}
