// SPDX-License-Identifier: GPL-3.0-or-later
#import "opus-encoder.h"
#import <AudioToolbox/AudioToolbox.h>
#include <math.h>
#include <mach/mach_time.h>

enum { InputStarved = -7777, Rate = 48000, PacketFrames = 240, MaxChunkFrames = 8192 };
typedef struct { AudioBufferList *list; UInt32 remaining, offset, bytesPerFrame; } Input;
static OSStatus provide(AudioConverterRef converter, UInt32 *frames, AudioBufferList *data,
                        AudioStreamPacketDescription **descriptions, void *context) {
    (void)converter;
    Input *input = context;
    UInt32 count = MIN(*frames, input->remaining);
    *frames = count; data->mNumberBuffers = input->list->mNumberBuffers;
    for (UInt32 b = 0; b < data->mNumberBuffers; ++b) {
        data->mBuffers[b].mNumberChannels = input->list->mBuffers[b].mNumberChannels;
        data->mBuffers[b].mDataByteSize = count * input->bytesPerFrame;
        data->mBuffers[b].mData = count ? (char *)input->list->mBuffers[b].mData + input->offset * input->bytesPerFrame : NULL;
    }
    input->remaining -= count; input->offset += count;
    if (descriptions) *descriptions = NULL;
    // Temporary input exhaustion is not EOF. The zero-frame callback also
    // ends AudioConverter's documented borrowed-input lifetime for this chunk.
    return count ? noErr : InputStarved;
}

