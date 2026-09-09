// SPDX-License-Identifier: GPL-3.0-or-later
// Exercise the actual desktop tap and unchanged Opus encoder, without transport
// or installing the Host. No payloads are persisted.
#import <AppKit/AppKit.h>
#import "audio-tap.h"
#import "opus-encoder.h"

int PLANKSessionAudioTapProbe(BOOL cancelImmediately) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        setbuf(stdout, NULL);
        __block BOOL done = NO, stopping = NO, failed = NO, ready = NO;
        __block uint64_t packets = 0, bytes = 0;
        PLANKMacOpusEncoder *encoder = [[PLANKMacOpusEncoder alloc] initWithOutput:^BOOL(NSData *packet, CMTime pts, BOOL discontinuity) {
            (void)pts; (void)discontinuity; packets++; bytes += packet.length; return YES;
        }];
        __block PLANKMacAudioTap *tap;
        void (^stop)(void) = ^{
            if (stopping) return;
            stopping = YES;
            [encoder stop];
            [tap stopWithCompletion:^{ done = YES; }];
        };
        tap = [[PLANKMacAudioTap alloc] initWithQueue:dispatch_get_main_queue() sample:^BOOL(CMSampleBufferRef sample) {
            return !stopping && [encoder encodeSample:sample];
        } failed:^{ failed = YES; stop(); }];
        if (!tap) return 2;
        [tap startWithCompletion:^(BOOL success) {
            ready = success;
            if (cancelImmediately) return;
            if (!success) { failed = YES; stop(); return; }
            printf("session_tap active=1 duration_seconds=10\n");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), stop);
        }];
        if (cancelImmediately) stop();
        CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 30;
        while (!done && CFAbsoluteTimeGetCurrent() < deadline) {
            @autoreleasepool { CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false); }
        }
        printf("session_tap done=%d ready=%d failed=%d cancelled=%d opus_packets=%llu opus_bytes=%llu\n",
            done, ready, failed, cancelImmediately, (unsigned long long)packets, (unsigned long long)bytes);
        BOOL passed = done && !failed && (cancelImmediately ? packets == 0 : ready && packets > 0);
        // Tap retains a callback that retains stop; clear the shared reference
        // after lifecycle drain, rather than retain this probe's owner forever.
        tap = nil;
        return passed ? 0 : 1;
    }
}
