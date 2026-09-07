// SPDX-License-Identifier: GPL-3.0-or-later
// Synthetic PCM -> Apple Opus, no device access. Output is a test fixture only.
#include <AudioToolbox/AudioToolbox.h>
#include <fcntl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>

#define REQUIRE(x) do { if (!(x)) { fprintf(stderr, "failed line %d: %s\n", __LINE__, #x); exit(1); } } while (0)
enum { Rate = 48000, Channels = 2, PacketFrames = 240, TotalFrames = 96000 };
enum { InputStarved = -7777 };
typedef struct {
    float* samples;
    unsigned consumed, available, starves;
    bool ended;
} Input;

static OSStatus provide(AudioConverterRef converter, UInt32* packets,
                        AudioBufferList* buffers, AudioStreamPacketDescription** descriptions, void* context) {
    (void)converter;
    Input* input = context;
    unsigned count = *packets;
    if (count > input->available - input->consumed) count = input->available - input->consumed;
    *packets = count;
    buffers->mNumberBuffers = 1;
    buffers->mBuffers[0].mNumberChannels = Channels;
    buffers->mBuffers[0].mDataByteSize = count * Channels * sizeof(float);
    buffers->mBuffers[0].mData = input->samples + input->consumed * Channels;
    input->consumed += count;
    if (descriptions) *descriptions = NULL;
    if (!count && !input->ended) {
        input->starves++;
        // AudioConverter.h explicitly defines a callback error with zero
        // packets as temporary starvation, distinct from a successful EOF.
        return InputStarved;
    }
    return noErr;
}

static void write32(FILE* file, UInt32 value) {
    unsigned char bytes[4] = {value & 255, (value >> 8) & 255, (value >> 16) & 255, value >> 24};
    REQUIRE(fwrite(bytes, 1, 4, file) == 4);
}

int main(int argc, const char** argv) {
    if (argc != 2 && !(argc == 3 && (!strcmp(argv[2], "--incremental") || !strcmp(argv[2], "--reset")))) return 2;
    const bool incremental = argc == 3;
    const bool reset = incremental && !strcmp(argv[2], "--reset");
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
    Input input = {0};
    input.samples = calloc(TotalFrames * Channels, sizeof(float));
    input.available = incremental ? 0 : TotalFrames;
    input.ended = !incremental;
    REQUIRE(packet && input.samples);
    if (reset) {
        // Leave a partially consumed silence stream in the converter, then
        // reset before exposing any of the new stream. Warmup output is not
        // part of the fixture and must not leak into the new stream.
        input.available = 1000;
        for (;;) {
            AudioBufferList buffers = {0};
            buffers.mNumberBuffers = 1;
            buffers.mBuffers[0] = (AudioBuffer){Channels, maximum, packet};
            AudioStreamPacketDescription description = {0};
            UInt32 packets = 1;
            OSStatus result = AudioConverterFillComplexBuffer(converter, provide, &input, &packets, &buffers, &description);
            REQUIRE(result == noErr || result == InputStarved);
            if (result == InputStarved) break;
        }
        REQUIRE(input.consumed == 1000);
        REQUIRE(AudioConverterReset(converter) == noErr);
        input.consumed = input.available = input.starves = 0;
    }
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
    unsigned packetsWritten = 0, bytesWritten = 0, iteration = 0;
    unsigned availableHighWater = 0, largestConsumedAhead = 0;
    unsigned emptyRetries = 0, firstPacketInput = 0;
    const unsigned chunks[] = {1, 127, 511, 32, 240, 1000, 17, 960, 333};
    for (;;) {
        REQUIRE(iteration++ < 5000);
        AudioBufferList buffers = {0};
        buffers.mNumberBuffers = 1;
        buffers.mBuffers[0].mNumberChannels = Channels;
        buffers.mBuffers[0].mData = packet;
        buffers.mBuffers[0].mDataByteSize = maximum;
        AudioStreamPacketDescription description = {0};
        UInt32 packets = 1;
        OSStatus status = AudioConverterFillComplexBuffer(converter, provide, &input, &packets, &buffers, &description);
        REQUIRE(status == noErr || (incremental && status == InputStarved));
        if (packets) {
            REQUIRE(packets == 1 && packetsWritten < 1000);
            REQUIRE(description.mStartOffset == 0 && description.mDataByteSize > 0 && description.mDataByteSize <= maximum);
            REQUIRE(description.mVariableFramesInPacket == 0 || description.mVariableFramesInPacket == PacketFrames);
            write32(file, description.mDataByteSize);
            REQUIRE(fwrite(packet, 1, description.mDataByteSize, file) == description.mDataByteSize);
            bytesWritten += description.mDataByteSize;
            packetsWritten++;
            if (!firstPacketInput) firstPacketInput = input.consumed;
        }
        const unsigned outputFrames = packetsWritten * PacketFrames;
        if (input.consumed > outputFrames && input.consumed - outputFrames > largestConsumedAhead)
            largestConsumedAhead = input.consumed - outputFrames;
        if (status == InputStarved) {
            REQUIRE(input.consumed == input.available && !input.ended);
            // Repeated no-input calls must not signal EOF or emit padding.
            if (emptyRetries++ % 3 != 2) { REQUIRE(!packets); continue; }
            if (input.available == TotalFrames) {
                input.ended = true;
            } else {
                unsigned chunk = chunks[(emptyRetries / 3 - 1) % (sizeof(chunks) / sizeof(chunks[0]))];
                if (chunk > TotalFrames - input.available) chunk = TotalFrames - input.available;
                input.available += chunk;
                if (chunk > availableHighWater) availableHighWater = chunk;
            }
        } else if (!packets) {
            REQUIRE(input.ended);
            break;
        }
    }
    REQUIRE(input.consumed == TotalFrames && packetsWritten >= TotalFrames / PacketFrames);
    REQUIRE(fclose(file) == 0);
    printf("incremental=%d reset=%d starvation_callbacks=%u supplied_chunk_high_water=%u consumed_ahead_high_water=%u first_packet_consumed=%u\n",
           incremental, reset, input.starves, availableHighWater, largestConsumedAhead, firstPacketInput);
    printf("apple_opus synthetic_frames=%u packets=%u bytes=%u rate=%u channels=%u packet_frames=%u bitrate=%u prime_status=%d leading_frames=%u trailing_frames=%u\n",
           input.consumed, packetsWritten, bytesWritten, Rate, Channels, PacketFrames, bitrate,
           (int)primeStatus, (unsigned)prime.leadingFrames, (unsigned)prime.trailingFrames);
    free(packet); free(input.samples); AudioConverterDispose(converter);
    return 0;
}
