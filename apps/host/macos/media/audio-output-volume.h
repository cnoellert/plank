// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <CoreAudio/CoreAudio.h>
#include <math.h>

// Read-only default-output policy. Devices without volume controls (for
// example some digital outputs) use unity; failed reads must not unmute audio.
static inline BOOL PLANKOutputValue(AudioObjectID device, AudioObjectPropertySelector selector,
                                    AudioObjectPropertyElement channel, void *value, UInt32 bytes,
                                    BOOL *present) {
    AudioObjectPropertyAddress address = {selector, kAudioObjectPropertyScopeOutput, channel};
    *present = AudioObjectHasProperty(device, &address);
    if (!*present) return YES;
    UInt32 actual = bytes;
    return AudioObjectGetPropertyData(device, &address, 0, NULL, &actual, value) == noErr && actual == bytes;
}
static inline BOOL PLANKOutputGains(AudioObjectID device, float gains[2]) {
    gains[0] = gains[1] = 0;
    if (!device) return NO;
    Float32 master = 1; UInt32 mute = 0; BOOL hasMaster = NO, present = NO;
    if (!PLANKOutputValue(device, kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain,
                         &master, sizeof(master), &hasMaster) || !isfinite(master) || master < 0 || master > 1 ||
        !PLANKOutputValue(device, kAudioDevicePropertyMute, kAudioObjectPropertyElementMain,
                         &mute, sizeof(mute), &present)) return NO;
    UInt32 channels[2] = {1, 2};
    if (!PLANKOutputValue(device, kAudioDevicePropertyPreferredChannelsForStereo, kAudioObjectPropertyElementMain,
                         channels, sizeof(channels), &present)) return NO;
    float result[2];
    for (unsigned i = 0; i < 2; ++i) {
        Float32 volume = master; UInt32 channelMute = 0;
        if ((!hasMaster && !PLANKOutputValue(device, kAudioDevicePropertyVolumeScalar, channels[i],
                                            &volume, sizeof(volume), &present)) ||
            !PLANKOutputValue(device, kAudioDevicePropertyMute, channels[i], &channelMute, sizeof(channelMute), &present) ||
            !isfinite(volume) || volume < 0 || volume > 1) return NO;
        result[i] = mute || channelMute ? 0 : volume;
    }
    gains[0] = result[0]; gains[1] = result[1];
    return YES;
}
