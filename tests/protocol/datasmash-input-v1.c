/* SPDX-License-Identifier: GPL-3.0-only */

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "stationconnect_datasmash_input.h"

#define CHECK(condition) do { if (!(condition)) abort(); } while (0)

static void check_absolute_mouse(void) {
    static const uint8_t expected[] = {
        0x04, 0x00, 0x02, 0x00, 0x0f, 0xff, 0x08, 0x6f,
    };
    uint8_t payload[SC_DATASMASH_INPUT_ABSOLUTE_MOUSE_SIZE];

    sc_datasmash_input_encode_absolute_mouse(
        payload, 1024, 512, 4095, 2159);
    CHECK(memcmp(payload, expected, sizeof(expected)) == 0);
    CHECK(sc_datasmash_input_read_u16(payload) == 1024);
    CHECK(sc_datasmash_input_read_u16(payload + 2) == 512);
    CHECK(sc_datasmash_input_read_u16(payload + 4) == 4095);
    CHECK(sc_datasmash_input_read_u16(payload + 6) == 2159);
}

static void check_pen(void) {
    static const uint8_t expected[] = {
        0x02, 0x01, 0x01, 0x5a, 0x01, 0x0e, 0x00, 0x00,
        0x3f, 0x00, 0x00, 0x00, 0x3e, 0x80, 0x00, 0x00,
        0x3f, 0x40, 0x00, 0x00, 0x3d, 0xcc, 0xcc, 0xcd,
        0x3d, 0x4c, 0xcc, 0xcd, 0x00, 0x00, 0x00, 0x00,
    };
    uint8_t payload[SC_DATASMASH_INPUT_PEN_SIZE];

    sc_datasmash_input_encode_pen(
        payload, 2, 1, 1, 90, 270, 0.5f, 0.25f, 0.75f, 0.1f, 0.05f);
    CHECK(memcmp(payload, expected, sizeof(expected)) == 0);
    CHECK(fabsf(sc_datasmash_input_read_float(payload + 8) - 0.5f) < 0.000001f);
    CHECK(fabsf(sc_datasmash_input_read_float(payload + 16) - 0.75f) < 0.000001f);
    CHECK(sc_datasmash_input_read_u16(payload + 4) == 270);
}

int main(void) {
    check_absolute_mouse();
    check_pen();
    return 0;
}
