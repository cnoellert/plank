/* SPDX-License-Identifier: AGPL-3.0-or-later */

#ifndef STATIONCONNECT_DATASMASH_EVENT_H
#define STATIONCONNECT_DATASMASH_EVENT_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ASCII "SCE1": StationConnect native Host-to-Client event protocol. */
#define SC_DATASMASH_EVENT_MAGIC 0x53434531u
#define SC_DATASMASH_EVENT_HEADER_SIZE 8u
#define SC_DATASMASH_EVENT_MAX_PACKET_SIZE 65535u
#define SC_DATASMASH_EVENT_HDR_MODE_SIZE 28u

typedef enum ScDatasmashEventType {
    SC_DATASMASH_EVENT_HDR_MODE = 1,
    SC_DATASMASH_EVENT_RAW_HID_WACOM = 2,
    SC_DATASMASH_EVENT_CURSOR_SHAPE = 3,
    SC_DATASMASH_EVENT_CURSOR_POSITION = 4,
} ScDatasmashEventType;

typedef struct ScDatasmashEventPacket {
    uint16_t type;
    const uint8_t *payload;
    uint16_t payload_size;
} ScDatasmashEventPacket;

static inline void sc_datasmash_event_write_u16(uint8_t *output,
                                                 uint16_t value) {
    output[0] = (uint8_t)(value >> 8);
    output[1] = (uint8_t)value;
}

static inline void sc_datasmash_event_write_u32(uint8_t *output,
                                                 uint32_t value) {
    output[0] = (uint8_t)(value >> 24);
    output[1] = (uint8_t)(value >> 16);
    output[2] = (uint8_t)(value >> 8);
    output[3] = (uint8_t)value;
}

static inline uint16_t sc_datasmash_event_read_u16(const uint8_t *input) {
    return (uint16_t)(((uint16_t)input[0] << 8) | input[1]);
}

static inline uint32_t sc_datasmash_event_read_u32(const uint8_t *input) {
    return ((uint32_t)input[0] << 24) |
           ((uint32_t)input[1] << 16) |
           ((uint32_t)input[2] << 8) |
           (uint32_t)input[3];
}

static inline int sc_datasmash_event_encode(
        uint16_t type, const uint8_t *payload, size_t payload_size,
        uint8_t *output, size_t output_capacity, size_t *output_size) {
    const size_t packet_size = SC_DATASMASH_EVENT_HEADER_SIZE + payload_size;
    if (output == NULL || output_size == NULL ||
            (payload_size != 0 && payload == NULL) ||
            payload_size > UINT16_MAX || output_capacity < packet_size) {
        return -1;
    }
    sc_datasmash_event_write_u32(output, SC_DATASMASH_EVENT_MAGIC);
    sc_datasmash_event_write_u16(output + 4, type);
    sc_datasmash_event_write_u16(output + 6, (uint16_t)payload_size);
    if (payload_size != 0) {
        memcpy(output + SC_DATASMASH_EVENT_HEADER_SIZE, payload, payload_size);
    }
    *output_size = packet_size;
    return 0;
}

static inline int sc_datasmash_event_decode(
        const uint8_t *packet, size_t packet_size,
        ScDatasmashEventPacket *decoded) {
    uint16_t payload_size;
    if (packet == NULL || decoded == NULL ||
            packet_size < SC_DATASMASH_EVENT_HEADER_SIZE ||
            sc_datasmash_event_read_u32(packet) != SC_DATASMASH_EVENT_MAGIC) {
        return -1;
    }
    payload_size = sc_datasmash_event_read_u16(packet + 6);
    if (packet_size != SC_DATASMASH_EVENT_HEADER_SIZE + payload_size) {
        return -1;
    }
    decoded->type = sc_datasmash_event_read_u16(packet + 4);
    decoded->payload = packet + SC_DATASMASH_EVENT_HEADER_SIZE;
    decoded->payload_size = payload_size;
    return 0;
}

#ifdef __cplusplus
}
#endif

#endif
