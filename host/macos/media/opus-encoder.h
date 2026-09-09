// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>

// Synchronous, single-owner-queue AudioToolbox encoder. Accepts native-endian
// 48-kHz stereo Float32 CMSampleBuffers, planar or interleaved. No resampling,
// microphone, private queue or worker. Output is 240-frame (5-ms) stereo Opus.
@interface PLANKMacOpusEncoder : NSObject
// discontinuity marks the first output after a source-clock re-anchor. PCM and
// codec state remain continuous; no synthetic silence or catch-up queue is added.
- (instancetype)initWithOutput:(BOOL (^)(NSData *packet, CMTime presentationTime, BOOL discontinuity))output;
- (BOOL)encodeSample:(CMSampleBufferRef)sample;
@property(nonatomic, readonly) uint32_t primingFrames;
// One-shot session lifetime: drop pending samples, never flush old audio on
// disconnect. Malformed source or output failure stops it; valid timestamp
// gaps/overlaps re-anchor source time without disabling the session's audio.
- (void)stop;
@end
