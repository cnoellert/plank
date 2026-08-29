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

    const size_t server_max = sc_datasmash_video_max_packet_size(server);
    const size_t client_max = sc_datasmash_video_max_packet_size(client);
    if (server_max < 1024 || server_max != client_max) {
        fprintf(stderr,
                "invalid negotiated video packet maximum: server=%zu client=%zu\n",
                server_max, client_max);
        goto failure;
    }

    unsigned char prefix[32];
    unsigned char payload[768];
    unsigned char received[sizeof(prefix) + sizeof(payload)];
    for (size_t i = 0; i < sizeof(prefix); ++i) {
        prefix[i] = (unsigned char)(0xa0u + i);
    }
    for (size_t i = 0; i < sizeof(payload); ++i) {
        payload[i] = (unsigned char)(i ^ 0x5au);
    }
    result = sc_datasmash_video_send(server, prefix, sizeof(prefix), payload,
                                     sizeof(payload));
    if (result != SC_DATASMASH_OK) {
        fprintf(stderr, "failed to submit video packet: %d\n", result);
        goto failure;
    }
    size_t received_size = 0;
    result = sc_datasmash_video_receive(client, received, sizeof(received),
                                        &received_size, 2000);
    if (result != SC_DATASMASH_OK || received_size != sizeof(received) ||
        memcmp(received, prefix, sizeof(prefix)) != 0 ||
        memcmp(received + sizeof(prefix), payload, sizeof(payload)) != 0) {
        fprintf(stderr, "video packet did not survive the C ABI round trip\n");
        goto failure;
    }

    result = sc_datasmash_video_send(server, prefix, sizeof(prefix), payload,
                                     sizeof(payload));
    if (result != SC_DATASMASH_OK) {
        fprintf(stderr, "failed to submit retained video packet: %d\n", result);
        goto failure;
    }
    unsigned char undersized[1];
    received_size = 0;
    result = sc_datasmash_video_receive(client, undersized,
                                        sizeof(undersized), &received_size,
                                        2000);
    if (result != SC_DATASMASH_ERROR_BUFFER_TOO_SMALL ||
        received_size != sizeof(received)) {
        fprintf(stderr, "undersized receive did not report the packet size\n");
        goto failure;
    }
    received_size = 0;
    result = sc_datasmash_video_receive(client, received, sizeof(received),
                                        &received_size, 0);
    if (result != SC_DATASMASH_OK || received_size != sizeof(received) ||
        memcmp(received, prefix, sizeof(prefix)) != 0 ||
        memcmp(received + sizeof(prefix), payload, sizeof(payload)) != 0) {
        fprintf(stderr, "undersized receive did not retain the video packet\n");
        goto failure;
    }

    ScDatasmashStats server_stats;
    ScDatasmashStats client_stats;
    memset(&server_stats, 0, sizeof(server_stats));
    memset(&client_stats, 0, sizeof(client_stats));
    server_stats.struct_size = sizeof(server_stats);
    server_stats.abi_version = SC_DATASMASH_ABI_VERSION;
    client_stats.struct_size = sizeof(client_stats);
    client_stats.abi_version = SC_DATASMASH_ABI_VERSION;
    if (sc_datasmash_endpoint_stats(server, &server_stats) != SC_DATASMASH_OK ||
        sc_datasmash_endpoint_stats(client, &client_stats) != SC_DATASMASH_OK ||
        server_stats.video_packets_sent != 2 ||
        client_stats.video_packets_received != 2 ||
        server_stats.video_bytes_sent != 2 * sizeof(received) ||
        client_stats.video_bytes_received != 2 * sizeof(received) ||
        server_stats.video_send_queue_drops != 0 ||
        client_stats.video_receive_queue_drops != 0) {
        fprintf(stderr, "video transport counters are inconsistent\n");
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
    printf("status=complete test=datasmash-ffi-loopback connections=2 "
           "video_packets=2 video_bytes=%zu max_video_packet_size=%zu\n",
           2 * sizeof(received), server_max);
    return 0;

failure:
    sc_datasmash_endpoint_destroy(client);
    sc_datasmash_endpoint_destroy(server);
    return 1;
}
