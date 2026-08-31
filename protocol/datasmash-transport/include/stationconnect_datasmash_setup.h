/* SPDX-License-Identifier: AGPL-3.0-or-later */

#ifndef STATIONCONNECT_DATASMASH_SETUP_H
#define STATIONCONNECT_DATASMASH_SETUP_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ASCII "SCS1": StationConnect pre-session setup protocol version 1. */
#define SC_DATASMASH_SETUP_MAGIC 0x53435331u
#define SC_DATASMASH_SETUP_VERSION 1u
#define SC_DATASMASH_SETUP_HEADER_SIZE 20u
#define SC_DATASMASH_SETUP_MAX_PACKET_SIZE 65536u
#define SC_DATASMASH_SETUP_MAX_PAYLOAD_SIZE \
    (SC_DATASMASH_SETUP_MAX_PACKET_SIZE - SC_DATASMASH_SETUP_HEADER_SIZE)

typedef enum ScDatasmashSetupType {
    SC_DATASMASH_SETUP_SERVER_INFO_REQUEST = 1,
    SC_DATASMASH_SETUP_SERVER_INFO_RESPONSE = 2,
    SC_DATASMASH_SETUP_PAM_START = 3,
    SC_DATASMASH_SETUP_PAM_CHALLENGE = 4,
    SC_DATASMASH_SETUP_PAM_RESPOND = 5,
    SC_DATASMASH_SETUP_PAM_RESULT = 6,
    SC_DATASMASH_SETUP_TOPOLOGY_REQUEST = 7,
    SC_DATASMASH_SETUP_TOPOLOGY_RESPONSE = 8,
    SC_DATASMASH_SETUP_LAUNCH_REQUEST = 9,
    SC_DATASMASH_SETUP_LAUNCH_RESPONSE = 10,
    SC_DATASMASH_SETUP_SESSION_READY = 11,
    SC_DATASMASH_SETUP_ERROR = 12,
} ScDatasmashSetupType;

typedef enum ScDatasmashSetupFlags {
    SC_DATASMASH_SETUP_FLAG_RESPONSE = 0x0001u,
    SC_DATASMASH_SETUP_FLAG_SENSITIVE = 0x0002u,
} ScDatasmashSetupFlags;

typedef enum ScDatasmashSetupStatus {
    SC_DATASMASH_SETUP_STATUS_OK = 0,
    SC_DATASMASH_SETUP_STATUS_CONTINUE = 1,
    SC_DATASMASH_SETUP_STATUS_INVALID_REQUEST = 2,
    SC_DATASMASH_SETUP_STATUS_AUTHENTICATION_FAILED = 3,
    SC_DATASMASH_SETUP_STATUS_AUTHORIZATION_FAILED = 4,
    SC_DATASMASH_SETUP_STATUS_BUSY = 5,
    SC_DATASMASH_SETUP_STATUS_UNSUPPORTED = 6,
    SC_DATASMASH_SETUP_STATUS_INTERNAL_ERROR = 7,
} ScDatasmashSetupStatus;

typedef struct ScDatasmashSetupPacket {
    uint16_t type;
    uint16_t flags;
    uint16_t status;
    uint32_t request_id;
    const uint8_t *payload;
    uint32_t payload_size;
} ScDatasmashSetupPacket;

static inline void sc_datasmash_setup_write_u16(uint8_t *output,
                                                 uint16_t value) {
    output[0] = (uint8_t)(value >> 8);
    output[1] = (uint8_t)value;
}

static inline void sc_datasmash_setup_write_u32(uint8_t *output,
                                                 uint32_t value) {
    output[0] = (uint8_t)(value >> 24);
    output[1] = (uint8_t)(value >> 16);
    output[2] = (uint8_t)(value >> 8);
    output[3] = (uint8_t)value;
}

static inline uint16_t sc_datasmash_setup_read_u16(const uint8_t *input) {
    return (uint16_t)(((uint16_t)input[0] << 8) | input[1]);
}

static inline uint32_t sc_datasmash_setup_read_u32(const uint8_t *input) {
    return ((uint32_t)input[0] << 24) |
           ((uint32_t)input[1] << 16) |
           ((uint32_t)input[2] << 8) |
           (uint32_t)input[3];
}

static inline int sc_datasmash_setup_encode(
        uint16_t type, uint16_t flags, uint16_t status, uint32_t request_id,
        const uint8_t *payload, size_t payload_size,
        uint8_t *output, size_t output_capacity, size_t *output_size) {
    const size_t packet_size = SC_DATASMASH_SETUP_HEADER_SIZE + payload_size;

    if (type == 0 || request_id == 0 || output == NULL || output_size == NULL ||
            (flags & ~(SC_DATASMASH_SETUP_FLAG_RESPONSE |
                       SC_DATASMASH_SETUP_FLAG_SENSITIVE)) != 0 ||
            (payload_size != 0 && payload == NULL) ||
            payload_size > SC_DATASMASH_SETUP_MAX_PAYLOAD_SIZE ||
            output_capacity < packet_size) {
        return -1;
    }

    sc_datasmash_setup_write_u32(output, SC_DATASMASH_SETUP_MAGIC);
    sc_datasmash_setup_write_u16(output + 4, SC_DATASMASH_SETUP_VERSION);
    sc_datasmash_setup_write_u16(output + 6, type);
    sc_datasmash_setup_write_u16(output + 8, flags);
    sc_datasmash_setup_write_u16(output + 10, status);
    sc_datasmash_setup_write_u32(output + 12, request_id);
    sc_datasmash_setup_write_u32(output + 16, (uint32_t)payload_size);
    if (payload_size != 0) {
        memcpy(output + SC_DATASMASH_SETUP_HEADER_SIZE, payload, payload_size);
    }
    *output_size = packet_size;
    return 0;
}

static inline int sc_datasmash_setup_decode(
        const uint8_t *packet, size_t packet_size,
        ScDatasmashSetupPacket *decoded) {
    uint16_t flags;
    uint32_t payload_size;

    if (packet == NULL || decoded == NULL ||
            packet_size < SC_DATASMASH_SETUP_HEADER_SIZE ||
            packet_size > SC_DATASMASH_SETUP_MAX_PACKET_SIZE ||
            sc_datasmash_setup_read_u32(packet) != SC_DATASMASH_SETUP_MAGIC ||
            sc_datasmash_setup_read_u16(packet + 4) !=
                SC_DATASMASH_SETUP_VERSION ||
            sc_datasmash_setup_read_u16(packet + 6) == 0 ||
            sc_datasmash_setup_read_u32(packet + 12) == 0) {
        return -1;
    }

    flags = sc_datasmash_setup_read_u16(packet + 8);
    if ((flags & ~(SC_DATASMASH_SETUP_FLAG_RESPONSE |
                   SC_DATASMASH_SETUP_FLAG_SENSITIVE)) != 0) {
        return -1;
    }
    payload_size = sc_datasmash_setup_read_u32(packet + 16);
    if (payload_size > SC_DATASMASH_SETUP_MAX_PAYLOAD_SIZE ||
            packet_size != SC_DATASMASH_SETUP_HEADER_SIZE + payload_size) {
        return -1;
    }

    decoded->type = sc_datasmash_setup_read_u16(packet + 6);
    decoded->flags = flags;
    decoded->status = sc_datasmash_setup_read_u16(packet + 10);
    decoded->request_id = sc_datasmash_setup_read_u32(packet + 12);
    decoded->payload = packet + SC_DATASMASH_SETUP_HEADER_SIZE;
    decoded->payload_size = payload_size;
    return 0;
}

#ifdef __cplusplus
}
#endif

#endif
