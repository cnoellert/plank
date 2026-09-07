// SPDX-License-Identifier: GPL-3.0-or-later
// Dedicated-Mac system-audio qualification. No microphone or persisted samples.
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#include <math.h>
#include <unistd.h>

enum { InputStarved = -7777 };
typedef struct { AudioBufferList* list; UInt32 remaining, offset, bytesPerFrame; } AudioInput;
static OSStatus provideAudio(AudioConverterRef converter, UInt32* frames, AudioBufferList* data,
                             AudioStreamPacketDescription** descriptions, void* context) {
    (void)converter;
    AudioInput* input = context;
    UInt32 count = *frames < input->remaining ? *frames : input->remaining;
    *frames = count;
    data->mNumberBuffers = input->list->mNumberBuffers;
    for (UInt32 b = 0; b < data->mNumberBuffers; ++b) {
        data->mBuffers[b].mNumberChannels = input->list->mBuffers[b].mNumberChannels;
        data->mBuffers[b].mDataByteSize = count * input->bytesPerFrame;
        data->mBuffers[b].mData = count ? (char*)input->list->mBuffers[b].mData + input->offset * input->bytesPerFrame : NULL;
    }
    input->remaining -= count; input->offset += count;
    if (descriptions) *descriptions = NULL;
    return count ? noErr : InputStarved;
}
static int compareAge(const void* a, const void* b) {
    double left = *(const double*)a, right = *(const double*)b;
    return (left > right) - (left < right);
}

@interface PLANKAudioCaptureProbe : NSObject <SCStreamOutput, SCStreamDelegate>
@property SCStream* stream;
@property AVAudioEngine* engine;
@property AVAudioPlayerNode* player;
@property BOOL stopping;
@property int result;
@property unsigned audioBuffers, videoFrames, minFrames, maxFrames;
@property uint64_t audioFrames;
@property CMTime expectedAudioPTS;
@property double maxGapUs, maxRms, maxAudioAgeMs, maxVideoAgeMs;
- (void)begin;
- (void)finish:(int)result;
@end

