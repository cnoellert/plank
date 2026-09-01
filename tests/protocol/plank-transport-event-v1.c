/* SPDX-License-Identifier: GPL-3.0-only */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "plank_transport_event.h"

#define CHECK(condition) do { if (!(condition)) abort(); } while (0)

int main(void) {
    static const uint8_t payload[] = {0x00, 0x00, 0x0f, 0xff, 0x08, 0x6f};
    static const uint8_t expected[] = {
        0x50, 0x4c, 0x45, 0x31, 0x00, 0x04, 0x00, 0x06,
        0x00, 0x00, 0x0f, 0xff, 0x08, 0x6f,
    };
    uint8_t encoded[sizeof(expected)];
    size_t encoded_size = 0;
    PlankTransportEventPacket decoded;

    CHECK(plank_transport_event_encode(
        PLANK_TRANSPORT_EVENT_CURSOR_POSITION, payload, sizeof(payload),
        encoded, sizeof(encoded), &encoded_size) == 0);
    CHECK(encoded_size == sizeof(expected));
    CHECK(memcmp(encoded, expected, sizeof(expected)) == 0);
    CHECK(plank_transport_event_decode(encoded, encoded_size, &decoded) == 0);
    CHECK(decoded.type == PLANK_TRANSPORT_EVENT_CURSOR_POSITION);
    CHECK(decoded.payload_size == sizeof(payload));
    CHECK(memcmp(decoded.payload, payload, sizeof(payload)) == 0);
    CHECK(plank_transport_event_decode(encoded, encoded_size - 1, &decoded) == -1);
    return 0;
}
