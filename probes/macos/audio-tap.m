// SPDX-License-Identifier: GPL-3.0-or-later
// Bounded Core Audio feasibility probe. No microphone, stored audio, network,
// default-device changes or production Host code. Run only on the dedicated Mac.
#import <AppKit/AppKit.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#import "opus-encoder.h"
#include <mach/mach_time.h>
#include <math.h>
#include <stdatomic.h>
#include <signal.h>
#include <unistd.h>

static volatile sig_atomic_t stopRequested;
static void requestStop(int signalNumber) { (void)signalNumber; stopRequested = 1; }

enum { TapSlots = 16, TapMaxFrames = 8192 };
typedef struct {
    UInt32 frames;
    uint64_t hostTime;
    float samples[TapMaxFrames * 2];
} TapBlock;

typedef struct {
    AudioStreamBasicDescription format;
    uint64_t callbacks, frames, invalid;
    UInt32 minFrames, maxFrames;
    double maxRMS, maxSampleGap, maxHostGapUs, maxAgeMs;
    double previousSample;
    uint64_t previousHost;
    UInt32 previousFrames;
    double tickSeconds;
    _Atomic uint32_t writeIndex, readIndex, overflow;
    TapBlock blocks[TapSlots];
    __unsafe_unretained dispatch_source_t ready;
} TapMeasurements;

// Single HAL callback writer; main reads only after IO has stopped/destroyed.
// No allocation, Objective-C messages, locks, logging or encoding in callback.
static OSStatus capture(AudioObjectID device, const AudioTimeStamp* now,
                        const AudioBufferList* input, const AudioTimeStamp* inputTime,
                        AudioBufferList* output, const AudioTimeStamp* outputTime, void* context) {
    (void)device; (void)now; (void)output; (void)outputTime;
    TapMeasurements* state = context;
    const BOOL planar = state->format.mFormatFlags & kAudioFormatFlagIsNonInterleaved;
    const UInt32 bytes = planar ? sizeof(float) : 2 * sizeof(float);
    if (!input || input->mNumberBuffers != (planar ? 2u : 1u) ||
        !inputTime || (inputTime->mFlags & (kAudioTimeStampSampleTimeValid | kAudioTimeStampHostTimeValid)) !=
                      (kAudioTimeStampSampleTimeValid | kAudioTimeStampHostTimeValid)) {
        state->invalid++; return noErr;
    }
    UInt32 frames = input->mBuffers[0].mDataByteSize / bytes;
    if (!frames || frames > 8192) { state->invalid++; return noErr; }
    double energy = 0;
    for (UInt32 b = 0; b < input->mNumberBuffers; b++) {
        const AudioBuffer* buffer = &input->mBuffers[b];
        if (!buffer->mData || buffer->mNumberChannels != (planar ? 1u : 2u) ||
            buffer->mDataByteSize != frames * bytes) { state->invalid++; return noErr; }
        const float* samples = buffer->mData;
        for (UInt32 i = 0; i < frames * (planar ? 1u : 2u); i++) {
            if (!isfinite(samples[i])) { state->invalid++; return noErr; }
            energy += (double)samples[i] * samples[i];
        }
    }
    if (state->callbacks) {
        state->maxSampleGap = fmax(state->maxSampleGap,
            fabs(inputTime->mSampleTime - state->previousSample - state->previousFrames));
        double hostDelta = ((double)inputTime->mHostTime - (double)state->previousHost) * state->tickSeconds;
        state->maxHostGapUs = fmax(state->maxHostGapUs,
            fabs(hostDelta - state->previousFrames / state->format.mSampleRate) * 1e6);
    }
    state->maxAgeMs = fmax(state->maxAgeMs,
        ((double)mach_absolute_time() - (double)inputTime->mHostTime) * state->tickSeconds * 1000);
    state->previousSample = inputTime->mSampleTime;
    state->previousHost = inputTime->mHostTime;
    state->previousFrames = frames;
    if (!state->callbacks || frames < state->minFrames) state->minFrames = frames;
    if (frames > state->maxFrames) state->maxFrames = frames;
    state->maxRMS = fmax(state->maxRMS, sqrt(energy / (2 * frames)));
    state->callbacks++; state->frames += frames;
    uint32_t writeIndex = atomic_load_explicit(&state->writeIndex, memory_order_relaxed);
    uint32_t readIndex = atomic_load_explicit(&state->readIndex, memory_order_acquire);
    if (writeIndex - readIndex == TapSlots) {
        atomic_fetch_add_explicit(&state->overflow, 1, memory_order_relaxed);
    } else {
        TapBlock* block = &state->blocks[writeIndex % TapSlots];
        block->frames = frames; block->hostTime = inputTime->mHostTime;
        if (planar) {
            const float* left = input->mBuffers[0].mData;
            const float* right = input->mBuffers[1].mData;
            for (UInt32 i = 0; i < frames; i++) {
                block->samples[i * 2] = left[i]; block->samples[i * 2 + 1] = right[i];
            }
        } else memcpy(block->samples, input->mBuffers[0].mData, frames * 2 * sizeof(float));
        atomic_store_explicit(&state->writeIndex, writeIndex + 1, memory_order_release);
        dispatch_source_merge_data(state->ready, 1);
    }
    return noErr;
}

