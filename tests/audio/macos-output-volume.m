// SPDX-License-Identifier: GPL-3.0-or-later
// Synthetic HAL reads only. No device changes, IO, permission or user settings.
#import <Foundation/Foundation.h>
#import "audio-output-volume.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static BOOL masterPresent = YES, channelsPresent, mutePresent = YES, failRead;
static Float32 master = .5f, channelVolumes[2] = {.25f, .75f};
static UInt32 muted, channelMutes[2];
Boolean AudioObjectHasProperty(AudioObjectID object, const AudioObjectPropertyAddress *p) {
    assert(object == 42);
    if (p->mSelector == kAudioDevicePropertyPreferredChannelsForStereo) return YES;
    if (p->mSelector == kAudioDevicePropertyVolumeScalar)
        return p->mElement == 0 ? masterPresent : channelsPresent;
    if (p->mSelector == kAudioDevicePropertyMute) return mutePresent;
    abort();
}
OSStatus AudioObjectGetPropertyData(AudioObjectID object, const AudioObjectPropertyAddress *p,
    UInt32 qualifierSize, const void *qualifier, UInt32 *size, void *data) {
    assert(object == 42 && !qualifierSize && !qualifier && p->mScope == kAudioObjectPropertyScopeOutput);
    if (failRead) return kAudioHardwareBadObjectError;
    if (p->mSelector == kAudioDevicePropertyPreferredChannelsForStereo) {
        assert(*size == 8); UInt32 channels[] = {3, 4}; memcpy(data, channels, 8); return noErr;
    }
    assert(*size == 4);
    if (p->mSelector == kAudioDevicePropertyVolumeScalar)
        *(Float32 *)data = p->mElement == 0 ? master : channelVolumes[p->mElement - 3];
    else *(UInt32 *)data = p->mElement == 0 ? muted : channelMutes[p->mElement - 3];
    return noErr;
}
int main(void) {
    float gains[2];
    assert(!PLANKOutputGains(0, gains) && !gains[0] && !gains[1]);
    assert(PLANKOutputGains(42, gains) && gains[0] == .5f && gains[1] == .5f);
    muted = 1;
    assert(PLANKOutputGains(42, gains) && !gains[0] && !gains[1]);
    muted = 0; master = 0;
    assert(PLANKOutputGains(42, gains) && !gains[0] && !gains[1]);
    master = 1;
    assert(PLANKOutputGains(42, gains) && gains[0] == 1 && gains[1] == 1);
    masterPresent = NO; channelsPresent = YES;
    assert(PLANKOutputGains(42, gains) && gains[0] == .25f && gains[1] == .75f);
    channelMutes[1] = 1;
    assert(PLANKOutputGains(42, gains) && gains[0] == .25f && !gains[1]);
    channelMutes[1] = 0; channelsPresent = mutePresent = NO;
    assert(PLANKOutputGains(42, gains) && gains[0] == 1 && gains[1] == 1);
    failRead = YES;
    assert(!PLANKOutputGains(42, gains) && !gains[0] && !gains[1]);
    failRead = NO; masterPresent = YES; master = NAN;
    assert(!PLANKOutputGains(42, gains) && !gains[0] && !gains[1]);
    puts("macos_output_volume=pass master=1 channels=1 mute=1 fixed_output=1 fail_closed=1 real_hal=0");
}
