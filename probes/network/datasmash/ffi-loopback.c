/* SPDX-License-Identifier: AGPL-3.0-or-later */

#include "stationconnect_datasmash.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void print_endpoint_error(const char *label,
                                 const ScDatasmashEndpoint *endpoint) {
    char error[1024];
    sc_datasmash_endpoint_last_error(endpoint, error, sizeof(error));
    fprintf(stderr, "%s: %s\n", label, error[0] == '\0' ? "unknown error" : error);
}

static ScDatasmashConfig base_config(uint32_t mode, const char *token) {
    ScDatasmashConfig config;
    memset(&config, 0, sizeof(config));
    config.struct_size = sizeof(config);
    config.abi_version = SC_DATASMASH_ABI_VERSION;
    config.mode = mode;
    config.handshake_timeout_ms = 5000;
    config.idle_timeout_ms = 10000;
    config.keep_alive_interval_ms = 2000;
    config.session_token = token;
    return config;
}

int main(int argc, char **argv) {
    if (argc != 7) {
        fprintf(stderr,
                "usage: %s <bind> <remote> <server-name> <cert.pem> <key.pem> "
                "<cert-sha256>\n",
                argv[0]);
        return 2;
    }
    if (sc_datasmash_abi_version() != SC_DATASMASH_ABI_VERSION) {
        fprintf(stderr, "datasmash ABI version mismatch\n");
        return 1;
    }

    const char *token = "stationconnect-datasmash-ffi-loopback";
    ScDatasmashConfig server_config =
        base_config(SC_DATASMASH_MODE_SERVER, token);
    server_config.bind_address = argv[1];
    server_config.certificate_path = argv[4];
    server_config.private_key_path = argv[5];

    ScDatasmashConfig client_config =
        base_config(SC_DATASMASH_MODE_CLIENT, token);
    client_config.remote_address = argv[2];
    client_config.server_name = argv[3];
    client_config.certificate_sha256 = argv[6];

    ScDatasmashEndpoint *server = NULL;
    ScDatasmashEndpoint *client = NULL;
    int result = sc_datasmash_endpoint_create(&server_config, &server);
    if (result != SC_DATASMASH_OK) {
        fprintf(stderr, "failed to create server endpoint: %d\n", result);
        return 1;
    }
    result = sc_datasmash_endpoint_create(&client_config, &client);
    if (result != SC_DATASMASH_OK) {
        fprintf(stderr, "failed to create client endpoint: %d\n", result);
        sc_datasmash_endpoint_destroy(server);
        return 1;
    }

    result = sc_datasmash_endpoint_start(server);
    if (result != SC_DATASMASH_OK) {
        print_endpoint_error("failed to start server endpoint", server);
        goto failure;
    }
    result = sc_datasmash_endpoint_start(client);
    if (result != SC_DATASMASH_OK) {
        print_endpoint_error("failed to start client endpoint", client);
        goto failure;
    }
    result = sc_datasmash_endpoint_wait_ready(client, 7000);
    if (result != SC_DATASMASH_OK) {
        print_endpoint_error("client endpoint did not become ready", client);
        goto failure;
    }
    result = sc_datasmash_endpoint_wait_ready(server, 7000);
    if (result != SC_DATASMASH_OK) {
        print_endpoint_error("server endpoint did not become ready", server);
        goto failure;
    }
    if (sc_datasmash_endpoint_state(client) != SC_DATASMASH_STATE_READY ||
        sc_datasmash_endpoint_state(server) != SC_DATASMASH_STATE_READY) {
        fprintf(stderr, "endpoint state changed before teardown\n");
        goto failure;
    }

    if (sc_datasmash_endpoint_stop(client) != SC_DATASMASH_OK) {
        print_endpoint_error("failed to stop client endpoint", client);
        goto failure;
    }
    if (sc_datasmash_endpoint_stop(server) != SC_DATASMASH_OK) {
        print_endpoint_error("failed to stop server endpoint", server);
        goto failure;
    }
    sc_datasmash_endpoint_destroy(client);
    sc_datasmash_endpoint_destroy(server);
    puts("status=complete test=datasmash-ffi-loopback connections=2");
    return 0;

failure:
    sc_datasmash_endpoint_destroy(client);
    sc_datasmash_endpoint_destroy(server);
    return 1;
}