extern int PLANKSessionAudioTapProbe(BOOL cancelImmediately);
int main(int argc, const char* argv[]) {
    @autoreleasepool {
        if (argc == 2 && (!strcmp(argv[1], "--session-tap") || !strcmp(argv[1], "--session-tap-cancel")))
            return PLANKSessionAudioTapProbe(!strcmp(argv[1], "--session-tap-cancel"));
        BOOL hold = argc == 2 && strcmp(argv[1], "--hold") == 0;
        if (argc != 1 && !hold) { fprintf(stderr, "Usage: audio-tap [--hold]\n"); return 2; }
        if (geteuid() == 0) { fprintf(stderr, "Run as the logged-in desktop user, not root.\n"); return 2; }
        struct sigaction action = {0};
        action.sa_handler = requestStop;
        sigemptyset(&action.sa_mask);
        if (sigaction(SIGTERM, &action, NULL) || sigaction(SIGINT, &action, NULL)) return 2;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        setbuf(stdout, NULL);
        AudioObjectID tap = kAudioObjectUnknown, aggregate = kAudioObjectUnknown;
        AudioDeviceIOProcID proc = NULL;
        BOOL started = NO;
        int result = 1;
        // Bounded RAM handoff to the ordinary main queue, never HAL encoding.
        // No PCM or Opus payload is persisted. The ring is single producer/consumer.
        static TapMeasurements measurements;
        TapMeasurements* state = &measurements;
        atomic_init(&measurements.writeIndex, 0);
        atomic_init(&measurements.readIndex, 0);
        atomic_init(&measurements.overflow, 0);
        __block uint64_t opusPackets = 0, opusBytes = 0, encodeFailures = 0;
        __block CMTime lastOpusPTS = kCMTimeInvalid;
        PLANKMacOpusEncoder* encoder = [[PLANKMacOpusEncoder alloc] initWithOutput:^BOOL(NSData* packet, CMTime pts, BOOL discontinuity) {
            if (!discontinuity && CMTIME_IS_VALID(lastOpusPTS) && CMTimeCompare(pts, lastOpusPTS) <= 0) return NO;
            lastOpusPTS = pts; opusPackets++; opusBytes += packet.length;
            return YES;
        }];
        dispatch_source_t ready = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0, dispatch_get_main_queue());
        measurements.ready = ready;
        void (^drain)(void) = ^{
            uint32_t readIndex = atomic_load_explicit(&state->readIndex, memory_order_relaxed);
            uint32_t writeIndex = atomic_load_explicit(&state->writeIndex, memory_order_acquire);
            while (readIndex != writeIndex) {
                TapBlock* block = &state->blocks[readIndex % TapSlots];
                AudioStreamBasicDescription format = state->format;
                format.mFormatFlags &= ~kAudioFormatFlagIsNonInterleaved;
                format.mBytesPerFrame = format.mBytesPerPacket = 8;
                CMAudioFormatDescriptionRef description = NULL;
                CMBlockBufferRef data = NULL;
                CMSampleBufferRef sample = NULL;
                size_t bytes = block->frames * 2 * sizeof(float);
                OSStatus status = CMAudioFormatDescriptionCreate(NULL, &format, 0, NULL, 0, NULL, NULL, &description);
                if (!status) status = CMBlockBufferCreateWithMemoryBlock(NULL, NULL, bytes, NULL, NULL, 0, bytes, 0, &data);
                if (!status) status = CMBlockBufferReplaceDataBytes(block->samples, data, 0, bytes);
                CMTime pts = CMClockMakeHostTimeFromSystemUnits(block->hostTime);
                if (!status) status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(NULL, data, description,
                    block->frames, pts, NULL, &sample);
                if (status || ![encoder encodeSample:sample]) encodeFailures++;
                if (sample) CFRelease(sample);
                if (data) CFRelease(data);
                if (description) CFRelease(description);
                atomic_store_explicit(&state->readIndex, ++readIndex, memory_order_release);
            }
        };
        dispatch_source_set_event_handler(ready, drain);
        dispatch_resume(ready);
        mach_timebase_info_data_t clock;
        mach_timebase_info(&clock);
        measurements.tickSeconds = (double)clock.numer / clock.denom / 1e9;
        // The feasibility probe captures the global stereo mix; the production
        // session ownership/process-exclusion policy is a separate release gate.
        CATapDescription* description = [[CATapDescription alloc] initStereoGlobalTapButExcludeProcesses:@[]];
        description.name = @"PLANK Audio Tap Qualification";
        description.privateTap = YES;
        description.muteBehavior = CATapMutedWhenTapped;
        printf("tap_probe stage=create mute=when-tapped duration=%s stored_audio=0\n", hold ? "until-stopped" : "10-seconds");
        OSStatus status = AudioHardwareCreateProcessTap(description, &tap);
        if (status) { printf("tap_create_status=%d\n", (int)status); goto cleanup; }
        AudioObjectPropertyAddress property = {kAudioTapPropertyFormat, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        UInt32 size = sizeof(measurements.format);
        status = AudioObjectGetPropertyData(tap, &property, 0, NULL, &size, &measurements.format);
        if (status) { printf("tap_format_status=%d\n", (int)status); goto cleanup; }
        printf("tap_format rate=%.0f channels=%u bits=%u flags=%u bytes_per_frame=%u\n",
            measurements.format.mSampleRate, measurements.format.mChannelsPerFrame,
            measurements.format.mBitsPerChannel, measurements.format.mFormatFlags,
            measurements.format.mBytesPerFrame);
        if (measurements.format.mFormatID != kAudioFormatLinearPCM ||
            measurements.format.mChannelsPerFrame != 2 || measurements.format.mBitsPerChannel != 32 ||
            !(measurements.format.mFormatFlags & kAudioFormatFlagIsFloat) ||
            (measurements.format.mFormatFlags & kAudioFormatFlagIsBigEndian) ||
            measurements.format.mBytesPerFrame !=
                ((measurements.format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? 4u : 8u) ||
            !isfinite(measurements.format.mSampleRate) || measurements.format.mSampleRate <= 0) goto cleanup;
        {
            NSDictionary* specification = @{
                @kAudioAggregateDeviceNameKey: @"PLANK Private Audio Qualification",
                @kAudioAggregateDeviceUIDKey: NSUUID.UUID.UUIDString,
                @kAudioAggregateDeviceIsPrivateKey: @YES,
                @kAudioAggregateDeviceTapAutoStartKey: @NO,
                @kAudioAggregateDeviceTapListKey: @[@{
                    @kAudioSubTapUIDKey: description.UUID.UUIDString,
                    @kAudioSubTapDriftCompensationKey: @YES}]
            };
            status = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)specification, &aggregate);
        }
        if (status) { printf("aggregate_create_status=%d\n", (int)status); goto cleanup; }
        status = AudioDeviceCreateIOProcID(aggregate, capture, &measurements, &proc);
        if (status) { printf("io_create_status=%d\n", (int)status); goto cleanup; }
        printf("tap_probe stage=start permission_may_be_requested=1\n");
        status = AudioDeviceStart(aggregate, proc);
        if (status) { printf("io_start_status=%d\n", (int)status); goto cleanup; }
        started = YES;
        printf("tap_probe stage=active pid=%d stop_with=SIGTERM\n", getpid());
        {
            CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 10;
            while (!stopRequested && (hold || CFAbsoluteTimeGetCurrent() < deadline)) {
                @autoreleasepool { CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false); }
            }
        }
        result = 0;
