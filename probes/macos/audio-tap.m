// SPDX-License-Identifier: GPL-3.0-or-later
// Bounded Core Audio feasibility probe. No microphone, stored audio, network,
// default-device changes or production Host code. Run only on the dedicated Mac.
#import <AppKit/AppKit.h>
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#include <mach/mach_time.h>
#include <math.h>
#include <unistd.h>

typedef struct {
    AudioStreamBasicDescription format;
    uint64_t callbacks, frames, invalid;
    UInt32 minFrames, maxFrames;
    double maxRMS, maxSampleGap, maxHostGapUs, maxAgeMs;
    double previousSample;
    uint64_t previousHost;
    UInt32 previousFrames;
    double tickSeconds;
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
    return noErr;
}

int main(void) {
    @autoreleasepool {
        if (geteuid() == 0) { fprintf(stderr, "Run as the logged-in desktop user, not root.\n"); return 2; }
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        setbuf(stdout, NULL);
        AudioObjectID tap = kAudioObjectUnknown, aggregate = kAudioObjectUnknown;
        AudioDeviceIOProcID proc = NULL;
        BOOL started = NO;
        int result = 1;
        TapMeasurements measurements = {0};
        mach_timebase_info_data_t clock;
        mach_timebase_info(&clock);
        measurements.tickSeconds = (double)clock.numer / clock.denom / 1e9;
        // The feasibility probe captures the global stereo mix; the production
        // session ownership/process-exclusion policy is a separate release gate.
        CATapDescription* description = [[CATapDescription alloc] initStereoGlobalTapButExcludeProcesses:@[]];
        description.name = @"PLANK Audio Tap Qualification";
        description.privateTap = YES;
        description.muteBehavior = CATapMutedWhenTapped;
        printf("tap_probe stage=create mute=when-tapped duration_seconds=10 stored_audio=0\n");
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
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 10, false);
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
        printf("tap_probe callbacks=%llu frames=%llu invalid=%llu chunk_min=%u chunk_max=%u max_rms=%.6f sample_gap_frames=%.3f host_gap_us=%.3f max_age_ms=%.3f result=%d\n",
            (unsigned long long)measurements.callbacks, (unsigned long long)measurements.frames,
            (unsigned long long)measurements.invalid, measurements.minFrames, measurements.maxFrames,
            measurements.maxRMS, measurements.maxSampleGap, measurements.maxHostGapUs, measurements.maxAgeMs, result);
        if (!measurements.callbacks || measurements.invalid) result = 1;
        return result;
    }
}
