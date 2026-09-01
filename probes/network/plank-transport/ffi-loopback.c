/* SPDX-License-Identifier: AGPL-3.0-or-later */

#include "plank_transport.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void print_endpoint_error(const char *label,
                                 const PlankTransportEndpoint *endpoint) {
    char error[1024];
    plank_transport_endpoint_last_error(endpoint, error, sizeof(error));
    fprintf(stderr, "%s: %s\n", label, error[0] == '\0' ? "unknown error" : error);
}

static PlankTransportConfig base_config(uint32_t mode, const char *token) {
    PlankTransportConfig config;
    memset(&config, 0, sizeof(config));
    config.struct_size = sizeof(config);
    config.abi_version = PLANK_TRANSPORT_ABI_VERSION;
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
    if (plank_transport_abi_version() != PLANK_TRANSPORT_ABI_VERSION) {
        fprintf(stderr, "plank_transport ABI version mismatch\n");
        return 1;
    }

    const char *token = "plank-transport-ffi-loopback";
    PlankTransportConfig server_config =
        base_config(PLANK_TRANSPORT_MODE_SERVER, token);
    server_config.bind_address = argv[1];
    server_config.certificate_path = argv[4];
    server_config.private_key_path = argv[5];

    PlankTransportConfig client_config =
        base_config(PLANK_TRANSPORT_MODE_CLIENT, token);
    client_config.remote_address = argv[2];
    client_config.server_name = argv[3];
    client_config.certificate_sha256 = argv[6];

    PlankTransportEndpoint *server = NULL;
    PlankTransportEndpoint *client = NULL;
    int result = plank_transport_endpoint_create(&server_config, &server);
    if (result != PLANK_TRANSPORT_OK) {
        fprintf(stderr, "failed to create server endpoint: %d\n", result);
        return 1;
    }
    result = plank_transport_endpoint_create(&client_config, &client);
    if (result != PLANK_TRANSPORT_OK) {
        fprintf(stderr, "failed to create client endpoint: %d\n", result);
        plank_transport_endpoint_destroy(server);
        return 1;
    }

    result = plank_transport_endpoint_start(server);
    if (result != PLANK_TRANSPORT_OK) {
        print_endpoint_error("failed to start server endpoint", server);
        goto failure;
    }
    result = plank_transport_endpoint_start(client);
    if (result != PLANK_TRANSPORT_OK) {
        print_endpoint_error("failed to start client endpoint", client);
        goto failure;
    }
    result = plank_transport_endpoint_wait_ready(client, 7000);
    if (result != PLANK_TRANSPORT_OK) {
        print_endpoint_error("client endpoint did not become ready", client);
        goto failure;
    }
    result = plank_transport_endpoint_wait_ready(server, 7000);
    if (result != PLANK_TRANSPORT_OK) {
        print_endpoint_error("server endpoint did not become ready", server);
        goto failure;
    }
    if (plank_transport_endpoint_state(client) != PLANK_TRANSPORT_STATE_READY ||
        plank_transport_endpoint_state(server) != PLANK_TRANSPORT_STATE_READY) {
        fprintf(stderr, "endpoint state changed before teardown\n");
        goto failure;
    }

    const size_t server_max = plank_transport_video_max_packet_size(server);
    const size_t client_max = plank_transport_video_max_packet_size(client);
    const size_t server_audio_max = plank_transport_audio_max_packet_size(server);
    const size_t client_audio_max = plank_transport_audio_max_packet_size(client);
    if (server_max < 1024 || server_max != client_max ||
        server_audio_max != server_max || client_audio_max != client_max) {
        fprintf(stderr,
                "invalid negotiated media packet maximum: video=%zu/%zu "
                "audio=%zu/%zu\n",
                server_max, client_max, server_audio_max, client_audio_max);
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
    result = plank_transport_video_send(server, prefix, sizeof(prefix), payload,
                                     sizeof(payload));
    if (result != PLANK_TRANSPORT_OK) {
        fprintf(stderr, "failed to submit video packet: %d\n", result);
        goto failure;
    }
    size_t received_size = 0;
    result = plank_transport_video_receive(client, received, sizeof(received),
                                        &received_size, 2000);
    if (result != PLANK_TRANSPORT_OK || received_size != sizeof(received) ||
        memcmp(received, prefix, sizeof(prefix)) != 0 ||
        memcmp(received + sizeof(prefix), payload, sizeof(payload)) != 0) {
        fprintf(stderr, "video packet did not survive the C ABI round trip\n");
        goto failure;
    }

    unsigned char audio_header[24];
    unsigned char audio_payload[320];
    unsigned char audio_received[sizeof(audio_header) + sizeof(audio_payload)];
    for (size_t i = 0; i < sizeof(audio_header); ++i) {
        audio_header[i] = (unsigned char)(0x30u + i);
    }
    for (size_t i = 0; i < sizeof(audio_payload); ++i) {
        audio_payload[i] = (unsigned char)(0xf0u ^ i);
    }
    result = plank_transport_audio_send(server, audio_header,
                                     sizeof(audio_header), audio_payload,
                                     sizeof(audio_payload));
    if (result != PLANK_TRANSPORT_OK) {
        fprintf(stderr, "failed to submit audio packet: %d\n", result);
        goto failure;
    }
    received_size = 0;
    result = plank_transport_audio_receive(client, audio_received,
                                        sizeof(audio_received), &received_size,
                                        2000);
    if (result != PLANK_TRANSPORT_OK || received_size != sizeof(audio_received) ||
        memcmp(audio_received, audio_header, sizeof(audio_header)) != 0 ||
        memcmp(audio_received + sizeof(audio_header), audio_payload,
               sizeof(audio_payload)) != 0) {
        fprintf(stderr, "audio packet did not survive the C ABI round trip\n");
        goto failure;
    }

    unsigned char control_packet[37];
    unsigned char control_received[sizeof(control_packet)];
    for (size_t i = 0; i < sizeof(control_packet); ++i) {
        control_packet[i] = (unsigned char)(0x80u ^ i);
    }
    result = plank_transport_control_send(client, control_packet,
                                       sizeof(control_packet));
    if (result != PLANK_TRANSPORT_OK) {
        fprintf(stderr, "failed to submit reliable control packet: %d\n",
                result);
        goto failure;
    }
    received_size = 0;
    result = plank_transport_control_receive(server, control_received,
                                          sizeof(control_received),
                                          &received_size, 2000);
    if (result != PLANK_TRANSPORT_OK ||
        received_size != sizeof(control_received) ||
        memcmp(control_received, control_packet, sizeof(control_packet)) != 0) {
        fprintf(stderr,
                "reliable control packet did not survive the C ABI round trip\n");
        goto failure;
    }

    unsigned char control_reply[41];
    unsigned char control_reply_received[sizeof(control_reply)];
    for (size_t i = 0; i < sizeof(control_reply); ++i) {
        control_reply[i] = (unsigned char)(0x35u ^ i);
    }
    result = plank_transport_control_send(server, control_reply,
                                       sizeof(control_reply));
    if (result != PLANK_TRANSPORT_OK) {
        fprintf(stderr, "failed to submit reliable control reply: %d\n",
                result);
        goto failure;
    }
    received_size = 0;
    result = plank_transport_control_receive(client, control_reply_received,
                                          sizeof(control_reply_received),
                                          &received_size, 2000);
    if (result != PLANK_TRANSPORT_OK ||
        received_size != sizeof(control_reply_received) ||
        memcmp(control_reply_received, control_reply,
               sizeof(control_reply)) != 0) {
        fprintf(stderr,
                "reliable control reply did not survive the C ABI round trip\n");
        goto failure;
    }

    result = plank_transport_video_send(server, prefix, sizeof(prefix), payload,
                                     sizeof(payload));
    if (result != PLANK_TRANSPORT_OK) {
        fprintf(stderr, "failed to submit retained video packet: %d\n", result);
        goto failure;
    }
    unsigned char undersized[1];
    received_size = 0;
    result = plank_transport_video_receive(client, undersized,
                                        sizeof(undersized), &received_size,
                                        2000);
    if (result != PLANK_TRANSPORT_ERROR_BUFFER_TOO_SMALL ||
        received_size != sizeof(received)) {
        fprintf(stderr, "undersized receive did not report the packet size\n");
        goto failure;
    }
    received_size = 0;
    result = plank_transport_video_receive(client, received, sizeof(received),
                                        &received_size, 0);
    if (result != PLANK_TRANSPORT_OK || received_size != sizeof(received) ||
        memcmp(received, prefix, sizeof(prefix)) != 0 ||
        memcmp(received + sizeof(prefix), payload, sizeof(payload)) != 0) {
        fprintf(stderr, "undersized receive did not retain the video packet\n");
        goto failure;
    }

    PlankTransportStats server_stats;
    PlankTransportStats client_stats;
    memset(&server_stats, 0, sizeof(server_stats));
    memset(&client_stats, 0, sizeof(client_stats));
    server_stats.struct_size = sizeof(server_stats);
    server_stats.abi_version = PLANK_TRANSPORT_ABI_VERSION;
    client_stats.struct_size = sizeof(client_stats);
    client_stats.abi_version = PLANK_TRANSPORT_ABI_VERSION;
    if (plank_transport_endpoint_stats(server, &server_stats) != PLANK_TRANSPORT_OK ||
        plank_transport_endpoint_stats(client, &client_stats) != PLANK_TRANSPORT_OK ||
        server_stats.video_packets_sent != 2 ||
        client_stats.video_packets_received != 2 ||
        server_stats.video_bytes_sent != 2 * sizeof(received) ||
        client_stats.video_bytes_received != 2 * sizeof(received) ||
        server_stats.video_send_queue_drops != 0 ||
        client_stats.video_receive_queue_drops != 0 ||
        server_stats.audio_packets_sent != 1 ||
        client_stats.audio_packets_received != 1 ||
        server_stats.audio_bytes_sent != sizeof(audio_received) ||
        client_stats.audio_bytes_received != sizeof(audio_received) ||
        server_stats.audio_send_queue_drops != 0 ||
        client_stats.audio_receive_queue_drops != 0 ||
        client_stats.control_packets_sent != 1 ||
        client_stats.control_bytes_sent != sizeof(control_packet) ||
        server_stats.control_packets_received != 1 ||
        server_stats.control_bytes_received != sizeof(control_packet) ||
        server_stats.control_packets_sent != 1 ||
        server_stats.control_bytes_sent != sizeof(control_reply) ||
        client_stats.control_packets_received != 1 ||
        client_stats.control_bytes_received != sizeof(control_reply) ||
        client_stats.control_send_queue_full != 0 ||
        server_stats.control_receive_queue_overflow != 0 ||
        server_stats.control_send_queue_full != 0 ||
        client_stats.control_receive_queue_overflow != 0) {
        fprintf(stderr, "media transport counters are inconsistent\n");
        goto failure;
    }

    if (plank_transport_endpoint_stop(client) != PLANK_TRANSPORT_OK) {
        print_endpoint_error("failed to stop client endpoint", client);
        goto failure;
    }
    if (plank_transport_endpoint_stop(server) != PLANK_TRANSPORT_OK) {
        print_endpoint_error("failed to stop server endpoint", server);
        goto failure;
    }
    plank_transport_endpoint_destroy(client);
    plank_transport_endpoint_destroy(server);
    printf("status=complete test=plank_transport-ffi-loopback connections=2 "
           "video_packets=2 video_bytes=%zu audio_packets=1 audio_bytes=%zu "
           "control_packets_each_direction=1 control_bytes=%zu/%zu "
           "max_media_packet_size=%zu\n",
           2 * sizeof(received), sizeof(audio_received), sizeof(control_packet),
           sizeof(control_reply),
           server_max);
    return 0;

failure:
    plank_transport_endpoint_destroy(client);
    plank_transport_endpoint_destroy(server);
    return 1;
}
