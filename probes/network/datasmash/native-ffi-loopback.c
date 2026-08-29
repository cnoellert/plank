/* SPDX-License-Identifier: AGPL-3.0-or-later */

#include "stationconnect_datasmash.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static ScDatasmashConfig base_config(uint32_t mode, const char *token) {
    ScDatasmashConfig config;
    memset(&config, 0, sizeof(config));
    config.struct_size = sizeof(config);
    config.abi_version = SC_DATASMASH_ABI_VERSION;
    config.mode = mode;
    config.handshake_timeout_ms = 5000;
    config.idle_timeout_ms = 10000;
    config.keep_alive_interval_ms = 1000;
    config.session_token = token;
    return config;
}

static void print_error(const char *label,
                        const ScDatasmashNativeEndpoint *endpoint) {
    char error[1024] = {0};
    sc_datasmash_native_endpoint_last_error(endpoint, error, sizeof(error));
    fprintf(stderr, "%s: %s\n", label,
            error[0] == '\0' ? "unknown error" : error);
}

int main(int argc, char **argv) {
    if (argc != 7) {
        fprintf(stderr,
                "usage: %s <bind> <remote> <server-name> <cert> <key> <hash>\n",
                argv[0]);
        return 2;
    }

    const char *token = "stationconnect-native-ffi-loopback";
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

    ScDatasmashNativeEndpoint *server = NULL;
    ScDatasmashNativeEndpoint *client = NULL;
    if (sc_datasmash_native_endpoint_create(&server_config, &server) !=
            SC_DATASMASH_OK ||
        sc_datasmash_native_endpoint_create(&client_config, &client) !=
            SC_DATASMASH_OK ||
        sc_datasmash_native_endpoint_start(server) != SC_DATASMASH_OK ||
        sc_datasmash_native_endpoint_start(client) != SC_DATASMASH_OK) {
        fprintf(stderr, "failed to create or start native endpoints\n");
        goto failure;
    }
    if (sc_datasmash_native_endpoint_wait_ready(client, 7000) !=
            SC_DATASMASH_OK ||
        sc_datasmash_native_endpoint_wait_ready(server, 7000) !=
            SC_DATASMASH_OK) {
        print_error("native client", client);
        ScDatasmashNativeStats failed_server_stats;
        ScDatasmashNativeStats failed_client_stats;
        memset(&failed_server_stats, 0, sizeof(failed_server_stats));
        memset(&failed_client_stats, 0, sizeof(failed_client_stats));
        failed_server_stats.struct_size = sizeof(failed_server_stats);
        failed_client_stats.struct_size = sizeof(failed_client_stats);
        if (sc_datasmash_native_endpoint_stats(server, &failed_server_stats) ==
                SC_DATASMASH_OK &&
            sc_datasmash_native_endpoint_stats(client, &failed_client_stats) ==
                SC_DATASMASH_OK) {
            fprintf(stderr,
                    "native video failure stats: sent=%llu received=%llu "
                    "server_quic_lost=%llu client_quic_lost=%llu "
                    "server_kyproto_drops=%llu client_kyproto_drops=%llu\n",
                    (unsigned long long)failed_server_stats.video_frames_sent,
                    (unsigned long long)failed_client_stats.video_frames_received,
                    (unsigned long long)failed_server_stats.quic_packets_lost,
                    (unsigned long long)failed_client_stats.quic_packets_lost,
                    (unsigned long long)failed_server_stats.kyproto_packets_dropped,
                    (unsigned long long)failed_client_stats.kyproto_packets_dropped);
        }
        print_error("native server", server);
        goto failure;
    }

    const size_t video_size = 192 * 1024;
    unsigned char *video = malloc(video_size);
    unsigned char *video_received = malloc(video_size);
    if (video == NULL || video_received == NULL) {
        fprintf(stderr, "failed to allocate video test buffers\n");
        free(video);
        free(video_received);
        goto failure;
    }
    for (size_t i = 0; i < video_size; ++i) {
        video[i] = (unsigned char)((i * 37u + 11u) & 0xffu);
    }
    ScDatasmashNativeVideoFrameInfo video_info;
    memset(&video_info, 0, sizeof(video_info));
    video_info.struct_size = sizeof(video_info);
    video_info.codec = SC_DATASMASH_NATIVE_VIDEO_CODEC_HEVC;
    video_info.flags = SC_DATASMASH_NATIVE_VIDEO_FLAG_KEY;
    video_info.frame_number = 42;
    video_info.pts = 90000;
    video_info.host_processing_latency = 17;
    if (sc_datasmash_native_video_send(server, &video_info, video,
                                       video_size) != SC_DATASMASH_OK) {
        fprintf(stderr, "failed to submit native video frame\n");
        free(video);
        free(video_received);
        goto failure;
    }
    ScDatasmashNativeVideoFrameInfo received_video_info;
    memset(&received_video_info, 0, sizeof(received_video_info));
    received_video_info.struct_size = sizeof(received_video_info);
    size_t received_size = 0;
    int video_receive_result = sc_datasmash_native_video_receive(
            client, &received_video_info, video_received, video_size,
            &received_size, 5000);
    if (video_receive_result != SC_DATASMASH_OK ||
        received_size != video_size ||
        memcmp(video, video_received, video_size) != 0 ||
        received_video_info.codec != video_info.codec ||
        received_video_info.flags != video_info.flags ||
        received_video_info.frame_number != video_info.frame_number ||
        received_video_info.pts != video_info.pts ||
        received_video_info.host_processing_latency !=
            video_info.host_processing_latency) {
        fprintf(stderr,
                "native video mismatch: result=%d size=%zu/%zu bytes_equal=%d "
                "codec=%08x/%08x flags=%08x/%08x frame=%llu/%llu "
                "pts=%llu/%llu latency=%u/%u\n",
                video_receive_result, received_size, video_size,
                received_size == video_size &&
                    memcmp(video, video_received, video_size) == 0,
                received_video_info.codec, video_info.codec,
                received_video_info.flags, video_info.flags,
                (unsigned long long)received_video_info.frame_number,
                (unsigned long long)video_info.frame_number,
                (unsigned long long)received_video_info.pts,
                (unsigned long long)video_info.pts,
                received_video_info.host_processing_latency,
                video_info.host_processing_latency);
        print_error("native client", client);
        ScDatasmashNativeStats video_server_stats;
        ScDatasmashNativeStats video_client_stats;
        memset(&video_server_stats, 0, sizeof(video_server_stats));
        memset(&video_client_stats, 0, sizeof(video_client_stats));
        video_server_stats.struct_size = sizeof(video_server_stats);
        video_client_stats.struct_size = sizeof(video_client_stats);
        if (sc_datasmash_native_endpoint_stats(server, &video_server_stats) ==
                SC_DATASMASH_OK &&
            sc_datasmash_native_endpoint_stats(client, &video_client_stats) ==
                SC_DATASMASH_OK) {
            fprintf(stderr,
                    "native video counters: sent=%llu received=%llu "
                    "server_quic_lost=%llu client_quic_lost=%llu "
                    "server_kyproto_drops=%llu client_kyproto_drops=%llu\n",
                    (unsigned long long)video_server_stats.video_frames_sent,
                    (unsigned long long)video_client_stats.video_frames_received,
                    (unsigned long long)video_server_stats.quic_packets_lost,
                    (unsigned long long)video_client_stats.quic_packets_lost,
                    (unsigned long long)video_server_stats.kyproto_packets_dropped,
                    (unsigned long long)video_client_stats.kyproto_packets_dropped);
        }
        free(video);
        free(video_received);
        goto failure;
    }
    free(video);
    free(video_received);

    const unsigned char audio[] = "raw-opus-packet";
    unsigned char audio_received[sizeof(audio)];
    ScDatasmashNativeAudioPacketInfo audio_info;
    memset(&audio_info, 0, sizeof(audio_info));
    audio_info.struct_size = sizeof(audio_info);
    audio_info.frame_samples = 240;
    audio_info.pts = 240;
    if (sc_datasmash_native_audio_send(server, &audio_info, audio,
                                       sizeof(audio)) != SC_DATASMASH_OK) {
        fprintf(stderr, "failed to submit native audio packet\n");
        goto failure;
    }
    ScDatasmashNativeAudioPacketInfo received_audio_info;
    memset(&received_audio_info, 0, sizeof(received_audio_info));
    received_audio_info.struct_size = sizeof(received_audio_info);
    received_size = 0;
    if (sc_datasmash_native_audio_receive(
            client, &received_audio_info, audio_received,
            sizeof(audio_received), &received_size, 5000) != SC_DATASMASH_OK ||
        received_size != sizeof(audio) ||
        memcmp(audio, audio_received, sizeof(audio)) != 0 ||
        received_audio_info.frame_samples != audio_info.frame_samples ||
        received_audio_info.pts != audio_info.pts) {
        fprintf(stderr, "native audio packet or metadata mismatch\n");
        goto failure;
    }

    const unsigned char input[] = "wacom-tip-transition";
    unsigned char input_received[sizeof(input)];
    uint8_t input_type = 0;
    if (sc_datasmash_native_input_send(client, 7, input, sizeof(input)) !=
            SC_DATASMASH_OK) {
        fprintf(stderr, "failed to submit native input packet\n");
        goto failure;
    }
    received_size = 0;
    if (sc_datasmash_native_input_receive(
            server, &input_type, input_received, sizeof(input_received),
            &received_size, 5000) != SC_DATASMASH_OK ||
        input_type != 7 || received_size != sizeof(input) ||
        memcmp(input, input_received, sizeof(input)) != 0) {
        fprintf(stderr, "native input packet mismatch\n");
        goto failure;
    }

    const unsigned char client_data[] = "client-control";
    const unsigned char server_data[] = "server-control";
    unsigned char data_received[32];
    if (sc_datasmash_native_data_send(client, client_data,
                                      sizeof(client_data)) != SC_DATASMASH_OK) {
        fprintf(stderr, "failed to submit client native data\n");
        goto failure;
    }
    received_size = 0;
    if (sc_datasmash_native_data_receive(
            server, data_received, sizeof(data_received), &received_size,
            5000) != SC_DATASMASH_OK ||
        received_size != sizeof(client_data) ||
        memcmp(client_data, data_received, sizeof(client_data)) != 0) {
        fprintf(stderr, "client native data mismatch\n");
        goto failure;
    }
    if (sc_datasmash_native_data_send(server, server_data,
                                      sizeof(server_data)) != SC_DATASMASH_OK) {
        fprintf(stderr, "failed to submit server native data\n");
        goto failure;
    }
    received_size = 0;
    if (sc_datasmash_native_data_receive(
            client, data_received, sizeof(data_received), &received_size,
            5000) != SC_DATASMASH_OK ||
        received_size != sizeof(server_data) ||
        memcmp(server_data, data_received, sizeof(server_data)) != 0) {
        fprintf(stderr, "server native data mismatch\n");
        goto failure;
    }

    ScDatasmashNativeStats server_stats;
    ScDatasmashNativeStats client_stats;
    memset(&server_stats, 0, sizeof(server_stats));
    memset(&client_stats, 0, sizeof(client_stats));
    server_stats.struct_size = sizeof(server_stats);
    client_stats.struct_size = sizeof(client_stats);
    if (sc_datasmash_native_endpoint_stats(server, &server_stats) !=
            SC_DATASMASH_OK ||
        sc_datasmash_native_endpoint_stats(client, &client_stats) !=
            SC_DATASMASH_OK ||
        server_stats.video_frames_sent != 1 ||
        client_stats.video_frames_received != 1 ||
        server_stats.video_bytes_sent != video_size ||
        client_stats.video_bytes_received != video_size ||
        server_stats.audio_packets_sent != 1 ||
        client_stats.audio_packets_received != 1 ||
        client_stats.input_packets_sent != 1 ||
        server_stats.input_packets_received != 1 ||
        server_stats.data_packets_sent != 1 ||
        server_stats.data_packets_received != 1 ||
        client_stats.data_packets_sent != 1 ||
        client_stats.data_packets_received != 1 ||
        server_stats.video_send_drops != 0 ||
        client_stats.video_receive_drops != 0 ||
        server_stats.audio_send_drops != 0 ||
        client_stats.audio_receive_drops != 0 ||
        client_stats.kyproto_packets_dropped != 0) {
        fprintf(stderr, "native transport counters mismatch\n");
        goto failure;
    }

    sc_datasmash_native_endpoint_stop(client);
    sc_datasmash_native_endpoint_stop(server);
    sc_datasmash_native_endpoint_destroy(client);
    sc_datasmash_native_endpoint_destroy(server);
    printf("status=complete test=native-kyproto-ffi-loopback "
           "video_frames=1 video_bytes=%zu audio_packets=1 input_packets=1 "
           "data_packets_each_direction=1\n", video_size);
    return 0;

failure:
    sc_datasmash_native_endpoint_destroy(client);
    sc_datasmash_native_endpoint_destroy(server);
    return 1;
}
