// SPDX-License-Identifier: GPL-3.0-or-later
// Exercise the real tap's owner/control queues and cancellation, with only HAL
// preparation/activation/destruction replaced. No permission requests or IO.
#import "audio-tap.h"
#import "audio-tap-system-alerts.h"
#include <stdatomic.h>
#include <assert.h>
#include <stdio.h>

@interface PLANKMacAudioTap (LifecycleTestBoundary)
- (BOOL)prepare;
- (BOOL)activate;
- (void)destroy;
@end
@interface TestTap : PLANKMacAudioTap {
@public
    dispatch_semaphore_t entered, releasePrepare, destroyed, releaseDestroy;
    atomic_int activations, callbacks, stops;
    BOOL permitted, holdDestroy;
}
@end
@implementation TestTap
- (BOOL)prepare {
    dispatch_semaphore_signal(entered);
    assert(!dispatch_semaphore_wait(releasePrepare, dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC)));
    return permitted;
}
- (BOOL)activate { atomic_fetch_add(&activations, 1); return YES; }
- (void)destroy {
    dispatch_semaphore_signal(destroyed);
    if (holdDestroy)
        assert(!dispatch_semaphore_wait(releaseDestroy, dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC)));
}
@end

static void waitFor(dispatch_semaphore_t signal) {
    assert(!dispatch_semaphore_wait(signal, dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC)));
}
static TestTap *makeTap(dispatch_queue_t owner) {
    TestTap *tap = [[TestTap alloc] initWithQueue:owner sample:^BOOL(CMSampleBufferRef sample) {
        (void)sample; assert(0); return NO;
    } failed:^{ assert(0); }];
    assert(tap);
    tap->entered = dispatch_semaphore_create(0);
    tap->releasePrepare = dispatch_semaphore_create(0);
    tap->destroyed = dispatch_semaphore_create(0);
    tap->releaseDestroy = dispatch_semaphore_create(0);
    atomic_init(&tap->activations, 0); atomic_init(&tap->callbacks, 0); atomic_init(&tap->stops, 0);
    tap->permitted = YES;
    return tap;
}
// Destruction's signal precedes the real class releasing its global slot.
// Starting another tap in the same owner turn as stop completion is a stronger
// check, so the active/denied paths wait for that actual completion below.
int main(void) {
    @autoreleasepool {
        assert(!PLANKTapSystemAlertProcess(0, getpid()));
        assert(!PLANKTapSystemAlertProcess(getuid(), -1));
        assert(!PLANKTapSystemAlertProcess(getuid(), 0));
        assert(!PLANKTapSystemAlertProcess(getuid(), getpid()));
        assert(!PLANKTapSystemAlertProcess(getuid(), 1)); // launchd is Apple-signed but not the alert service
        assert(!PLANKTapSystemAlertProcess(getuid() + 1, 1));
        dispatch_queue_t owner = dispatch_queue_create("plank.test.tap-owner", DISPATCH_QUEUE_SERIAL);
        TestTap *pending = makeTap(owner);
        dispatch_sync(owner, ^{
            [pending startWithCompletion:^(BOOL ready) { (void)ready; atomic_fetch_add(&pending->callbacks, 1); }];
        });
        waitFor(pending->entered);
        dispatch_sync(owner, ^{
            [pending stopWithCompletion:^{ atomic_fetch_add(&pending->stops, 1); }];
            assert(atomic_load(&pending->stops) == 1); // no wait for consent
        });
        TestTap *overlap = makeTap(owner);
        dispatch_semaphore_t overlapStopped = dispatch_semaphore_create(0);
        dispatch_sync(owner, ^{
            [overlap startWithCompletion:^(BOOL ready) { assert(!ready); atomic_fetch_add(&overlap->callbacks, 1); }];
            assert(atomic_load(&overlap->callbacks) == 1); // bounded, no second HAL wait
            [overlap stopWithCompletion:^{ dispatch_semaphore_signal(overlapStopped); }];
        });
        waitFor(overlapStopped);
        dispatch_semaphore_signal(pending->releasePrepare);
        waitFor(pending->destroyed);
        // Wait for background cleanup to release the slot using the queued
        // owner notification, not an arbitrary sleep. The serial owner's first
        // callback cannot be used because it may run before destroy completes.
        // A private test barrier is dispatched on the real control queue below.
        dispatch_queue_t control = [pending valueForKey:@"control"];
        dispatch_sync(control, ^{});
        dispatch_sync(owner, ^{});
        assert(!atomic_load(&pending->activations) && !atomic_load(&pending->callbacks));
        assert(atomic_load(&pending->stops) == 1);

        TestTap *active = makeTap(owner); active->holdDestroy = YES;
        dispatch_semaphore_t activeReady = dispatch_semaphore_create(0), activeStopped = dispatch_semaphore_create(0);
        dispatch_sync(owner, ^{
            [active startWithCompletion:^(BOOL ready) { assert(ready); dispatch_semaphore_signal(activeReady); }];
        });
        waitFor(active->entered); dispatch_semaphore_signal(active->releasePrepare); waitFor(activeReady);
        dispatch_sync(owner, ^{
            [active stopWithCompletion:^{ atomic_fetch_add(&active->stops, 1); dispatch_semaphore_signal(activeStopped); }];
        });
        waitFor(active->destroyed);
        assert(atomic_load(&active->activations) == 1 && !atomic_load(&active->stops));
        dispatch_semaphore_signal(active->releaseDestroy); waitFor(activeStopped);

        TestTap *denied = makeTap(owner); denied->permitted = NO;
        dispatch_semaphore_t deniedStopped = dispatch_semaphore_create(0);
        dispatch_sync(owner, ^{
            [denied startWithCompletion:^(BOOL ready) {
                assert(!ready); atomic_fetch_add(&denied->callbacks, 1);
                [denied stopWithCompletion:^{ dispatch_semaphore_signal(deniedStopped); }];
            }];
        });
        waitFor(denied->entered); dispatch_semaphore_signal(denied->releasePrepare); waitFor(deniedStopped);
        waitFor(denied->destroyed);
        dispatch_sync((dispatch_queue_t)[denied valueForKey:@"control"], ^{});
        dispatch_sync(owner, ^{});
        assert(!atomic_load(&denied->activations) && atomic_load(&denied->callbacks) == 1);

        for (unsigned i = 0; i < 100; ++i) {
            TestTap *race = makeTap(owner);
            dispatch_semaphore_t stopped = dispatch_semaphore_create(0);
            dispatch_sync(owner, ^{
                [race startWithCompletion:^(BOOL ready) { assert(ready); atomic_fetch_add(&race->callbacks, 1); }];
            });
            waitFor(race->entered);
            dispatch_semaphore_signal(race->releasePrepare);
            __block int activationsAtStop = -1;
            dispatch_sync(owner, ^{
                [race stopWithCompletion:^{
                    activationsAtStop = atomic_load(&race->activations);
                    atomic_fetch_add(&race->stops, 1); dispatch_semaphore_signal(stopped);
                }];
            });
            waitFor(stopped); waitFor(race->destroyed);
            dispatch_sync((dispatch_queue_t)[race valueForKey:@"control"], ^{});
            dispatch_sync(owner, ^{});
            assert(atomic_load(&race->stops) == 1);
            assert(atomic_load(&race->activations) == activationsAtStop); // never start after stopped
            assert(atomic_load(&race->callbacks) <= 1);
        }
        puts("audio_tap_lifecycle_pass pending_cancel=1 late_consent=1 bounded_reconnect=1 active_drain=1 denied=1 races=100 real_hal=0");
    }
}
