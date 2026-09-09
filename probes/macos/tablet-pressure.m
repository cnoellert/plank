// SPDX-License-Identifier: GPL-3.0-or-later
// Public Quartz tablet qualification. Generated events only, no network/device
// capture. --inspect never posts; --tablet-pressure requires our owned window.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import "session-boundary.h"
#include <math.h>
#include <unistd.h>

static const int64_t tag = 0x504c50454e00;
static const double pressures[] = {0, .25, .75, .5, 0, 0};
static CGEventRef penEvent(CGEventSourceRef source, CGPoint point, unsigned stage) {
    BOOL proximity = stage == 0 || stage == 5;
    CGEventType type = stage == 1 ? kCGEventLeftMouseDown : stage == 4 ? kCGEventLeftMouseUp :
        proximity ? kCGEventMouseMoved : kCGEventLeftMouseDragged;
    CGEventRef event = CGEventCreateMouseEvent(source, type, point, kCGMouseButtonLeft);
    if (!event) return NULL;
    CGEventSetIntegerValueField(event, kCGEventSourceUserData, tag + stage);
    if (proximity) {
        CGEventSetType(event, kCGEventTabletProximity);
        CGEventSetIntegerValueField(event, kCGTabletProximityEventEnterProximity, stage == 0);
        CGEventSetIntegerValueField(event, kCGTabletProximityEventPointerType, NSPointingDeviceTypePen);
        CGEventSetIntegerValueField(event, kCGTabletProximityEventDeviceID, 1);
        CGEventSetIntegerValueField(event, kCGTabletProximityEventPointerID, 1);
        CGEventSetIntegerValueField(event, kCGTabletProximityEventSystemTabletID, 1);
    } else {
        CGEventSetIntegerValueField(event, kCGMouseEventSubtype, kCGEventMouseSubtypeTabletPoint);
        CGEventSetIntegerValueField(event, kCGTabletEventDeviceID, 1);
        CGEventSetIntegerValueField(event, kCGTabletEventPointButtons, stage == 4 ? 0 : 1);
        CGEventSetIntegerValueField(event, kCGTabletEventPointX, llround(point.x));
        CGEventSetIntegerValueField(event, kCGTabletEventPointY, llround(point.y));
        CGEventSetDoubleValueField(event, kCGMouseEventPressure, pressures[stage]);
        CGEventSetDoubleValueField(event, kCGTabletEventPointPressure, pressures[stage]);
    }
    return event;
}
static BOOL inspect(NSEvent *event, unsigned stage) {
    if (stage == 0 || stage == 5)
        return event.type == NSEventTypeTabletProximity && event.enteringProximity == (stage == 0) &&
            event.pointingDeviceType == NSPointingDeviceTypePen;
    return event.subtype == NSEventSubtypeTabletPoint && fabs(event.pressure - pressures[stage]) < .01;
}
int main(int argc, const char **argv) {
    BOOL deliver = argc == 2 && !strcmp(argv[1], "--tablet-pressure");
    if (argc != 2 || (!deliver && strcmp(argv[1], "--inspect"))) return 2;
    alarm(20);
    @autoreleasepool {
        CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStatePrivate);
        if (!source) return 3;
        if (!deliver) {
            for (unsigned i = 0; i < 6; ++i) {
                CGEventRef event = penEvent(source, CGPointMake(100, 100), i);
                BOOL good = event && inspect([NSEvent eventWithCGEvent:event], i);
                if (event) CFRelease(event);
                if (!good) { fprintf(stderr, "tablet_inspection_failed stage=%u\n", i); CFRelease(source); return 4; }
            }
            CFRelease(source);
            puts("tablet_inspection_pass stages=6 pressure=1 proximity=1 posted=0"); return 0;
        }
        PLANKGraphicalSession initial = PLANKReadGraphicalSession();
        if (initial.phase != PLANKSessionDesktop || !CGPreflightPostEventAccess() || !AXIsProcessTrusted()) {
            CFRelease(source); fprintf(stderr, "tablet_probe_requires_consented_desktop\n"); return 5;
        }
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSRunningApplication *previous = NSWorkspace.sharedWorkspace.frontmostApplication;
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 300)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        window.title = @"PLANK — synthetic pressure test";
        window.releasedWhenClosed = NO;
        window.contentView = [NSView new];
        [window center];
        __block unsigned received = 0;
        __block unsigned stage = 0;
        __block CGPoint lastPoint = CGPointZero;
        __block int result = 6;
        BOOL (^safe)(void) = ^BOOL {
            return NSApp.active && window.keyWindow &&
                PLANKSessionMatches(initial, PLANKReadGraphicalSession()) && CGPreflightPostEventAccess();
        };
        void (^finish)(void) = ^{
            if (stage > 1 && stage < 5 && PLANKSessionMatches(initial, PLANKReadGraphicalSession())) {
                CGEventRef release = penEvent(source, lastPoint, 4);
                if (release) { CGEventPostToPid(getpid(), release); CFRelease(release); }
            }
            [NSApp stop:nil];
            [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint
                modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:NO];
        };
        id monitor = [NSEvent addLocalMonitorForEventsMatchingMask:
            NSEventMaskTabletProximity | NSEventMaskLeftMouseDown | NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp
            handler:^NSEvent *(NSEvent *event) {
                CGEventRef cg = event.CGEvent;
                int64_t index = cg ? CGEventGetIntegerValueField(cg, kCGEventSourceUserData) - tag : -1;
                if (index >= 0 && index < 6 && inspect(event, (unsigned)index)) received |= 1u << index;
                return event;
            }];
        id launched = [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidFinishLaunchingNotification
            object:NSApp queue:nil usingBlock:^(NSNotification *note) {
                (void)note; [window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
            }];
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
            NSEC_PER_SEC / 4, NSEC_PER_MSEC);
        dispatch_source_set_event_handler(timer, ^{
            if (!safe()) { fprintf(stderr, "tablet_probe_refused_foreign_focus\n"); finish(); return; }
            if (stage == 6) {
                result = received == 63 ? 0 : 7;
                printf("tablet_delivery_mask=%u expected=63 result=%d\n", received, result);
                finish(); return;
            }
            // Target only this process. Space samples so WindowServer does not
            // coalesce the two deliberately different pressure measurements.
            NSPoint cocoa = [window convertPointToScreen:NSMakePoint(300 + stage * 5, 150)];
            lastPoint = CGPointMake(cocoa.x, CGRectGetHeight(CGDisplayBounds(CGMainDisplayID())) - cocoa.y);
            CGEventRef event = penEvent(source, lastPoint, stage);
            if (!event) { finish(); return; }
            CGEventPostToPid(getpid(), event); CFRelease(event); ++stage;
        });
        dispatch_resume(timer); [NSApp run]; dispatch_source_cancel(timer);
        [NSEvent removeMonitor:monitor]; [NSNotificationCenter.defaultCenter removeObserver:launched];
        [window close];
        if (PLANKSessionMatches(initial, PLANKReadGraphicalSession()) && NSApp.active)
            [previous activateWithOptions:0];
        CFRelease(source); return result;
    }
}
