// SPDX-License-Identifier: GPL-3.0-or-later
// Decode synthetic Apple packets through the Client's existing Opus layout.
#include <opus/opus_multistream.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define REQUIRE(x) do { if (!(x)) { fprintf(stderr, "failed line %d: %s\n", __LINE__, #x); exit(1); } } while (0)
static uint32_t read32(FILE* file) {
    unsigned char bytes[4];
    REQUIRE(fread(bytes, 1, 4, file) == 4);
    return (uint32_t)bytes[0] | (uint32_t)bytes[1] << 8 | (uint32_t)bytes[2] << 16 | (uint32_t)bytes[3] << 24;
}
int main(int argc, char** argv) {
    if (argc != 2 && !(argc == 3 && !strcmp(argv[2], "--measure-priming"))) return 2;
    FILE* file = fopen(argv[1], "rb");
    REQUIRE(file);
    char magic[4];
    REQUIRE(fread(magic, 1, 4, file) == 4 && !memcmp(magic, "PAO1", 4));
    REQUIRE(read32(file) == 48000 && read32(file) == 2 && read32(file) == 240);
    const unsigned char mapping[2] = {0, 1};
    int error;
    OpusMSDecoder* decoder = opus_multistream_decoder_create(48000, 2, 1, 1, mapping, &error);
    REQUIRE(error == OPUS_OK && decoder);
    unsigned packetCount = 0, samples = 0, measured = 0;
    double energy[2] = {0}, real[2][2] = {{0}}, imaginary[2][2] = {{0}};
    float beginning[4800][2] = {{0}};
    for (;;) {
        int next = fgetc(file);
        if (next == EOF) break;
        REQUIRE(ungetc(next, file) != EOF);
        uint32_t bytes = read32(file);
        unsigned char packet[65536];
        float decoded[240 * 2];
        REQUIRE(bytes > 0 && bytes <= sizeof(packet));
        REQUIRE(fread(packet, 1, bytes, file) == bytes);
        REQUIRE(opus_packet_get_nb_samples(packet, bytes, 48000) == 240);
        REQUIRE(opus_multistream_decode_float(decoder, packet, bytes, decoded, 240, 0) == 240);
        REQUIRE(++packetCount <= 1000);
        for (unsigned i = 0; i < 240; ++i, ++samples) {
            for (unsigned channel = 0; channel < 2; ++channel) {
                REQUIRE(isfinite(decoded[i * 2 + channel]) && fabsf(decoded[i * 2 + channel]) < 1.0f);
                if (samples < 4800) beginning[samples][channel] = decoded[i * 2 + channel];
            }
            // Whole 1-second measurement, beyond startup and before EOF padding.
            if (samples < 24000 || samples >= 72000) continue;
            measured++;
            for (unsigned channel = 0; channel < 2; ++channel) {
                const double value = decoded[i * 2 + channel];
                energy[channel] += value * value;
                for (unsigned tone = 0; tone < 2; ++tone) {
                    const double phase = 2 * M_PI * (tone ? 880 : 440) * samples / 48000;
                    real[channel][tone] += value * cos(phase);
                    imaginary[channel][tone] += value * sin(phase);
                }
            }
        }
    }
    REQUIRE(!ferror(file) && samples >= 96000 && samples < 100800 && measured == 48000);
    if (argc == 3) {
        double best = INFINITY; unsigned lag = 0;
        for (unsigned candidate = 0; candidate <= 960; ++candidate) {
            double errorSum = 0;
            for (unsigned frame = 0; frame < 4800; ++frame) for (unsigned channel = 0; channel < 2; ++channel) {
                double expected = frame < candidate ? 0 :
                    0.25 * sin(2 * M_PI * (channel ? 880 : 440) * (frame - candidate) / 48000);
                double difference = beginning[frame][channel] - expected;
                errorSum += difference * difference;
            }
            if (errorSum < best) { best = errorSum; lag = candidate; }
        }
        printf("decoded_priming_best_lag_frames=%u mse=%.8f\n", lag, best / 9600);
        REQUIRE(lag >= 308 && lag <= 316);
    }
    for (unsigned channel = 0; channel < 2; ++channel) {
        double rms = sqrt(energy[channel] / measured);
        double wanted = hypot(real[channel][channel], imaginary[channel][channel]);
        double other = hypot(real[channel][1 - channel], imaginary[channel][1 - channel]);
        REQUIRE(rms > 0.15 && rms < 0.20 && wanted > other * 100);
        printf("channel=%u rms=%.6f tone_separation_db=%.1f\n", channel, rms, 20 * log10(wanted / fmax(other, 1e-12)));
    }
    printf("apple_opus_client_decode=pass packets=%u samples=%u packet_ms=5 opus=%s\n", packetCount, samples, opus_get_version_string());
    opus_multistream_decoder_destroy(decoder);
    fclose(file);
    return 0;
}
