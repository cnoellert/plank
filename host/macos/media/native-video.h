// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <CoreMedia/CoreMedia.h>
#import "authentication-session.h"
#include "plank_transport.h"

// Bounded compressed-data conversion. No pixel mapping, scaling or GPU download.
// Returns nil for malformed samples; outputs are cleared on failure.
NSData *PLANKMacHEVCAnnexB(CMSampleBufferRef sample, int width, int height,
                         BOOL *keyFrame, uint64_t *pts90Khz);

// Call on the capture owner's serial submission queue. This object owns no
// worker/queue and borrows the endpoint: stop submissions before destroying it.
// Its lease must be activated only after that endpoint authenticates the token.
@interface PLANKMacNativeVideo : NSObject
- (instancetype)initWithEndpoint:(PlankTransportNativeEndpoint *)endpoint
                        sessions:(PLANKMacAuthenticationSession *)sessions
                           lease:(PLANKMacStreamLease *)lease
                           width:(int)width height:(int)height
                        validity:(BOOL (^)(void))validity;
@property(nonatomic, readonly) BOOL needsKeyFrame;
// Temporary timing diagnostic: last assigned native frame number, same queue.
@property(nonatomic, readonly) uint64_t lastFrameNumber;
// Called on the same serial queue for a native receiver recovery request.
- (void)requestKeyFrame;
// Latency is capture-to-submit in tenths of a millisecond, matching native ABI.
// A dropped frame requests a new encoder keyframe; no private retry queue.
- (int32_t)sendSample:(CMSampleBufferRef)sample processingLatency:(uint16_t)latency;
@end
