// SPDX-License-Identifier: GPL-3.0-or-later
// Experimental private-API qualification, never linked into the Host package.
#import "virtual-display-probe.h"

/** Create one bounded 1080p display, observe activation, then release it. */
int main(void) {
    @autoreleasepool {
        setbuf(stdout, NULL);
        (void)CGMainDisplayID();
        __block PLANKVirtualDisplay *display = createProbeDisplay(1920, 1080);
        if (!display) return 3;
        CGDirectDisplayID displayID = display.displayID;
        printf("created=%u requested=1920x1080@60 bounded_lifetime=10s\n", displayID);
        __block BOOL wasReady = NO;
        __block BOOL released = NO;
        __block int ticks = 0;
        __block int result = 5;
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
            0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, NSEC_PER_SEC, NSEC_PER_MSEC * 10);
        dispatch_source_set_event_handler(timer, ^{
            ticks++;
            if (!released) wasReady |= report(displayID, 1920, 1080);
            if (ticks == 10) {
                display = nil;
                released = YES;
                printf("released=%u\n", displayID);
            }
            if (released && (onlineState(displayID) == 0 || ticks >= 15)) {
                BOOL gone = onlineState(displayID) == 0;
                printf("ready_observed=%d cleanup_confirmed=%d\n", wasReady, gone);
                result = wasReady && gone ? 0 : 5;
                CFRunLoopStop(CFRunLoopGetMain());
            }
        });
        dispatch_resume(timer);
        CFRunLoopRun();
        dispatch_source_cancel(timer);
        return result;
    }
}
