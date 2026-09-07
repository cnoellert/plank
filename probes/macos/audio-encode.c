// SPDX-License-Identifier: GPL-3.0-or-later
// Synthetic PCM -> Apple Opus, no device access. Output is a test fixture only.
#include <AudioToolbox/AudioToolbox.h>
#include <fcntl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define REQUIRE(x) do { if (!(x)) { fprintf(stderr, "failed line %d: %s\n", __LINE__, #x); exit(1); } } while (0)
enum { Rate = 48000, Channels = 2, PacketFrames = 240, TotalFrames = 96000 };
typedef struct { float* samples; unsigned consumed; } Input;

static OSStatus provide(AudioConverterRef converter, UInt32* packets,
                        AudioBufferList* buffers, AudioStreamPacketDescription** descriptions, void* context) {
    (void)converter;
    Input* input = context;
    unsigned count = *packets;
    if (count > TotalFrames - input->consumed) count = TotalFrames - input->consumed;
    *packets = count;
    buffers->mNumberBuffers = 1;
    buffers->mBuffers[0].mNumberChannels = Channels;
    buffers->mBuffers[0].mDataByteSize = count * Channels * sizeof(float);
    buffers->mBuffers[0].mData = input->samples + input->consumed * Channels;
    input->consumed += count;
    if (descriptions) *descriptions = NULL;
    return noErr;
}

static void write32(FILE* file, UInt32 value) {
    unsigned char bytes[4] = {value & 255, (value >> 8) & 255, (value >> 16) & 255, value >> 24};
    REQUIRE(fwrite(bytes, 1, 4, file) == 4);
}

int main(int argc, const char** argv) {
    if (argc != 2) return 2;
    alarm(20);
    AudioStreamBasicDescription source = {0}, destination = {0};
    source.mSampleRate = destination.mSampleRate = Rate;
    source.mFormatID = kAudioFormatLinearPCM;
    source.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    source.mBytesPerPacket = source.mBytesPerFrame = Channels * sizeof(float);
    source.mFramesPerPacket = 1;
    source.mChannelsPerFrame = destination.mChannelsPerFrame = Channels;
    source.mBitsPerChannel = sizeof(float) * 8;
    destination.mFormatID = kAudioFormatOpus;
    destination.mFramesPerPacket = PacketFrames;
    AudioConverterRef converter = NULL;
    REQUIRE(AudioConverterNew(&source, &destination, &converter) == noErr && converter);
    UInt32 bitrate = 96000;
    REQUIRE(AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate, sizeof(bitrate), &bitrate) == noErr);
    UInt32 size = sizeof(destination);
    REQUIRE(AudioConverterGetProperty(converter, kAudioConverterCurrentOutputStreamDescription, &size, &destination) == noErr);
    REQUIRE(destination.mSampleRate == Rate && destination.mChannelsPerFrame == Channels && destination.mFramesPerPacket == PacketFrames);
    AudioConverterPrimeInfo prime = {0};
    size = sizeof(prime);
    OSStatus primeStatus = AudioConverterGetProperty(converter, kAudioConverterPrimeInfo, &size, &prime);
    UInt32 maximum = 0;
    size = sizeof(maximum);
    REQUIRE(AudioConverterGetProperty(converter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &maximum) == noErr);
    REQUIRE(maximum > 0 && maximum <= 65536);
    unsigned char* packet = malloc(maximum);
    Input input = {calloc(TotalFrames * Channels, sizeof(float)), 0};
    REQUIRE(packet && input.samples);
    for (unsigned frame = 0; frame < TotalFrames; ++frame) {
        input.samples[frame * 2] = 0.25f * sinf(2 * M_PI * 440 * frame / Rate);
        input.samples[frame * 2 + 1] = 0.25f * sinf(2 * M_PI * 880 * frame / Rate);
    }
    int descriptor = open(argv[1], O_WRONLY | O_CREAT | O_EXCL, 0600);
    REQUIRE(descriptor >= 0);
    FILE* file = fdopen(descriptor, "wb");
    REQUIRE(file);
    REQUIRE(fwrite("PAO1", 1, 4, file) == 4);
    write32(file, Rate); write32(file, Channels); write32(file, PacketFrames);
    unsigned packetsWritten = 0, bytesWritten = 0;
    for (;;) {
        AudioBufferList buffers = {0};
        buffers.mNumberBuffers = 1;
        buffers.mBuffers[0].mNumberChannels = Channels;
        buffers.mBuffers[0].mData = packet;
        buffers.mBuffers[0].mDataByteSize = maximum;
        AudioStreamPacketDescription description = {0};
        UInt32 packets = 1;
        OSStatus status = AudioConverterFillComplexBuffer(converter, provide, &input, &packets, &buffers, &description);
        REQUIRE(status == noErr);
        if (!packets) break;
        REQUIRE(packets == 1 && packetsWritten < 1000);
        REQUIRE(description.mStartOffset == 0 && description.mDataByteSize > 0 && description.mDataByteSize <= maximum);
        REQUIRE(description.mVariableFramesInPacket == 0 || description.mVariableFramesInPacket == PacketFrames);
        write32(file, description.mDataByteSize);
        REQUIRE(fwrite(packet, 1, description.mDataByteSize, file) == description.mDataByteSize);
        bytesWritten += description.mDataByteSize;
        packetsWritten++;
    }
    REQUIRE(input.consumed == TotalFrames && packetsWritten >= TotalFrames / PacketFrames);
    REQUIRE(fclose(file) == 0);
    printf("apple_opus synthetic_frames=%u packets=%u bytes=%u rate=%u channels=%u packet_frames=%u bitrate=%u prime_status=%d leading_frames=%u trailing_frames=%u\n",
           input.consumed, packetsWritten, bytesWritten, Rate, Channels, PacketFrames, bitrate,
           (int)primeStatus, (unsigned)prime.leadingFrames, (unsigned)prime.trailingFrames);
    free(packet); free(input.samples); AudioConverterDispose(converter);
    return 0;
}