@implementation PLANKMacOpusEncoder {
    AudioConverterRef _converter;
    AudioStreamBasicDescription _format;
    BOOL (^_output)(NSData *, CMTime);
    BOOL _stopped;
    CMTime _origin, _packetPTS;
    uint64_t _inputFrames;
    uint32_t _primingFrames, _maximumPacketBytes;
    double _sourceToleranceSeconds;
}
- (instancetype)init { return nil; }
- (instancetype)initWithOutput:(BOOL (^)(NSData *, CMTime))output {
    if (!output) return nil;
    self = [super init];
    if (self) {
        mach_timebase_info_data_t clock = {0};
        if (mach_timebase_info(&clock) != KERN_SUCCESS || !clock.numer || !clock.denom) return nil;
        // SCK's source clock is quantized to hardware ticks, even when PTS is
        // expressed in nanoseconds. Bound rounding at both endpoints plus CMTime
        // representation; never permit as much as half an audio sample.
        _sourceToleranceSeconds = 2 * ((double)clock.numer / clock.denom + 1) * 1e-9;
        if (_sourceToleranceSeconds >= 0.5 / Rate) return nil;
        _output = [output copy];
    }
    return self;
}
- (uint32_t)primingFrames { return _primingFrames; }
- (void)stop {
    _stopped = YES;
    if (_converter) { AudioConverterDispose(_converter); _converter = NULL; }
    _output = nil;
}
- (void)dealloc { if (_converter) AudioConverterDispose(_converter); }
- (BOOL)prepare:(const AudioStreamBasicDescription *)format pts:(CMTime)pts {
    _format = *format;
    AudioStreamBasicDescription destination = {0};
    destination.mFormatID = kAudioFormatOpus;
    destination.mSampleRate = Rate; destination.mChannelsPerFrame = 2;
    destination.mFramesPerPacket = PacketFrames;
    if (AudioConverterNew(format, &destination, &_converter)) return NO;
    UInt32 bitrate = 96000; // Initial qualified stereo policy; not a CBR claim.
    if (AudioConverterSetProperty(_converter, kAudioConverterEncodeBitRate, sizeof(bitrate), &bitrate)) return NO;
    AudioConverterPrimeInfo prime = {0}; UInt32 size = sizeof(prime);
    if (AudioConverterGetProperty(_converter, kAudioConverterPrimeInfo, &size, &prime) ||
        prime.leadingFrames > Rate) return NO;
    _primingFrames = prime.leadingFrames;
    size = sizeof(_maximumPacketBytes);
    if (AudioConverterGetProperty(_converter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &_maximumPacketBytes) ||
        !_maximumPacketBytes || _maximumPacketBytes > 65536) return NO;
    _origin = pts;
    _packetPTS = CMTimeSubtract(pts, CMTimeMake(_primingFrames, Rate));
    return CMTIME_IS_NUMERIC(_packetPTS) && _packetPTS.value >= 0;
}
- (BOOL)encodeSample:(CMSampleBufferRef)sample {
    if (_stopped) return NO;
    if (![self consume:sample]) { [self stop]; return NO; }
    return YES;
}
- (BOOL)consume:(CMSampleBufferRef)sample {
    if (!sample || !CMSampleBufferIsValid(sample) || !CMSampleBufferDataIsReady(sample)) return NO;
    CMFormatDescriptionRef description = CMSampleBufferGetFormatDescription(sample);
    if (!description || CMFormatDescriptionGetMediaType(description) != kCMMediaType_Audio) return NO;
    const AudioStreamBasicDescription *format = CMAudioFormatDescriptionGetStreamBasicDescription(description);
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sample);
    CMItemCount frames = CMSampleBufferGetNumSamples(sample);
    if (!format || !CMTIME_IS_NUMERIC(pts) || pts.epoch != 0 || pts.value < 0 ||
        format->mFormatID != kAudioFormatLinearPCM || format->mSampleRate != Rate ||
        format->mChannelsPerFrame != 2 || format->mBitsPerChannel != 32 ||
        !(format->mFormatFlags & kAudioFormatFlagIsFloat) ||
        (format->mFormatFlags & kAudioFormatFlagIsBigEndian) ||
        format->mFramesPerPacket != 1 || frames <= 0 || frames > MaxChunkFrames) return NO;
    BOOL planar = (format->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    if (format->mBytesPerFrame != (planar ? 4u : 8u) || format->mBytesPerPacket != format->mBytesPerFrame) return NO;
    if (_converter) {
        if (format->mFormatFlags != _format.mFormatFlags || format->mBytesPerFrame != _format.mBytesPerFrame ||
            _inputFrames > INT64_MAX - MaxChunkFrames) return NO;
        CMTime expected = CMTimeAdd(_origin, CMTimeMake((int64_t)_inputFrames, Rate));
        // Allow only source-clock representation rounding, never a missing
        // sample. Derive from the origin, not rounded increments.
        double gap = fabs(CMTimeGetSeconds(CMTimeSubtract(pts, expected)));
        if (!isfinite(gap) || gap > _sourceToleranceSeconds) {
            fprintf(stderr, "macos_opus_failure stage=timestamp gap_ns=%.3f\n", gap * 1e9);
            return NO;
        }
    } else if (![self prepare:format pts:pts]) return NO;
    struct { UInt32 count; AudioBuffer buffers[2]; } storage = {0};
    AudioBufferList *list = (AudioBufferList *)&storage;
    CMBlockBufferRef block = NULL;
    // Pass the exact list size for the requested format. On SDK 27 the
    // two-buffer capacity passed for interleaved PCM returns ArrayTooSmall,
    // despite the separately queried requirement being only one buffer.
    OSStatus status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, NULL,
        list, planar ? sizeof(storage) : sizeof(AudioBufferList), kCFAllocatorDefault, kCFAllocatorDefault,
        kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, &block);
    BOOL valid = !status && list->mNumberBuffers == (planar ? 2u : 1u);
    for (UInt32 b = 0; valid && b < list->mNumberBuffers; ++b) {
        AudioBuffer *buffer = &list->mBuffers[b];
        valid = buffer->mData && buffer->mNumberChannels == (planar ? 1u : 2u) &&
            buffer->mDataByteSize == frames * format->mBytesPerFrame;
        for (size_t i = 0; valid && i < buffer->mDataByteSize / sizeof(float); ++i) {
            float value; memcpy(&value, (char *)buffer->mData + i * sizeof(float), sizeof(value));
            valid = isfinite(value);
        }
    }
    if (valid) valid = [self encodeBuffers:list frames:(UInt32)frames];
    if (!valid) [self stop]; // dispose before releasing any borrowed input
    if (block) CFRelease(block);
    if (valid) _inputFrames += frames;
    return valid;
}
- (BOOL)encodeBuffers:(AudioBufferList *)list frames:(UInt32)frames {
    Input input = {list, frames, 0, _format.mBytesPerFrame};
    // Max 8192 input frames plus one partial codec packet. No unbounded drain.
    for (unsigned step = 0; step < 40; ++step) {
        uint8_t bytes[65536];
        AudioBufferList output = {0}; output.mNumberBuffers = 1;
        output.mBuffers[0] = (AudioBuffer){2, _maximumPacketBytes, bytes};
        AudioStreamPacketDescription description = {0}; UInt32 packets = 1;
        OSStatus status = AudioConverterFillComplexBuffer(_converter, provide, &input, &packets, &output, &description);
        if (status != noErr && status != InputStarved) return NO;
        if (packets) {
            if (packets != 1 || description.mStartOffset != 0 || !description.mDataByteSize ||
                description.mDataByteSize > _maximumPacketBytes ||
                (description.mVariableFramesInPacket && description.mVariableFramesInPacket != PacketFrames)) return NO;
            NSData *packet = [NSData dataWithBytes:bytes length:description.mDataByteSize];
            if (!_output(packet, _packetPTS) || _stopped) return NO;
            _packetPTS = CMTimeAdd(_packetPTS, CMTimeMake(PacketFrames, Rate));
            if (!CMTIME_IS_NUMERIC(_packetPTS)) return NO;
        }
        if (status == InputStarved) return input.remaining == 0;
    }
    return NO;
}
@end
