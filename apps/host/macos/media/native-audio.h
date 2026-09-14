// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <CoreMedia/CoreMedia.h>
#import "authentication-session.h"
#include "plank_transport.h"

// Complete, encoder-produced stereo Opus packets, 48 kHz / 240 samples (5 ms).
// The caller owns capture/encoding, priming compensation and the source clock.
// Calls belong on the capture owner's serial queue; no worker or retry queue.
// Stop submissions and release this adapter before destroying its endpoint.
@interface PLANKMacNativeAudio : NSObject
- (instancetype)initWithEndpoint:(PlankTransportNativeEndpoint *)endpoint
                        sessions:(PLANKMacAuthenticationSession *)sessions
                           lease:(PLANKMacStreamLease *)lease
                        validity:(BOOL (^)(void))validity;
// PTS is the decoded packet's first sample on the source timeline, not the
// callback arrival time. Converts to milliseconds, matching the Linux sender.
// Only the encoder may mark the first packet after a source-clock re-anchor.
// Ordinary packets remain strictly contiguous; authorization applies to both.
- (int32_t)sendOpusPacket:(NSData *)packet presentationTime:(CMTime)pts discontinuity:(BOOL)discontinuity;
@end
