// SPDX-License-Identifier: GPL-3.0-or-later
// Capability inventory only: no recording, playback, microphone, or device I/O.
// Creating a converter does not qualify packet output or Client compatibility.
#include <AudioToolbox/AudioToolbox.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void fourcc(UInt32 value, char text[5]) {
    for (unsigned i = 0; i < 4; ++i) {
        unsigned char c = (value >> (24 - i * 8)) & 255;
        text[i] = c >= 32 && c <= 126 ? (char)c : '?';
    }
    text[4] = 0;
}

int main(void) {
    const AudioFormatID format = kAudioFormatOpus;
    UInt32 size = 0;
    OSStatus status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders,
                                                sizeof(format), &format, &size);
    printf("opus_encoder_inventory_status=%d bytes=%u\n", (int)status, (unsigned)size);
    if (!status && size > 0 && size <= 65536 && size % sizeof(AudioClassDescription) == 0) {
        AudioClassDescription* classes = calloc(1, size);
        if (!classes) return 2;
        status = AudioFormatGetProperty(kAudioFormatProperty_Encoders,
                                       sizeof(format), &format, &size, classes);
        if (!status) {
            for (unsigned i = 0; i < size / sizeof(*classes); ++i) {
                char type[5], subtype[5], manufacturer[5];
                fourcc(classes[i].mType, type);
                fourcc(classes[i].mSubType, subtype);
                fourcc(classes[i].mManufacturer, manufacturer);
                printf("encoder type=%s subtype=%s manufacturer=%s\n", type, subtype, manufacturer);
            }
        }
        free(classes);
    }
    const unsigned frames[] = {120, 240, 480, 960};
    for (unsigned i = 0; i < sizeof(frames) / sizeof(frames[0]); ++i) {
        AudioStreamBasicDescription source = {0}, destination = {0};
        source.mSampleRate = destination.mSampleRate = 48000;
        source.mFormatID = kAudioFormatLinearPCM;
        source.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
        source.mBytesPerPacket = source.mBytesPerFrame = 2 * sizeof(float);
        source.mFramesPerPacket = 1;
        source.mChannelsPerFrame = destination.mChannelsPerFrame = 2;
        source.mBitsPerChannel = 8 * sizeof(float);
        destination.mFormatID = format;
        destination.mFramesPerPacket = frames[i];
        AudioConverterRef converter = NULL;
        status = AudioConverterNew(&source, &destination, &converter);
        printf("requested_packet_frames=%u requested_ms=%.1f converter_status=%d",
               frames[i], frames[i] / 48.0, (int)status);
        if (!status && converter) {
            size = sizeof(destination);
            OSStatus descriptionStatus = AudioConverterGetProperty(converter,
                kAudioConverterCurrentOutputStreamDescription, &size, &destination);
            printf(" description_status=%d actual_rate=%.0f actual_channels=%u actual_packet_frames=%u",
                   (int)descriptionStatus, destination.mSampleRate,
                   (unsigned)destination.mChannelsPerFrame, (unsigned)destination.mFramesPerPacket);
            AudioConverterDispose(converter);
        }
        putchar('\n');
    }
    puts("qualification=inventory-only actual_encoding=not-tested capture=not-started");
    return 0;
}