@implementation PLANKAudioCaptureProbe
{
    AudioConverterRef _converter;
    AudioStreamBasicDescription _inputFormat;
    unsigned _encodedPackets, _encodedBytes;
    double _audioAges[1024], _encodeDurations[1024];
    unsigned _ageCount, _encodeCount;
}
- (void)finish:(int)result {
    if (_stopping) return;
    _stopping = YES; _result = result;
    [_player stop]; [_engine stop];
    if (_converter) { AudioConverterDispose(_converter); _converter = NULL; }
    printf("system_audio buffers=%u frames=%llu chunk_min=%u chunk_max=%u max_abs_pts_gap_us=%.3f max_rms=%.6f max_audio_age_ms=%.3f video_frames=%u max_video_age_ms=%.3f result=%d\n",
           _audioBuffers, (unsigned long long)_audioFrames, _minFrames, _maxFrames,
           _maxGapUs, _maxRms, _maxAudioAgeMs, _videoFrames, _maxVideoAgeMs, result);
    if (_ageCount > 50 && _encodeCount) {
        // Exclude the first second's 50 x 20-ms capture chunks from age stats.
        unsigned count = _ageCount - 50;
        qsort(_audioAges + 50, count, sizeof(double), compareAge);
        qsort(_encodeDurations, _encodeCount, sizeof(double), compareAge);
        printf("audio_steady_age_ms min=%.3f median=%.3f p95=%.3f max=%.3f encode_chunk_ms_p95=%.3f encode_chunk_ms_max=%.3f opus_packets=%u opus_bytes=%u\n",
               _audioAges[50], _audioAges[50 + count / 2], _audioAges[50 + count * 95 / 100], _audioAges[_ageCount - 1],
               _encodeDurations[_encodeCount * 95 / 100], _encodeDurations[_encodeCount - 1], _encodedPackets, _encodedBytes);
    }
    fflush(stdout);
    if (!_stream) { CFRunLoopStop(CFRunLoopGetMain()); return; }
    [_stream stopCaptureWithCompletionHandler:^(NSError* error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) self.result = 4;
            CFRunLoopStop(CFRunLoopGetMain());
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        self.result = 4; CFRunLoopStop(CFRunLoopGetMain());
    });
}
- (void)stream:(SCStream*)stream didStopWithError:(NSError*)error {
    (void)stream;
    fprintf(stderr, "capture_error domain=%s code=%ld\n", error.domain.UTF8String, (long)error.code);
    dispatch_async(dispatch_get_main_queue(), ^{ [self finish:3]; });
}
- (void)stream:(SCStream*)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    (void)stream;
    if (_stopping || !CMSampleBufferDataIsReady(sample)) return;
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sample);
    if (!CMTIME_IS_NUMERIC(pts) || pts.epoch != 0) { [self finish:3]; return; }
    double age = CMTimeGetSeconds(CMTimeSubtract(CMClockGetTime(CMClockGetHostTimeClock()), pts)) * 1000;
    if (!isfinite(age)) { [self finish:3]; return; }
    if (type == SCStreamOutputTypeScreen) {
        _videoFrames++; _maxVideoAgeMs = fmax(_maxVideoAgeMs, age); return;
    }
    if (type != SCStreamOutputTypeAudio) { [self finish:3]; return; }
    _maxAudioAgeMs = fmax(_maxAudioAgeMs, age);
    if (_ageCount < 1024) _audioAges[_ageCount++] = age;
    CMAudioFormatDescriptionRef description = CMSampleBufferGetFormatDescription(sample);
    const AudioStreamBasicDescription* format = CMAudioFormatDescriptionGetStreamBasicDescription(description);
    CMItemCount frames = CMSampleBufferGetNumSamples(sample);
    if (!format || format->mFormatID != kAudioFormatLinearPCM || format->mSampleRate != 48000 ||
        format->mChannelsPerFrame != 2 || format->mBitsPerChannel != 32 ||
        !(format->mFormatFlags & kAudioFormatFlagIsFloat) ||
        (format->mFormatFlags & kAudioFormatFlagIsBigEndian) || frames <= 0 || frames > 8192) {
        [self finish:3]; return;
    }
    BOOL planar = (format->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    if (format->mBytesPerFrame != (planar ? 4 : 8)) { [self finish:3]; return; }
    struct { UInt32 count; AudioBuffer buffers[2]; } storage = {0};
    AudioBufferList* list = (AudioBufferList*)&storage;
    CMBlockBufferRef block = NULL;
    OSStatus status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, NULL,
        list, sizeof(storage), kCFAllocatorDefault, kCFAllocatorDefault,
        kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, &block);
    if (status || list->mNumberBuffers != (planar ? 2u : 1u)) {
        if (block) CFRelease(block); [self finish:3]; return;
    }
    double energy = 0;
    BOOL valid = YES;
    for (UInt32 b = 0; b < list->mNumberBuffers; ++b) {
        const AudioBuffer* buffer = &list->mBuffers[b];
        if (!buffer->mData || buffer->mNumberChannels != (planar ? 1u : 2u) ||
            buffer->mDataByteSize != frames * (planar ? 4u : 8u)) { valid = NO; break; }
        const float* values = buffer->mData;
        for (size_t i = 0; i < buffer->mDataByteSize / sizeof(float); ++i) {
            if (!isfinite(values[i])) { valid = NO; break; }
            energy += (double)values[i] * values[i];
        }
    }
    if (valid) valid = [self encodeAudio:list format:format frames:(UInt32)frames];
    if (block) CFRelease(block);
    if (!valid) { [self finish:3]; return; }
    if (!_audioBuffers) {
        printf("system_audio_format rate=%.0f channels=%u bits=%u planar=%d bytes_per_frame=%u pts_timescale=%d\n",
               format->mSampleRate, (unsigned)format->mChannelsPerFrame,
               (unsigned)format->mBitsPerChannel, planar, (unsigned)format->mBytesPerFrame, pts.timescale);
        _minFrames = (unsigned)frames;
    } else {
        double gap = fabs(CMTimeGetSeconds(CMTimeSubtract(pts, _expectedAudioPTS)) * 1000000);
        _maxGapUs = fmax(_maxGapUs, gap);
    }
    _expectedAudioPTS = CMTimeAdd(pts, CMTimeMake(frames, 48000));
    _audioBuffers++; _audioFrames += frames;
    if ((unsigned)frames < _minFrames) _minFrames = (unsigned)frames;
    if ((unsigned)frames > _maxFrames) _maxFrames = (unsigned)frames;
    _maxRms = fmax(_maxRms, sqrt(energy / (frames * 2)));
}
- (BOOL)encodeAudio:(AudioBufferList*)list format:(const AudioStreamBasicDescription*)format frames:(UInt32)frames {
    if (!_converter) {
        _inputFormat = *format;
        AudioStreamBasicDescription destination = {0};
        destination.mFormatID = kAudioFormatOpus;
        destination.mSampleRate = 48000; destination.mChannelsPerFrame = 2; destination.mFramesPerPacket = 240;
        if (AudioConverterNew(format, &destination, &_converter)) return NO;
        UInt32 bitrate = 96000;
        if (AudioConverterSetProperty(_converter, kAudioConverterEncodeBitRate, sizeof(bitrate), &bitrate)) return NO;
        AudioConverterPrimeInfo prime = {0}; UInt32 size = sizeof(prime);
        if (AudioConverterGetProperty(_converter, kAudioConverterPrimeInfo, &size, &prime)) return NO;
        printf("live_opus leading_frames=%u packet_frames=240 bitrate=96000\n", (unsigned)prime.leadingFrames);
    }
    if (format->mFormatFlags != _inputFormat.mFormatFlags || format->mBytesPerFrame != _inputFormat.mBytesPerFrame) return NO;
    AudioInput input = {list, frames, 0, format->mBytesPerFrame};
    double start = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()));
    // Borrow SCK buffers only until the final zero-packet callback. That
    // callback ends the converter's documented borrowed-input lifetime.
    for (unsigned step = 0; step < 40; ++step) {
        unsigned char packet[65536];
        AudioBufferList output = {0};
        output.mNumberBuffers = 1;
        output.mBuffers[0] = (AudioBuffer){2, sizeof(packet), packet};
        AudioStreamPacketDescription description = {0}; UInt32 packets = 1;
        OSStatus status = AudioConverterFillComplexBuffer(_converter, provideAudio, &input, &packets, &output, &description);
        if (status != noErr && status != InputStarved) return NO;
        if (packets) {
            if (packets != 1 || description.mStartOffset != 0 || !description.mDataByteSize ||
                description.mDataByteSize > sizeof(packet) ||
                (description.mVariableFramesInPacket && description.mVariableFramesInPacket != 240)) return NO;
            _encodedPackets++; _encodedBytes += description.mDataByteSize;
            // Intentionally discard compressed samples: no recording or network.
        }
        if (status == InputStarved) {
            if (input.remaining) return NO;
            if (_encodeCount < 1024) _encodeDurations[_encodeCount++] =
                (CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())) - start) * 1000;
            return YES;
        }
    }
    return NO;
}
- (void)playTone {
    AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:2];
    AVAudioPCMBuffer* tone = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:96000];
    tone.frameLength = 96000;
    for (unsigned frame = 0; frame < tone.frameLength; ++frame) {
        tone.floatChannelData[0][frame] = 0.025f * sinf(2 * M_PI * 440 * frame / 48000);
        tone.floatChannelData[1][frame] = 0.025f * sinf(2 * M_PI * 880 * frame / 48000);
    }
    _engine = [AVAudioEngine new]; _player = [AVAudioPlayerNode new];
    [_engine attachNode:_player];
    NSError* error = nil;
    if (![_engine connect:_player to:_engine.mainMixerNode format:format error:&error]) { [self finish:3]; return; }
    [_player scheduleBuffer:tone completionHandler:nil];
    if (![_engine startAndReturnError:&error]) { [self finish:3]; return; }
    if (![_player playAndReturnError:&error]) [self finish:3];
}
- (void)begin {
    if (!CGPreflightScreenCaptureAccess()) { fprintf(stderr, "screen_capture_permission=not-allowed\n"); [self finish:2]; return; }
    [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:YES completionHandler:^(SCShareableContent* content, NSError* error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.stopping) return;
            SCDisplay* selected = nil;
            for (SCDisplay* display in content.displays) if (display.displayID == CGMainDisplayID()) selected = display;
            if (error || !selected) { [self finish:3]; return; }
            SCContentFilter* filter = [[SCContentFilter alloc] initWithDisplay:selected excludingWindows:@[]];
            SCStreamConfiguration* configuration = [SCStreamConfiguration new];
            configuration.width = 64; configuration.height = 64; // Metadata-only video timing; not an image-quality test.
            configuration.minimumFrameInterval = CMTimeMake(1, 10);
            configuration.queueDepth = 3;
            configuration.capturesAudio = YES;
            configuration.captureMicrophone = NO;
            configuration.sampleRate = 48000; configuration.channelCount = 2;
            configuration.excludesCurrentProcessAudio = NO; // Include this probe's tone alongside system audio.
            self.stream = [[SCStream alloc] initWithFilter:filter configuration:configuration delegate:self];
            NSError* outputError = nil;
            if (![self.stream addStreamOutput:self type:SCStreamOutputTypeAudio sampleHandlerQueue:dispatch_get_main_queue() error:&outputError] ||
                ![self.stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:dispatch_get_main_queue() error:&outputError]) {
                [self finish:3]; return;
            }
            [self.stream startCaptureWithCompletionHandler:^(NSError* startError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.stopping) return;
                    if (startError) { [self finish:3]; return; }
                    [self playTone];
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        [self finish:(self.audioBuffers > 20 && self.videoFrames > 0 && self.maxRms > 0.0001) ? 0 : 3];
                    });
                });
            }];
        });
    }];
}
@end

int main(int argc, const char** argv) {
    if (argc != 2 || strcmp(argv[1], "--audio")) return 2;
    alarm(20);
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        PLANKAudioCaptureProbe* probe = [PLANKAudioCaptureProbe new];
        probe.result = 4;
        dispatch_async(dispatch_get_main_queue(), ^{ [probe begin]; });
        CFRunLoopRun();
        return probe.result;
    }
}
