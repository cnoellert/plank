// SPDX-License-Identifier: GPL-3.0-or-later
// Operator-observed LoginWindow motion only. Never keys, clicks or login actions.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import "session-boundary.h"
#import "input-events.h"
#include "plank_transport_input.h"
#include <math.h>
#include <time.h>

int PLANKRunNativeLoginPointer(void) {
    alarm(20); setbuf(stdout, NULL);
    @autoreleasepool {
        PLANKGraphicalSession initial = PLANKReadGraphicalSession();
        if (getuid() != 0 || initial.phase != PLANKSessionLoginWindow ||
            !CGPreflightPostEventAccess() || !AXIsProcessTrusted()) {
            fprintf(stderr, "login_pointer_scope_or_permission_denied\n"); return 2;
        }
        CGDirectDisplayID display = CGMainDisplayID();
        CGRect bounds = CGDisplayBounds(display);
        CGSize pixels = CGSizeMake(CGDisplayPixelsWide(display), CGDisplayPixelsHigh(display));
        CGEventRef first = CGEventCreate(NULL);
        CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStatePrivate);
        if (!first || !source || CGRectIsEmpty(bounds) || pixels.width < 2 || pixels.height < 2) {
            if (first) CFRelease(first);
            if (source) CFRelease(source);
            return 3;
        }
        CGPoint original = CGEventGetLocation(first); CFRelease(first);
        PLANKMacInputEvents *mapper = [[PLANKMacInputEvents alloc] initWithSource:source bounds:bounds
            pixels:pixels initialPosition:original doubleClickInterval:NSEvent.doubleClickInterval];
        if (!mapper) { CFRelease(source); return 3; }
        BOOL (^authorized)(void) = ^BOOL {
            return PLANKSessionMatches(initial, PLANKReadGraphicalSession()) &&
                CGPreflightPostEventAccess() && AXIsProcessTrusted() && CGMainDisplayID() == display &&
                CGRectEqualToRect(bounds, CGDisplayBounds(display)) &&
                pixels.width == CGDisplayPixelsWide(display) && pixels.height == CGDisplayPixelsHigh(display);
        };
        BOOL (^post)(CGEventRef) = ^BOOL(CGEventRef event) {
            if (!authorized() || CGEventGetType(event) != kCGEventMouseMoved) return NO;
            CGEventSetIntegerValueField(event, kCGEventSourceUserData, 0x504c414e4b);
            CGEventPost(kCGHIDEventTap, event); return YES;
        };
        __block unsigned stage = 0, observed = 0;
        __block CGPoint expected = original;
        __block BOOL moved = NO, restored = NO;
        __block int result = 5;
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
            2 * NSEC_PER_SEC, 10 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(timer, ^{
            if (!authorized()) {
                fprintf(stderr, "login_pointer_scope_revoked\n");
                result = 6; CFRunLoopStop(CFRunLoopGetMain()); return;
            }
            if (stage) {
                CGEventRef current = CGEventCreate(NULL);
                BOOL match = current && hypot(CGEventGetLocation(current).x - expected.x,
                    CGEventGetLocation(current).y - expected.y) <= 2;
                if (current) CFRelease(current);
                observed += match;
                printf("login_pointer target=%u observed_match=%d restore=%d\n", stage - 1, match, stage == 3);
            }
            if (stage < 2) {
                uint16_t coordinate = stage ? 49151 : 16384;
                uint8_t payload[8];
                plank_transport_input_encode_absolute_mouse(payload, coordinate, coordinate, 65535, 65535);
                expected = CGPointMake(bounds.origin.x + (double)coordinate / 65535 *
                    (bounds.size.width - bounds.size.width / pixels.width),
                    bounds.origin.y + (double)coordinate / 65535 *
                    (bounds.size.height - bounds.size.height / pixels.height));
                if ([mapper consumeType:1 payload:[NSData dataWithBytes:payload length:sizeof(payload)]
                    time:clock_gettime_nsec_np(CLOCK_UPTIME_RAW) accept:post] != PLANKMacInputEvent) {
                    result = 4; CFRunLoopStop(CFRunLoopGetMain()); return;
                }
                moved = YES;
            } else if (stage == 2) {
                expected = original;
                CGEventRef restore = CGEventCreateMouseEvent(source, kCGEventMouseMoved, original, kCGMouseButtonLeft);
                restored = restore && post(restore);
                if (restore) CFRelease(restore);
                if (!restored) { result = 4; CFRunLoopStop(CFRunLoopGetMain()); return; }
            } else {
                result = observed == 3 ? 0 : 5;
                CFRunLoopStop(CFRunLoopGetMain()); return;
            }
            stage++;
        });
        printf("login_pointer_start scope=sign-in source=private targets=2 clicks=0 keys=0\n");
        dispatch_resume(timer); CFRunLoopRun(); dispatch_source_cancel(timer);
        // If a local error ended the test early, restore only within the same
        // still-authorized scope. Never restore into a newly logged-in desktop.
        if (moved && !restored && authorized()) {
            CGEventRef restore = CGEventCreateMouseEvent(source, kCGEventMouseMoved, original, kCGMouseButtonLeft);
            if (restore) { restored = post(restore); CFRelease(restore); }
        }
        BOOL clean = [mapper stopAndCopyReleaseEvents].count == 0;
        CFRelease(source);
        printf("login_pointer_complete matches=%u restored=%d no_held_input=%d result=%d\n",
            observed, restored, clean, result);
        return result || !clean ? (result ? result : 7) : 0;
    }
}
