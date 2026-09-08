// SPDX-License-Identifier: GPL-3.0-or-later
#import "audio-tap.h"
#import "audio-tap-buffer.h"
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <CoreAudio/CATapDescription.h>
#include <libproc.h>
#include <unistd.h>

static AudioObjectPropertyAddress property(AudioObjectPropertySelector selector) {
    return (AudioObjectPropertyAddress){selector, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
}
typedef struct {
    PLANKTapBuffer buffer;
    __unsafe_unretained dispatch_source_t ready;
    BOOL planar;
} TapInput;

static OSStatus receive(AudioObjectID device, const AudioTimeStamp *now,
                         const AudioBufferList *input, const AudioTimeStamp *time,
                         AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    (void)device; (void)now; (void)output; (void)outputTime;
    TapInput *state = context;
    if (atomic_load_explicit(&state->buffer.stopped, memory_order_acquire)) return noErr;
    uint32_t bytes = state->planar ? 4 : 8;
    BOOL valid = input && input->mNumberBuffers == (state->planar ? 2u : 1u) &&
        time && (time->mFlags & kAudioTimeStampHostTimeValid);
    uint32_t frames = valid ? input->mBuffers[0].mDataByteSize / bytes : 0;
    for (uint32_t b = 0; valid && b < input->mNumberBuffers; b++)
        valid = input->mBuffers[b].mNumberChannels == (state->planar ? 1u : 2u) &&
            input->mBuffers[b].mData && input->mBuffers[b].mDataByteSize == frames * bytes;
    if (!valid) atomic_store(&state->buffer.failed, 1);
    else PLANKTapPush(&state->buffer, input->mBuffers[0].mData,
        state->planar ? input->mBuffers[1].mData : NULL, frames, time->mHostTime);
    dispatch_source_merge_data(state->ready, 1);
    return noErr;
}

@implementation PLANKMacAudioTap {
    dispatch_queue_t _owner, _control;
    dispatch_source_t _ready;
    TapInput *_input;
    BOOL (^_sample)(CMSampleBufferRef);
    void (^_failed)(void);
    BOOL _started, _stopped;
    AudioObjectID _tap, _device;
    AudioDeviceIOProcID _io;
    BOOL _running, _listening;
    CATapDescription *_description;
    AudioObjectPropertyListenerBlock _processesChanged;
    CMAudioFormatDescriptionRef _format;
}
- (instancetype)init { return nil; }
- (instancetype)initWithQueue:(dispatch_queue_t)queue sample:(BOOL (^)(CMSampleBufferRef))sample failed:(void (^)(void))failed {
    if (!queue || !sample || !failed || getuid() == 0 || geteuid() != getuid()) return nil;
    self = [super init];
    if (!self) return nil;
    _owner = queue; _sample = [sample copy]; _failed = [failed copy];
    _control = dispatch_queue_create("la.instinctual.PLANK.audio-tap", DISPATCH_QUEUE_SERIAL);
    _input = calloc(1, sizeof(*_input));
    if (!_input) return nil;
    PLANKTapBufferInit(&_input->buffer);
    _ready = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0, _owner);
    _input->ready = _ready;
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_ready, ^{ [weakSelf drain]; });
    dispatch_resume(_ready);
    return self;
}
- (NSArray<NSNumber *> *)ownedAudioProcesses {
    AudioObjectPropertyAddress address = property(kAudioHardwarePropertyProcessObjectList);
    UInt32 bytes = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &bytes) ||
        bytes % sizeof(AudioObjectID) || bytes > 65536) return nil;
    if (!bytes) return @[];
    NSMutableData *storage = [NSMutableData dataWithLength:bytes];
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &bytes, storage.mutableBytes)) return nil;
    NSMutableArray *owned = [NSMutableArray array];
    const AudioObjectID *objects = storage.bytes;
    for (UInt32 i = 0; i < bytes / sizeof(AudioObjectID); i++) {
        pid_t pid = 0; UInt32 size = sizeof(pid);
        AudioObjectPropertyAddress pidProperty = property(kAudioProcessPropertyPID);
        if (AudioObjectGetPropertyData(objects[i], &pidProperty, 0, NULL, &size, &pid) ||
            pid <= 0 || pid == getpid()) continue;
        struct proc_bsdinfo info = {0};
        if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info) ||
            info.pbi_uid != getuid() || info.pbi_ruid != getuid()) continue;
        // Re-read the HAL object's PID after the kernel ownership check.
        pid_t confirmed = 0; size = sizeof(confirmed);
        if (!AudioObjectGetPropertyData(objects[i], &pidProperty, 0, NULL, &size, &confirmed) && confirmed == pid)
            [owned addObject:@(objects[i])];
    }
    return owned;
}
- (BOOL)updateProcesses {
    NSArray *processes = [self ownedAudioProcesses];
    if (!processes) return NO;
    if ([_description.processes isEqual:processes]) return YES;
    _description.processes = processes;
    AudioObjectPropertyAddress address = property(kAudioTapPropertyDescription);
    CFTypeRef description = (__bridge CFTypeRef)_description;
    return AudioObjectSetPropertyData(_tap, &address, 0, NULL, sizeof(description), &description) == noErr;
}
- (BOOL)prepare {
    NSArray *processes = [self ownedAudioProcesses];
    if (!processes) return NO;
    _description = [[CATapDescription alloc] initStereoMixdownOfProcesses:processes];
    _description.name = @"PLANK Session Audio";
    _description.privateTap = YES;
    _description.processRestoreEnabled = NO; // no bundle-ID cross-user matching
    _description.muteBehavior = CATapMutedWhenTapped;
    if (AudioHardwareCreateProcessTap(_description, &_tap)) return NO;
    NSDictionary *specification = @{
        @kAudioAggregateDeviceNameKey: @"PLANK Private Session Audio",
        @kAudioAggregateDeviceUIDKey: NSUUID.UUID.UUIDString,
        @kAudioAggregateDeviceIsPrivateKey: @YES,
        @kAudioAggregateDeviceTapAutoStartKey: @NO,
        @kAudioAggregateDeviceTapListKey: @[@{
            @kAudioSubTapUIDKey: _description.UUID.UUIDString,
            @kAudioSubTapDriftCompensationKey: @YES}]
    };
    if (AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)specification, &_device)) return NO;
    // This device contains only our private tap, never the physical output.
    // Request the existing Opus input rate without changing user device settings.
    AudioObjectPropertyAddress rateProperty = property(kAudioDevicePropertyNominalSampleRate);
    Float64 rate = 48000;
    if (AudioObjectSetPropertyData(_device, &rateProperty, 0, NULL, sizeof(rate), &rate)) return NO;
    AudioObjectPropertyAddress formatProperty = {kAudioDevicePropertyStreamFormat, kAudioObjectPropertyScopeInput, kAudioObjectPropertyElementMain};
    AudioStreamBasicDescription format = {0}; UInt32 size = sizeof(format);
    if (AudioObjectGetPropertyData(_device, &formatProperty, 0, NULL, &size, &format) ||
        format.mFormatID != kAudioFormatLinearPCM || format.mSampleRate != 48000 ||
        format.mChannelsPerFrame != 2 || format.mBitsPerChannel != 32 ||
        !(format.mFormatFlags & kAudioFormatFlagIsFloat) || (format.mFormatFlags & kAudioFormatFlagIsBigEndian)) return NO;
    _input->planar = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    if (format.mBytesPerFrame != (_input->planar ? 4u : 8u)) return NO;
    format.mFormatFlags &= ~kAudioFormatFlagIsNonInterleaved;
    format.mBytesPerFrame = format.mBytesPerPacket = 8;
    if (CMAudioFormatDescriptionCreate(NULL, &format, 0, NULL, 0, NULL, NULL, &_format)) return NO;
    __weak typeof(self) weakSelf = self;
    _processesChanged = ^(UInt32 count, const AudioObjectPropertyAddress *addresses) {
        (void)count; (void)addresses;
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || atomic_load(&strongSelf->_input->buffer.stopped)) return;
        if (![strongSelf updateProcesses]) {
            atomic_store(&strongSelf->_input->buffer.failed, 3);
            dispatch_source_merge_data(strongSelf->_ready, 1);
        }
    };
    AudioObjectPropertyAddress processProperty = property(kAudioHardwarePropertyProcessObjectList);
    if (AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &processProperty, _control, _processesChanged)) return NO;
    _listening = YES;
    if (![self updateProcesses]) return NO; // close enumeration/listener setup race
    if (atomic_load(&_input->buffer.stopped)) return NO;
    if (AudioDeviceCreateIOProcID(_device, receive, _input, &_io) || AudioDeviceStart(_device, _io)) return NO;
    _running = YES;
    return YES;
}
- (void)startWithCompletion:(void (^)(BOOL))completion {
    if (_started || _stopped || !completion) { if (completion) completion(NO); return; }
    _started = YES;
    dispatch_async(_control, ^{
        BOOL ready = [self prepare];
        dispatch_async(self->_owner, ^{
            NSLog(@"PLANK desktop audio tap: ready=%d local-playback=muted-while-captured", ready);
            completion(ready && !self->_stopped);
        });
    });
}
- (void)drain {
    if (_stopped) return;
    if (atomic_load(&_input->buffer.failed)) { if (_failed) _failed(); return; }
    PLANKTapBlock *block;
    while (!_stopped && (block = PLANKTapPeek(&_input->buffer))) {
        @autoreleasepool {
            CMBlockBufferRef data = NULL; CMSampleBufferRef sample = NULL;
            size_t bytes = block->frames * 2 * sizeof(float);
            OSStatus result = CMBlockBufferCreateWithMemoryBlock(NULL, NULL, bytes, NULL, NULL, 0, bytes, 0, &data);
            if (!result) result = CMBlockBufferReplaceDataBytes(block->samples, data, 0, bytes);
            if (!result) result = CMAudioSampleBufferCreateReadyWithPacketDescriptions(NULL, data, _format,
                block->frames, CMClockMakeHostTimeFromSystemUnits(block->hostTime), NULL, &sample);
            BOOL delivered = !result && _sample && _sample(sample);
            if (sample) CFRelease(sample);
            if (data) CFRelease(data);
            PLANKTapPop(&_input->buffer);
            if (!delivered) { if (_failed) _failed(); return; }
        }
    }
}
- (void)stopWithCompletion:(void (^)(void))completion {
    if (_stopped) return; // one-shot owner calls exactly once
    _stopped = YES; _sample = nil; _failed = nil;
    atomic_store_explicit(&_input->buffer.stopped, true, memory_order_release);
    dispatch_async(_control, ^{
        BOOL clean = YES;
        if (self->_listening) {
            AudioObjectPropertyAddress address = property(kAudioHardwarePropertyProcessObjectList);
            clean &= AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject, &address, self->_control, self->_processesChanged) == noErr;
        }
        if (self->_running) clean &= AudioDeviceStop(self->_device, self->_io) == noErr;
        if (self->_io) clean &= AudioDeviceDestroyIOProcID(self->_device, self->_io) == noErr;
        if (self->_device) clean &= AudioHardwareDestroyAggregateDevice(self->_device) == noErr;
        if (self->_tap) clean &= AudioHardwareDestroyProcessTap(self->_tap) == noErr;
        // Do not reuse a worker after uncertain HAL teardown: process exit is
        // the final cleanup boundary and the machine service replaces its agent.
        if (!clean) { NSLog(@"PLANK audio tap teardown failed; retiring worker"); _exit(70); }
        self->_processesChanged = nil; self->_description = nil;
        dispatch_async(self->_owner, ^{
            dispatch_source_cancel(self->_ready);
            NSLog(@"PLANK desktop audio tap stopped; local playback released");
            if (completion) completion();
        });
    });
}
- (void)dealloc {
    if (_format) CFRelease(_format);
    free(_input);
}
@end
