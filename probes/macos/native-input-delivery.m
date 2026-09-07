// SPDX-License-Identifier: GPL-3.0-or-later
// Production packet mapper, own-window delivery only. No network or credentials.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import "input-events.h"
#include "plank_transport_input.h"
#include <math.h>
#include <time.h>
#include <unistd.h>

int PLANKRunNativeLoginPointer(void);

static const int64_t tag = 0x504c414e4b;
static void finish(void) {
    [NSApp stop:nil];
    [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined
        location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
        subtype:0 data1:0 data2:0] atStart:NO];
}
@interface PLANKNativeInputView : NSView
@property unsigned received;
@property unsigned modifiersDown;
@property unsigned modifiersUp;
@property BOOL cleanupPhase;
@property unsigned cleanupReleased;
@property BOOL shiftClick;
@property BOOL shiftKey;
@end
@implementation PLANKNativeInputView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)record:(NSEvent *)event bit:(unsigned)bit {
    CGEventRef value = event.CGEvent;
    if (value && CGEventGetIntegerValueField(value, kCGEventSourceUserData) == tag)
        self.received |= bit; // No user input/contents/coordinates are recorded.
}
- (void)mouseMoved:(NSEvent *)event { [self record:event bit:1]; }
- (BOOL)isTagged:(NSEvent *)event {
    return event.CGEvent && CGEventGetIntegerValueField(event.CGEvent, kCGEventSourceUserData) == tag;
}
- (void)mouseDown:(NSEvent *)event {
    [self record:event bit:2];
    if (self.cleanupPhase && [self isTagged:event] && (event.modifierFlags & NSEventModifierFlagShift))
        self.shiftClick = YES;
}
- (void)mouseDragged:(NSEvent *)event { [self record:event bit:4]; }
- (void)mouseUp:(NSEvent *)event {
    [self record:event bit:8];
    if (self.cleanupPhase && [self isTagged:event]) self.cleanupReleased |= 4;
}
- (void)rightMouseDown:(NSEvent *)event { [self record:event bit:16]; }
- (void)rightMouseUp:(NSEvent *)event { [self record:event bit:32]; }
- (void)scrollWheel:(NSEvent *)event {
    if (event.scrollingDeltaY != 0) [self record:event bit:64];
    if (event.scrollingDeltaX != 0) [self record:event bit:512];
}
- (void)keyDown:(NSEvent *)event {
    [self record:event bit:128];
    if (self.cleanupPhase && [self isTagged:event] && event.keyCode == 0 &&
        (event.modifierFlags & NSEventModifierFlagShift)) self.shiftKey = YES;
}
- (void)keyUp:(NSEvent *)event {
    [self record:event bit:256];
    if (self.cleanupPhase && [self isTagged:event] && event.keyCode == 0) self.cleanupReleased |= 1;
}
- (void)flagsChanged:(NSEvent *)event {
    if (![self isTagged:event]) return;
    const unsigned codes[] = {56, 60, 59, 62, 58, 61, 55, 54};
    const NSEventModifierFlags flags[] = {NSEventModifierFlagShift, NSEventModifierFlagControl,
        NSEventModifierFlagOption, NSEventModifierFlagCommand};
    for (unsigned i = 0; i < 8; ++i) if (event.keyCode == codes[i]) {
        if (event.modifierFlags & flags[i / 2]) self.modifiersDown |= 1u << i;
        else {
            self.modifiersUp |= 1u << i;
            if (self.cleanupPhase && event.keyCode == 56) self.cleanupReleased |= 2;
        }
    }
}
@end
int main(int argc, const char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--login-pointer")) return PLANKRunNativeLoginPointer();
    if (argc != 2 || strcmp(argv[1], "--input") || getuid() == 0) return 2;
    alarm(30);
    @autoreleasepool {
        if (!CGPreflightPostEventAccess() || !AXIsProcessTrusted()) {
            fprintf(stderr, "native_input_permission_denied\n"); return 2;
        }
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSRunningApplication *previous = NSWorkspace.sharedWorkspace.frontmostApplication;
        CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStatePrivate);
        CGEventRef initial = CGEventCreate(NULL);
        if (!source || !initial) return 3;
        CGPoint original = CGEventGetLocation(initial); CFRelease(initial);
        CGDirectDisplayID display = CGMainDisplayID(); CGRect bounds = CGDisplayBounds(display);
        CGSize pixels = CGSizeMake(CGDisplayPixelsWide(display), CGDisplayPixelsHigh(display));
        PLANKMacInputEvents *mapper = [[PLANKMacInputEvents alloc] initWithSource:source
            bounds:bounds pixels:pixels initialPosition:original doubleClickInterval:NSEvent.doubleClickInterval];
        if (!mapper) { CFRelease(source); return 3; }
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 400)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        window.title = @"PLANK — native input qualification";
        window.releasedWhenClosed = NO; window.acceptsMouseMovedEvents = YES;
        PLANKNativeInputView *view = [[PLANKNativeInputView alloc] initWithFrame:NSMakeRect(0, 0, 640, 400)];
        window.contentView = view; [window center];
        // Activation requested before AppKit completes launch can be ignored
        // for a launchd-started agent. Activate once, after the lifecycle event;
        // never retry stealing focus or weaken the per-event focus check.
        id launchObserver = [NSNotificationCenter.defaultCenter
            addObserverForName:NSApplicationDidFinishLaunchingNotification object:NSApp queue:nil
            usingBlock:^(NSNotification *notification) {
                (void)notification;
                [window makeKeyAndOrderFront:nil]; [window makeFirstResponder:view];
                [NSApp activateIgnoringOtherApps:YES];
            }];
        BOOL (^ownedFocus)(void) = ^BOOL {
            return NSApp.active && window.keyWindow && window.firstResponder == view && CGPreflightPostEventAccess();
        };
        BOOL (^post)(uint8_t, const uint8_t *, size_t) = ^BOOL(uint8_t type, const uint8_t *data, size_t size) {
            return [mapper consumeType:type payload:[NSData dataWithBytes:data length:size]
                time:clock_gettime_nsec_np(CLOCK_UPTIME_RAW) accept:^BOOL(CGEventRef event) {
                    if (!ownedFocus()) return NO;
                    CGEventSetIntegerValueField(event, kCGEventSourceUserData, tag);
                    CGEventPost(kCGHIDEventTap, event); return YES;
                }] == PLANKMacInputEvent;
        };
        BOOL (^move)(CGPoint) = ^BOOL(CGPoint point) {
            uint8_t data[8];
            double x = (point.x - bounds.origin.x) / (bounds.size.width - bounds.size.width / pixels.width);
            double y = (point.y - bounds.origin.y) / (bounds.size.height - bounds.size.height / pixels.height);
            if (x < 0 || x > 1 || y < 0 || y > 1) return NO;
            plank_transport_input_encode_absolute_mouse(data, (uint16_t)llround(x * 65535),
                (uint16_t)llround(y * 65535), 65535, 65535);
            return post(1, data, sizeof(data));
        };
        __block unsigned ticks = 0; __block BOOL passed = YES, moved = NO, positionMatch = NO;
        __block BOOL heldStateVerified = NO, cleanupStateVerified = NO;
        __block int result = 5;
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
            NSEC_PER_SEC / 4, 10 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(timer, ^{
            if (!ownedFocus()) {
                fprintf(stderr, "native_input_refused_foreign_focus active=%d key=%d responder=%d permission=%d\n",
                    NSApp.active, window.keyWindow, window.firstResponder == view, CGPreflightPostEventAccess());
                result = 6; finish(); return;
            }
            NSPoint cocoa = [window convertPointToScreen:NSMakePoint(320, 200)];
            CGPoint center = CGPointMake(cocoa.x, CGRectGetHeight(CGDisplayBounds(CGMainDisplayID())) - cocoa.y);
            switch (ticks++) {
                case 0: passed &= move(center); moved = YES; break;
                case 1: {
                    CGEventRef current = CGEventCreate(NULL);
                    if (current) {
                        CGPoint actual = CGEventGetLocation(current);
                        positionMatch = hypot(actual.x - center.x, actual.y - center.y) <= 2;
                        CFRelease(current);
                    }
                    passed &= post(2, (uint8_t[]){1, 1}, 2);
                    passed &= move(CGPointMake(center.x + 20, center.y + 10));
                    passed &= post(2, (uint8_t[]){1, 0}, 2);
                    break;
                }
                case 2:
                    passed &= post(2, (uint8_t[]){3, 1}, 2);
                    passed &= post(2, (uint8_t[]){3, 0}, 2); break;
                case 3:
                    passed &= post(3, (uint8_t[]){0, 120}, 2);
                    passed &= post(4, (uint8_t[]){0, 120}, 2); break;
                case 4:
                    passed &= post(5, (uint8_t[]){0x80, 0x41, 1, 0, 0}, 5);
                    passed &= post(5, (uint8_t[]){0x80, 0x41, 0, 0, 0}, 5); break;
                default:
                    if (ticks <= 21) {
                        // Each left/right modifier is held for one timer tick.
                        // No letter is posted while Command/Option/Control is held.
                        unsigned index = (ticks - 6) / 2; BOOL down = !(ticks & 1);
                        const uint8_t keys[] = {0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0x5b, 0x5c};
                        uint8_t bytes[] = {0x80, keys[index], down, down ? (1u << (index / 2)) : 0, 0};
                        passed &= post(5, bytes, sizeof(bytes));
                    } else if (ticks == 22) {
                        view.cleanupPhase = YES;
                        passed &= post(5, (uint8_t[]){0x80, 0xa0, 1, 1, 0}, 5);
                        passed &= post(5, (uint8_t[]){0x80, 0x41, 1, 1, 0}, 5);
                        passed &= post(2, (uint8_t[]){1, 1}, 2);
                    } else if (ticks == 23) {
                        CGEventSourceStateID state = CGEventSourceGetSourceStateID(source);
                        heldStateVerified = CGEventSourceKeyState(state, 0) &&
                            CGEventSourceButtonState(state, kCGMouseButtonLeft) &&
                            (CGEventSourceFlagsState(state) & kCGEventFlagMaskShift);
                        NSArray *releases = [mapper stopAndCopyReleaseEvents];
                        passed &= releases.count == 3;
                        for (id value in releases) if (ownedFocus()) {
                            CGEventRef event = (__bridge CGEventRef)value;
                            CGEventSetIntegerValueField(event, kCGEventSourceUserData, tag);
                            CGEventPost(kCGHIDEventTap, event);
                        } else passed = NO;
                        passed &= [mapper stopAndCopyReleaseEvents].count == 0;
                        passed &= [mapper consumeType:5 payload:[NSData dataWithBytes:(uint8_t[]){0x80, 0x41, 1, 0, 0} length:5]
                            time:clock_gettime_nsec_np(CLOCK_UPTIME_RAW) accept:^BOOL(CGEventRef event) {
                                (void)event; return NO;
                            }] == PLANKMacInputStopped;
                    } else {
                        CGEventSourceStateID state = CGEventSourceGetSourceStateID(source);
                        cleanupStateVerified = !CGEventSourceKeyState(state, 0) &&
                            !CGEventSourceButtonState(state, kCGMouseButtonLeft) &&
                            !(CGEventSourceFlagsState(state) & (kCGEventFlagMaskShift | kCGEventFlagMaskControl |
                                kCGEventFlagMaskAlternate | kCGEventFlagMaskCommand));
                        BOOL complete = view.received == 1023 && view.modifiersDown == 255 && view.modifiersUp == 255 &&
                            view.cleanupReleased == 7 && view.shiftClick && view.shiftKey && cleanupStateVerified;
                        if (complete || ticks >= 35) {
                            result = passed && positionMatch && heldStateVerified && complete ? 0 : 5; finish();
                        }
                    }
                    break;
            }
        });
        dispatch_resume(timer); [NSApp run]; dispatch_source_cancel(timer);
        [NSNotificationCenter.defaultCenter removeObserver:launchObserver];
        for (id event in [mapper stopAndCopyReleaseEvents]) if (ownedFocus())
            CGEventPost(kCGHIDEventTap, (__bridge CGEventRef)event);
        [window orderOut:nil]; [window close];
        if (moved) {
            CGEventRef restore = CGEventCreateMouseEvent(source, kCGEventMouseMoved, original, kCGMouseButtonLeft);
            if (restore) { CGEventPost(kCGHIDEventTap, restore); CFRelease(restore); }
        }
        CFRelease(source);
        if (previous && previous.processIdentifier != NSProcessInfo.processInfo.processIdentifier)
            [previous activateWithOptions:0];
        printf("native_input_delivery received_mask=%u expected_mask=1023 position_match=%d result=%d\n", view.received, positionMatch, result);
        printf("native_input_modifiers down=%u up=%u expected=255 shift_key=%d shift_click=%d held=%d cleanup_received=%u expected_cleanup=7 released=%d\n",
            view.modifiersDown, view.modifiersUp, view.shiftKey, view.shiftClick, heldStateVerified, view.cleanupReleased, cleanupStateVerified);
        return result;
    }
}
