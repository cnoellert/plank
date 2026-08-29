/* SPDX-License-Identifier: AGPL-3.0-or-later */

#ifndef STATIONCONNECT_DATASMASH_CONTROL_H
#define STATIONCONNECT_DATASMASH_CONTROL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ASCII "SCD1": StationConnect native data/control protocol version 1. */
#define SC_DATASMASH_CONTROL_MAGIC 0x53434431u
#define SC_DATASMASH_CONTROL_HEADER_SIZE 8u
#define SC_DATASMASH_CONTROL_MAX_PACKET_SIZE 20u

typedef enum ScDatasmashControlType {
    SC_DATASMASH_CONTROL_CLIENT_DISCONNECT = 1,
    SC_DATASMASH_CONTROL_HOST_TERMINATE = 2,
    SC_DATASMASH_CONTROL_REQUEST_IDR = 3,
    SC_DATASMASH_CONTROL_INVALIDATE_REFERENCE_FRAMES = 4,
    SC_DATASMASH_CONTROL_SET_VIDEO_BITRATE = 5,
    SC_DATASMASH_CONTROL_VIDEO_BITRATE_APPLIED = 6,
} ScDatasmashControlType;

typedef struct ScDatasmashControlPacket {
    uint16_t type;
    const uint8_t *payload;
    uint16_t payload_size;
} ScDatasmashControlPacket;

static inline void sc_datasmash_control_write_u16(uint8_t *output,
                                                   uint16_t value) {
    output[0] = (uint8_t)(value >> 8);
    output[1] = (uint8_t)value;
}

static inline void sc_datasmash_control_write_u32(uint8_t *output,
                                                   uint32_t value) {
    output[0] = (uint8_t)(value >> 24);
    output[1] = (uint8_t)(value >> 16);
    output[2] = (uint8_t)(value >> 8);
    output[3] = (uint8_t)value;
}

static inline uint16_t sc_datasmash_control_read_u16(const uint8_t *input) {
    return (uint16_t)(((uint16_t)input[0] << 8) | input[1]);
}

static inline uint32_t sc_datasmash_control_read_u32(const uint8_t *input) {
    return ((uint32_t)input[0] << 24) |
           ((uint32_t)input[1] << 16) |
           ((uint32_t)input[2] << 8) |
           (uint32_t)input[3];
}

static inline int sc_datasmash_control_encode(
        uint16_t type, const uint32_t *values, size_t value_count,
        uint8_t *output, size_t output_capacity, size_t *output_size) {
    size_t payload_size;
    size_t packet_size;
    size_t index;

    if (output == NULL || output_size == NULL ||
            value_count > 3 || (value_count != 0 && values == NULL)) {
        return -1;
    }
    payload_size = value_count * sizeof(uint32_t);
    packet_size = SC_DATASMASH_CONTROL_HEADER_SIZE + payload_size;
    if (output_capacity < packet_size) {
        return -1;
    }

    sc_datasmash_control_write_u32(output, SC_DATASMASH_CONTROL_MAGIC);
    sc_datasmash_control_write_u16(output + 4, type);
    sc_datasmash_control_write_u16(output + 6, (uint16_t)payload_size);
    for (index = 0; index < value_count; ++index) {
        sc_datasmash_control_write_u32(
                    output + SC_DATASMASH_CONTROL_HEADER_SIZE +
                        index * sizeof(uint32_t),
                    values[index]);
    }
    *output_size = packet_size;
    return 0;
}

static inline int sc_datasmash_control_decode(
        const uint8_t *packet, size_t packet_size,
        ScDatasmashControlPacket *decoded) {
    uint16_t payload_size;

    if (packet == NULL || decoded == NULL ||
            packet_size < SC_DATASMASH_CONTROL_HEADER_SIZE ||
            sc_datasmash_control_read_u32(packet) !=
                SC_DATASMASH_CONTROL_MAGIC) {
        return -1;
    }
    payload_size = sc_datasmash_control_read_u16(packet + 6);
    if (packet_size != SC_DATASMASH_CONTROL_HEADER_SIZE + payload_size) {
        return -1;
    }

    decoded->type = sc_datasmash_control_read_u16(packet + 4);
    decoded->payload = packet + SC_DATASMASH_CONTROL_HEADER_SIZE;
    decoded->payload_size = payload_size;
    return 0;
}

#ifdef __cplusplus
}
#endif

#endif
