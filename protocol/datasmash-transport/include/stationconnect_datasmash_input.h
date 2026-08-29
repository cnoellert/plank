/* SPDX-License-Identifier: AGPL-3.0-or-later */

#ifndef STATIONCONNECT_DATASMASH_INPUT_H
#define STATIONCONNECT_DATASMASH_INPUT_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Native KyProto input messages carry their type in Kyber's InputPacket.
 * Each type below therefore defines its complete payload directly, without a
 * GameStream input header, nested encryption envelope, or transport shim.
 * Adding or changing a payload requires a new type value.
 */
typedef enum ScDatasmashInputType {
    SC_DATASMASH_INPUT_ABSOLUTE_MOUSE = 1,
    SC_DATASMASH_INPUT_MOUSE_BUTTON = 2,
    SC_DATASMASH_INPUT_VERTICAL_SCROLL = 3,
    SC_DATASMASH_INPUT_HORIZONTAL_SCROLL = 4,
    SC_DATASMASH_INPUT_KEYBOARD = 5,
    SC_DATASMASH_INPUT_UTF8_TEXT = 6,
    SC_DATASMASH_INPUT_PEN = 7,
    SC_DATASMASH_INPUT_RAW_HID_WACOM = 8,
} ScDatasmashInputType;

#define SC_DATASMASH_INPUT_ABSOLUTE_MOUSE_SIZE 8u
#define SC_DATASMASH_INPUT_MOUSE_BUTTON_SIZE 2u
#define SC_DATASMASH_INPUT_SCROLL_SIZE 2u
#define SC_DATASMASH_INPUT_KEYBOARD_SIZE 5u
#define SC_DATASMASH_INPUT_PEN_SIZE 32u
#define SC_DATASMASH_INPUT_MAX_PAYLOAD_SIZE 8192u

#define SC_DATASMASH_INPUT_ACTION_RELEASE 0u
#define SC_DATASMASH_INPUT_ACTION_PRESS 1u

static inline void sc_datasmash_input_write_u16(uint8_t *output,
                                                 uint16_t value) {
    output[0] = (uint8_t)(value >> 8);
    output[1] = (uint8_t)value;
}

static inline void sc_datasmash_input_write_u32(uint8_t *output,
                                                 uint32_t value) {
    output[0] = (uint8_t)(value >> 24);
    output[1] = (uint8_t)(value >> 16);
    output[2] = (uint8_t)(value >> 8);
    output[3] = (uint8_t)value;
}

static inline uint16_t sc_datasmash_input_read_u16(const uint8_t *input) {
    return (uint16_t)(((uint16_t)input[0] << 8) | input[1]);
}

static inline uint32_t sc_datasmash_input_read_u32(const uint8_t *input) {
    return ((uint32_t)input[0] << 24) |
           ((uint32_t)input[1] << 16) |
           ((uint32_t)input[2] << 8) |
           (uint32_t)input[3];
}

static inline void sc_datasmash_input_write_float(uint8_t *output,
                                                   float value) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    sc_datasmash_input_write_u32(output, bits);
}

static inline float sc_datasmash_input_read_float(const uint8_t *input) {
    uint32_t bits = sc_datasmash_input_read_u32(input);
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

static inline void sc_datasmash_input_encode_absolute_mouse(
        uint8_t output[SC_DATASMASH_INPUT_ABSOLUTE_MOUSE_SIZE],
        uint16_t x, uint16_t y, uint16_t maximum_x, uint16_t maximum_y) {
    sc_datasmash_input_write_u16(output, x);
    sc_datasmash_input_write_u16(output + 2, y);
    sc_datasmash_input_write_u16(output + 4, maximum_x);
    sc_datasmash_input_write_u16(output + 6, maximum_y);
}

static inline void sc_datasmash_input_encode_pen(
        uint8_t output[SC_DATASMASH_INPUT_PEN_SIZE],
        uint8_t event_type, uint8_t tool_type, uint8_t buttons, uint8_t tilt,
        uint16_t rotation, float x, float y, float pressure_or_distance,
        float contact_area_major, float contact_area_minor) {
    output[0] = event_type;
    output[1] = tool_type;
    output[2] = buttons;
    output[3] = tilt;
    sc_datasmash_input_write_u16(output + 4, rotation);
    output[6] = 0;
    output[7] = 0;
    sc_datasmash_input_write_float(output + 8, x);
    sc_datasmash_input_write_float(output + 12, y);
    sc_datasmash_input_write_float(output + 16, pressure_or_distance);
    sc_datasmash_input_write_float(output + 20, contact_area_major);
    sc_datasmash_input_write_float(output + 24, contact_area_minor);
    sc_datasmash_input_write_u32(output + 28, 0);
}

#ifdef __cplusplus
}
#endif

#endif
