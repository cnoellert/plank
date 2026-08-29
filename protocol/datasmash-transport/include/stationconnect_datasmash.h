/* SPDX-License-Identifier: AGPL-3.0-or-later */

#ifndef STATIONCONNECT_DATASMASH_H
#define STATIONCONNECT_DATASMASH_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SC_DATASMASH_ABI_VERSION 1u

typedef struct ScDatasmashEndpoint ScDatasmashEndpoint;

typedef enum ScDatasmashMode {
    SC_DATASMASH_MODE_SERVER = 1,
    SC_DATASMASH_MODE_CLIENT = 2,
} ScDatasmashMode;

typedef enum ScDatasmashState {
    SC_DATASMASH_STATE_INVALID = 0,
    SC_DATASMASH_STATE_IDLE = 1,
    SC_DATASMASH_STATE_STARTING = 2,
    SC_DATASMASH_STATE_READY = 3,
    SC_DATASMASH_STATE_STOPPING = 4,
    SC_DATASMASH_STATE_STOPPED = 5,
    SC_DATASMASH_STATE_FAILED = 6,
} ScDatasmashState;

typedef enum ScDatasmashResult {
    SC_DATASMASH_OK = 0,
    SC_DATASMASH_TIMEOUT = 1,
    SC_DATASMASH_ERROR_INVALID_ARGUMENT = -1,
    SC_DATASMASH_ERROR_INVALID_STATE = -2,
    SC_DATASMASH_ERROR_RUNTIME = -3,
    SC_DATASMASH_ERROR_PANIC = -4,
} ScDatasmashResult;

/*
 * Strings are copied during sc_datasmash_endpoint_create() and need only
 * remain valid for that call. Server mode requires bind_address,
 * certificate_path, private_key_path, and session_token. Client mode requires
 * remote_address, server_name, certificate_sha256, and session_token.
 */
typedef struct ScDatasmashConfig {
    uint32_t struct_size;
    uint32_t abi_version;
    uint32_t mode;
    uint32_t handshake_timeout_ms;
    uint32_t idle_timeout_ms;
    uint32_t keep_alive_interval_ms;
    const char *bind_address;
    const char *remote_address;
    const char *server_name;
    const char *certificate_path;
    const char *private_key_path;
    const char *certificate_sha256;
    const char *session_token;
} ScDatasmashConfig;

uint32_t sc_datasmash_abi_version(void);

int32_t sc_datasmash_endpoint_create(const ScDatasmashConfig *config,
                                     ScDatasmashEndpoint **endpoint_out);
int32_t sc_datasmash_endpoint_start(ScDatasmashEndpoint *endpoint);
int32_t sc_datasmash_endpoint_wait_ready(ScDatasmashEndpoint *endpoint,
                                         uint32_t timeout_ms);
uint32_t sc_datasmash_endpoint_state(const ScDatasmashEndpoint *endpoint);
int32_t sc_datasmash_endpoint_stop(ScDatasmashEndpoint *endpoint);
void sc_datasmash_endpoint_destroy(ScDatasmashEndpoint *endpoint);

/*
 * Returns the required byte count including the trailing NUL. If buffer is
 * non-NULL and buffer_size is nonzero, the result is always NUL-terminated.
 */
size_t sc_datasmash_endpoint_last_error(const ScDatasmashEndpoint *endpoint,
                                        char *buffer,
                                        size_t buffer_size);

#ifdef __cplusplus
}
#endif

#endif
