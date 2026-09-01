/* SPDX-License-Identifier: GPL-3.0-only */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "plank_transport_control.h"

#define CHECK(condition) do { if (!(condition)) abort(); } while (0)

static void check_empty_message(void) {
    static const uint8_t expected[] = {
        0x50, 0x4c, 0x44, 0x31, 0x00, 0x03, 0x00, 0x00,
    };
    uint8_t encoded[PLANK_TRANSPORT_CONTROL_MAX_PACKET_SIZE] = {0};
    size_t encoded_size = 0;
    PlankTransportControlPacket decoded;

    CHECK(plank_transport_control_encode(
               PLANK_TRANSPORT_CONTROL_REQUEST_IDR, NULL, 0,
               encoded, sizeof(encoded), &encoded_size) == 0);
    CHECK(encoded_size == sizeof(expected));
    CHECK(memcmp(encoded, expected, sizeof(expected)) == 0);
    CHECK(plank_transport_control_decode(
               encoded, encoded_size, &decoded) == 0);
    CHECK(decoded.type == PLANK_TRANSPORT_CONTROL_REQUEST_IDR);
    CHECK(decoded.payload_size == 0);
}

static void check_multiword_message(void) {
    static const uint8_t expected[] = {
        0x50, 0x4c, 0x44, 0x31, 0x00, 0x06, 0x00, 0x0c,
        0x00, 0x00, 0xcd, 0x14,
        0x00, 0x00, 0xcd, 0x14,
        0x00, 0x01, 0x33, 0x9e,
    };
    const uint32_t values[] = {52500, 52500, 78750};
    uint8_t encoded[PLANK_TRANSPORT_CONTROL_MAX_PACKET_SIZE] = {0};
    size_t encoded_size = 0;
    PlankTransportControlPacket decoded;

    CHECK(plank_transport_control_encode(
               PLANK_TRANSPORT_CONTROL_VIDEO_BITRATE_APPLIED,
               values, 3, encoded, sizeof(encoded), &encoded_size) == 0);
    CHECK(encoded_size == sizeof(expected));
    CHECK(memcmp(encoded, expected, sizeof(expected)) == 0);
    CHECK(plank_transport_control_decode(
               encoded, encoded_size, &decoded) == 0);
    CHECK(decoded.type == PLANK_TRANSPORT_CONTROL_VIDEO_BITRATE_APPLIED);
    CHECK(decoded.payload_size == 12);
    CHECK(plank_transport_control_read_u32(decoded.payload) == 52500);
    CHECK(plank_transport_control_read_u32(decoded.payload + 4) == 52500);
    CHECK(plank_transport_control_read_u32(decoded.payload + 8) == 78750);
}

static void check_session_takeover_reason(void) {
    uint8_t encoded[PLANK_TRANSPORT_CONTROL_MAX_PACKET_SIZE] = {0};
    const uint32_t reason = PLANK_TRANSPORT_TERMINATION_SESSION_TAKEN_OVER;
    size_t encoded_size = 0;
    PlankTransportControlPacket decoded;

    CHECK(plank_transport_control_encode(
               PLANK_TRANSPORT_CONTROL_HOST_TERMINATE, &reason, 1,
               encoded, sizeof(encoded), &encoded_size) == 0);
    CHECK(plank_transport_control_decode(
               encoded, encoded_size, &decoded) == 0);
    CHECK(decoded.type == PLANK_TRANSPORT_CONTROL_HOST_TERMINATE);
    CHECK(decoded.payload_size == sizeof(uint32_t));
    CHECK(plank_transport_control_read_u32(decoded.payload) ==
          PLANK_TRANSPORT_TERMINATION_SESSION_TAKEN_OVER);
    CHECK(PLANK_TRANSPORT_TERMINATION_SESSION_TAKEN_OVER !=
          PLANK_TRANSPORT_TERMINATION_GRACEFUL);
}

static void check_malformed_messages(void) {
    uint8_t encoded[PLANK_TRANSPORT_CONTROL_MAX_PACKET_SIZE] = {0};
    const uint32_t value = 1;
    size_t encoded_size = 0;
    PlankTransportControlPacket decoded;

    CHECK(plank_transport_control_encode(
               PLANK_TRANSPORT_CONTROL_SET_VIDEO_BITRATE, &value, 1,
               encoded, sizeof(encoded), &encoded_size) == 0);
    CHECK(plank_transport_control_decode(
               encoded, encoded_size - 1, &decoded) == -1);
    encoded[0] = 0;
    CHECK(plank_transport_control_decode(
               encoded, encoded_size, &decoded) == -1);
    CHECK(plank_transport_control_encode(
               PLANK_TRANSPORT_CONTROL_SET_VIDEO_BITRATE, &value, 1,
               encoded, PLANK_TRANSPORT_CONTROL_HEADER_SIZE, &encoded_size) == -1);
}

int main(void) {
    check_empty_message();
    check_multiword_message();
    check_session_takeover_reason();
    check_malformed_messages();
    return 0;
}