cleanup:
        if (started) {
            status = AudioDeviceStop(aggregate, proc);
            printf("io_stop_status=%d\n", (int)status);
            if (status) result = 1;
        }
        if (proc) {
            status = AudioDeviceDestroyIOProcID(aggregate, proc);
            printf("io_destroy_status=%d\n", (int)status);
            if (status) result = 1;
        }
        if (aggregate != kAudioObjectUnknown) {
            status = AudioHardwareDestroyAggregateDevice(aggregate);
            printf("aggregate_destroy_status=%d\n", (int)status);
            if (status) result = 1;
        }
        if (tap != kAudioObjectUnknown) {
            status = AudioHardwareDestroyProcessTap(tap);
            printf("tap_destroy_status=%d\n", (int)status);
            if (status) result = 1;
        }
        drain();
        dispatch_source_cancel(ready);
        [encoder stop];
        uint32_t overflows = atomic_load_explicit(&measurements.overflow, memory_order_relaxed);
        if (overflows || encodeFailures || !opusPackets) result = 1;
        if (!measurements.callbacks || measurements.invalid) result = 1;
        printf("tap_opus packets=%llu bytes=%llu failures=%llu ring_overflows=%u persisted_payloads=0\n",
            (unsigned long long)opusPackets, (unsigned long long)opusBytes,
            (unsigned long long)encodeFailures, overflows);
        printf("tap_probe callbacks=%llu frames=%llu invalid=%llu chunk_min=%u chunk_max=%u max_rms=%.6f sample_gap_frames=%.3f host_gap_us=%.3f max_age_ms=%.3f result=%d\n",
            (unsigned long long)measurements.callbacks, (unsigned long long)measurements.frames,
            (unsigned long long)measurements.invalid, measurements.minFrames, measurements.maxFrames,
            measurements.maxRMS, measurements.maxSampleGap, measurements.maxHostGapUs, measurements.maxAgeMs, result);
        return result;
    }
}
