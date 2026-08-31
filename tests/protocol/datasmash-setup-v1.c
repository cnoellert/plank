/* SPDX-License-Identifier: GPL-3.0-only */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "stationconnect_datasmash_setup.h"

#define CHECK(condition) do { if (!(condition)) abort(); } while (0)

static void check_pam_challenge_vector(void) {
    static const uint8_t payload[] = "Password:";
    static const uint8_t expected[] = {
        0x53, 0x43, 0x53, 0x31, 0x00, 0x01, 0x00, 0x04,
        0x00, 0x01, 0x00, 0x01, 0x01, 0x02, 0x03, 0x04,
        0x00, 0x00, 0x00, 0x09,
        0x50, 0x61, 0x73, 0x73, 0x77, 0x6f, 0x72, 0x64, 0x3a,
    };
    uint8_t encoded[128] = {0};
    size_t encoded_size = 0;
    ScDatasmashSetupPacket decoded;

    CHECK(sc_datasmash_setup_encode(
              SC_DATASMASH_SETUP_PAM_CHALLENGE,
              SC_DATASMASH_SETUP_FLAG_RESPONSE,
              SC_DATASMASH_SETUP_STATUS_CONTINUE, 0x01020304,
              payload, sizeof(payload) - 1,
              encoded, sizeof(encoded), &encoded_size) == 0);
    CHECK(encoded_size == sizeof(expected));
    CHECK(memcmp(encoded, expected, sizeof(expected)) == 0);
    CHECK(sc_datasmash_setup_decode(encoded, encoded_size, &decoded) == 0);
    CHECK(decoded.type == SC_DATASMASH_SETUP_PAM_CHALLENGE);
    CHECK(decoded.flags == SC_DATASMASH_SETUP_FLAG_RESPONSE);
    CHECK(decoded.status == SC_DATASMASH_SETUP_STATUS_CONTINUE);
    CHECK(decoded.request_id == 0x01020304);
    CHECK(decoded.payload_size == sizeof(payload) - 1);
    CHECK(memcmp(decoded.payload, payload, sizeof(payload) - 1) == 0);
}

static void check_empty_request(void) {
    uint8_t encoded[SC_DATASMASH_SETUP_HEADER_SIZE] = {0};
    size_t encoded_size = 0;
    ScDatasmashSetupPacket decoded;

    CHECK(sc_datasmash_setup_encode(
              SC_DATASMASH_SETUP_SERVER_INFO_REQUEST, 0,
              SC_DATASMASH_SETUP_STATUS_OK, 1, NULL, 0,
              encoded, sizeof(encoded), &encoded_size) == 0);
    CHECK(encoded_size == SC_DATASMASH_SETUP_HEADER_SIZE);
    CHECK(sc_datasmash_setup_decode(encoded, encoded_size, &decoded) == 0);
    CHECK(decoded.payload_size == 0);
}

static void check_malformed_records(void) {
    uint8_t encoded[64] = {0};
    size_t encoded_size = 0;
    ScDatasmashSetupPacket decoded;

    CHECK(sc_datasmash_setup_encode(
              SC_DATASMASH_SETUP_SERVER_INFO_REQUEST, 0,
              SC_DATASMASH_SETUP_STATUS_OK, 7, NULL, 0,
              encoded, sizeof(encoded), &encoded_size) == 0);
    CHECK(sc_datasmash_setup_decode(encoded, encoded_size - 1, &decoded) == -1);
    encoded[0] = 0;
    CHECK(sc_datasmash_setup_decode(encoded, encoded_size, &decoded) == -1);
    encoded[0] = 0x53;
    encoded[5] = 2;
    CHECK(sc_datasmash_setup_decode(encoded, encoded_size, &decoded) == -1);
    encoded[5] = 1;
    encoded[8] = 0x80;
    CHECK(sc_datasmash_setup_decode(encoded, encoded_size, &decoded) == -1);

    CHECK(sc_datasmash_setup_encode(
              0, 0, 0, 1, NULL, 0,
              encoded, sizeof(encoded), &encoded_size) == -1);
    CHECK(sc_datasmash_setup_encode(
              SC_DATASMASH_SETUP_SERVER_INFO_REQUEST, 0, 0, 0,
              NULL, 0, encoded, sizeof(encoded), &encoded_size) == -1);
}

int main(void) {
    check_pam_challenge_vector();
    check_empty_request();
    check_malformed_records();
    return 0;
}
