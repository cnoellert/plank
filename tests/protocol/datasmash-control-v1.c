/* SPDX-License-Identifier: GPL-3.0-only */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "stationconnect_datasmash_control.h"

#define CHECK(condition) do { if (!(condition)) abort(); } while (0)

static void check_empty_message(void) {
    static const uint8_t expected[] = {
        0x53, 0x43, 0x44, 0x31, 0x00, 0x03, 0x00, 0x00,
    };
    uint8_t encoded[SC_DATASMASH_CONTROL_MAX_PACKET_SIZE] = {0};
    size_t encoded_size = 0;
    ScDatasmashControlPacket decoded;

    CHECK(sc_datasmash_control_encode(
               SC_DATASMASH_CONTROL_REQUEST_IDR, NULL, 0,
               encoded, sizeof(encoded), &encoded_size) == 0);
    CHECK(encoded_size == sizeof(expected));
    CHECK(memcmp(encoded, expected, sizeof(expected)) == 0);
    CHECK(sc_datasmash_control_decode(
               encoded, encoded_size, &decoded) == 0);
    CHECK(decoded.type == SC_DATASMASH_CONTROL_REQUEST_IDR);
    CHECK(decoded.payload_size == 0);
}

static void check_multiword_message(void) {
    static const uint8_t expected[] = {
        0x53, 0x43, 0x44, 0x31, 0x00, 0x06, 0x00, 0x0c,
        0x00, 0x00, 0xcd, 0x14,
        0x00, 0x00, 0xcd, 0x14,
        0x00, 0x01, 0x33, 0x9e,
    };
    const uint32_t values[] = {52500, 52500, 78750};
    uint8_t encoded[SC_DATASMASH_CONTROL_MAX_PACKET_SIZE] = {0};
    size_t encoded_size = 0;
    ScDatasmashControlPacket decoded;

    CHECK(sc_datasmash_control_encode(
               SC_DATASMASH_CONTROL_VIDEO_BITRATE_APPLIED,
               values, 3, encoded, sizeof(encoded), &encoded_size) == 0);
    CHECK(encoded_size == sizeof(expected));
    CHECK(memcmp(encoded, expected, sizeof(expected)) == 0);
    CHECK(sc_datasmash_control_decode(
               encoded, encoded_size, &decoded) == 0);
    CHECK(decoded.type == SC_DATASMASH_CONTROL_VIDEO_BITRATE_APPLIED);
    CHECK(decoded.payload_size == 12);
    CHECK(sc_datasmash_control_read_u32(decoded.payload) == 52500);
    CHECK(sc_datasmash_control_read_u32(decoded.payload + 4) == 52500);
    CHECK(sc_datasmash_control_read_u32(decoded.payload + 8) == 78750);
}

static void check_malformed_messages(void) {
    uint8_t encoded[SC_DATASMASH_CONTROL_MAX_PACKET_SIZE] = {0};
    const uint32_t value = 1;
    size_t encoded_size = 0;
    ScDatasmashControlPacket decoded;

    CHECK(sc_datasmash_control_encode(
               SC_DATASMASH_CONTROL_SET_VIDEO_BITRATE, &value, 1,
               encoded, sizeof(encoded), &encoded_size) == 0);
    CHECK(sc_datasmash_control_decode(
               encoded, encoded_size - 1, &decoded) == -1);
    encoded[0] = 0;
    CHECK(sc_datasmash_control_decode(
               encoded, encoded_size, &decoded) == -1);
    CHECK(sc_datasmash_control_encode(
               SC_DATASMASH_CONTROL_SET_VIDEO_BITRATE, &value, 1,
               encoded, SC_DATASMASH_CONTROL_HEADER_SIZE, &encoded_size) == -1);
}

int main(void) {
    check_empty_message();
    check_multiword_message();
    check_malformed_messages();
    return 0;
}
