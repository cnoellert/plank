/* SPDX-License-Identifier: AGPL-3.0-or-later */

#ifndef STATIONCONNECT_DATASMASH_H
#define STATIONCONNECT_DATASMASH_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SC_DATASMASH_ABI_VERSION 11u

typedef struct ScDatasmashEndpoint ScDatasmashEndpoint;
typedef struct ScDatasmashNativeEndpoint ScDatasmashNativeEndpoint;

typedef enum ScDatasmashMode {
    SC_DATASMASH_MODE_SERVER = 1,
    SC_DATASMASH_MODE_CLIENT = 2,
} ScDatasmashMode;

typedef enum ScDatasmashSessionMode {
    SC_DATASMASH_SESSION_ACTIVE = 0,
    SC_DATASMASH_SESSION_SETUP = 1,
} ScDatasmashSessionMode;

typedef enum ScDatasmashState {
    SC_DATASMASH_STATE_INVALID = 0,
    SC_DATASMASH_STATE_IDLE = 1,
    SC_DATASMASH_STATE_STARTING = 2,
    SC_DATASMASH_STATE_PEER_VALIDATION = 3,
    SC_DATASMASH_STATE_SETUP_READY = 4,
    SC_DATASMASH_STATE_READY = 5,
    SC_DATASMASH_STATE_STOPPING = 6,
    SC_DATASMASH_STATE_STOPPED = 7,
    SC_DATASMASH_STATE_FAILED = 8,
} ScDatasmashState;

typedef enum ScDatasmashResult {
    SC_DATASMASH_OK = 0,
    SC_DATASMASH_TIMEOUT = 1,
    SC_DATASMASH_DROPPED = 2,
    SC_DATASMASH_ERROR_INVALID_ARGUMENT = -1,
    SC_DATASMASH_ERROR_INVALID_STATE = -2,
    SC_DATASMASH_ERROR_RUNTIME = -3,
    SC_DATASMASH_ERROR_PANIC = -4,
    SC_DATASMASH_ERROR_BUFFER_TOO_SMALL = -5,
} ScDatasmashResult;

typedef struct ScDatasmashStats {
    uint32_t struct_size;
    uint32_t abi_version;
    uint64_t video_packets_sent;
    uint64_t video_bytes_sent;
    uint64_t video_packets_received;
    uint64_t video_bytes_received;
    uint64_t video_send_queue_drops;
    uint64_t video_receive_queue_drops;
    uint64_t video_transport_send_drops;
    uint64_t malformed_datagrams;
    uint64_t video_send_queue_high_water;
    uint64_t video_receive_queue_high_water;
    uint64_t audio_packets_sent;
    uint64_t audio_bytes_sent;
    uint64_t audio_packets_received;
    uint64_t audio_bytes_received;
    uint64_t audio_send_queue_drops;
    uint64_t audio_receive_queue_drops;
    uint64_t audio_transport_send_drops;
    uint64_t audio_send_queue_high_water;
    uint64_t audio_receive_queue_high_water;
    uint64_t media_quic_rtt_us;
    uint64_t media_quic_packets_lost;
    uint64_t control_packets_sent;
    uint64_t control_bytes_sent;
    uint64_t control_packets_received;
    uint64_t control_bytes_received;
    uint64_t control_send_queue_full;
    uint64_t control_receive_queue_overflow;
    uint64_t control_send_queue_high_water;
    uint64_t control_receive_queue_high_water;
    uint64_t interaction_quic_rtt_us;
    uint64_t interaction_quic_packets_lost;
} ScDatasmashStats;

/*
 * Strings are copied during sc_datasmash_endpoint_create() and need only
 * remain valid for that call. Server mode requires bind_address,
 * certificate_path, private_key_path, and session_token. Client mode requires
 * remote_address, server_name, and session_token. A non-NULL
 * certificate_sha256 selects exact-fingerprint validation. NULL selects the
 * explicit StationConnect certificate-profile validation workflow documented
 * with sc_datasmash_native_endpoint_peer_certificate().
 */
typedef struct ScDatasmashConfig {
    uint32_t struct_size;
    uint32_t abi_version;
    uint32_t mode;
    uint32_t handshake_timeout_ms;
    uint32_t idle_timeout_ms;
    uint32_t keep_alive_interval_ms;
    uint32_t session_mode;
    /*
     * Maximum complete QUIC UDP payload, excluding outer IP/UDP headers.
     * Zero retains Quinn's default path policy. A nonzero value also limits
     * the peer through QUIC's max_udp_payload_size transport parameter.
     */
    uint32_t max_udp_payload_size;
    /*
     * Initial server-side video encoder target in kilobits per second. This
     * drives the FEC-inclusive native transport budget. Zero is valid for a
     * receive-only client endpoint.
     */
    uint32_t initial_video_bitrate_kbps;
    const char *bind_address;
    const char *remote_address;
    const char *server_name;
    const char *certificate_path;
    const char *private_key_path;
    const char *certificate_sha256;
    const char *session_token;
} ScDatasmashConfig;

#define SC_DATASMASH_NATIVE_VIDEO_CODEC_H264 0x48323634u
#define SC_DATASMASH_NATIVE_VIDEO_CODEC_HEVC 0x48455643u
#define SC_DATASMASH_NATIVE_VIDEO_FLAG_KEY 0x00000001u

typedef struct ScDatasmashNativeVideoFrameInfo {
    uint32_t struct_size;
    uint32_t codec;
    uint32_t flags;
    uint32_t reserved;
    uint64_t frame_number;
    uint64_t pts;
    uint16_t host_processing_latency;
    uint8_t reserved2[6];
} ScDatasmashNativeVideoFrameInfo;

typedef struct ScDatasmashNativeAudioPacketInfo {
    uint32_t struct_size;
    uint16_t frame_samples;
    uint16_t reserved;
    uint32_t missing_samples;
    uint32_t reserved2;
    uint64_t pts;
} ScDatasmashNativeAudioPacketInfo;

typedef struct ScDatasmashNativeStats {
    uint32_t struct_size;
    uint64_t video_frames_sent;
    uint64_t video_bytes_sent;
    uint64_t video_frames_received;
    uint64_t video_bytes_received;
    uint64_t video_send_drops;
    uint64_t video_receive_drops;
    uint64_t audio_packets_sent;
    uint64_t audio_bytes_sent;
    uint64_t audio_packets_received;
    uint64_t audio_bytes_received;
    uint64_t audio_send_drops;
    uint64_t audio_receive_drops;
    uint64_t input_packets_sent;
    uint64_t input_packets_received;
    uint64_t data_packets_sent;
    uint64_t data_packets_received;
    uint64_t quic_rtt_us;
    uint64_t quic_packets_lost;
    uint64_t kyproto_packets_dropped;
    uint64_t video_fec_source_symbols;
    uint64_t video_fec_source_symbols_missing;
} ScDatasmashNativeStats;

uint32_t sc_datasmash_abi_version(void);

int32_t sc_datasmash_endpoint_create(const ScDatasmashConfig *config,
                                     ScDatasmashEndpoint **endpoint_out);
int32_t sc_datasmash_endpoint_start(ScDatasmashEndpoint *endpoint);
int32_t sc_datasmash_endpoint_wait_ready(ScDatasmashEndpoint *endpoint,
                                         uint32_t timeout_ms);
uint32_t sc_datasmash_endpoint_state(const ScDatasmashEndpoint *endpoint);

/*
 * Returns the largest complete legacy video packet that can be carried inside
 * one negotiated QUIC DATAGRAM after StationConnect framing. Zero means the
 * endpoint is invalid or has not reached READY.
 */
size_t sc_datasmash_video_max_packet_size(const ScDatasmashEndpoint *endpoint);
size_t sc_datasmash_audio_max_packet_size(const ScDatasmashEndpoint *endpoint);

/*
 * Server-only, nonblocking video submission. Both byte ranges are copied
 * before this function returns. SC_DATASMASH_DROPPED means the new packet was
 * accepted after evicting the oldest queued video packet to preserve latency.
 */
int32_t sc_datasmash_video_send(ScDatasmashEndpoint *endpoint,
                                const uint8_t *prefix,
                                size_t prefix_size,
                                const uint8_t *payload,
                                size_t payload_size);

/*
 * Client-only bounded wait for one received legacy video packet. On success,
 * packet_size_out is the copied byte count. When the destination is too small,
 * packet_size_out reports the required count and the packet remains queued.
 */
int32_t sc_datasmash_video_receive(ScDatasmashEndpoint *endpoint,
                                   uint8_t *packet,
                                   size_t packet_capacity,
                                   size_t *packet_size_out,
                                   uint32_t timeout_ms);

/*
 * Server-only, nonblocking audio submission. Complete existing encrypted
 * audio or audio-FEC packets are copied without repacketization. Audio has
 * strict dequeue priority over video. SC_DATASMASH_DROPPED means the new
 * packet was accepted after evicting the oldest queued audio packet.
 */
int32_t sc_datasmash_audio_send(ScDatasmashEndpoint *endpoint,
                                const uint8_t *prefix,
                                size_t prefix_size,
                                const uint8_t *payload,
                                size_t payload_size);

/*
 * Client-only bounded wait for one received legacy audio packet. Buffer and
 * retention behavior matches sc_datasmash_video_receive().
 */
int32_t sc_datasmash_audio_receive(ScDatasmashEndpoint *endpoint,
                                   uint8_t *packet,
                                   size_t packet_capacity,
                                   size_t *packet_size_out,
                                   uint32_t timeout_ms);

/*
 * Bidirectional, nonblocking submission of one complete encrypted GameStream
 * control packet. The bytes are copied. A full bounded queue returns
 * SC_DATASMASH_TIMEOUT and never evicts a previously accepted record.
 */
int32_t sc_datasmash_control_send(ScDatasmashEndpoint *endpoint,
                                  const uint8_t *packet,
                                  size_t packet_size);

/*
 * Bidirectional bounded wait for one complete encrypted GameStream control
 * packet. Buffer and retention behavior matches the media receive functions.
 */
int32_t sc_datasmash_control_receive(ScDatasmashEndpoint *endpoint,
                                     uint8_t *packet,
                                     size_t packet_capacity,
                                     size_t *packet_size_out,
                                     uint32_t timeout_ms);

int32_t sc_datasmash_endpoint_stats(const ScDatasmashEndpoint *endpoint,
                                    ScDatasmashStats *stats);

int32_t sc_datasmash_endpoint_stop(ScDatasmashEndpoint *endpoint);
void sc_datasmash_endpoint_destroy(ScDatasmashEndpoint *endpoint);

/*
 * Returns the required byte count including the trailing NUL. If buffer is
 * non-NULL and buffer_size is nonzero, the result is always NUL-terminated.
 */
size_t sc_datasmash_endpoint_last_error(const ScDatasmashEndpoint *endpoint,
                                        char *buffer,
                                        size_t buffer_size);

/*
 * KyProto-native complete-frame API. This deliberately bypasses the legacy
 * GameStream RTP, AES, Reed-Solomon, packetization, and depacketization path.
 * The Host submits complete encoded Annex-B frames and raw Opus packets;
 * KyProto owns packetization, RaptorQ, ordering, and reconstruction.
 */
int32_t sc_datasmash_native_endpoint_create(
        const ScDatasmashConfig *config,
        ScDatasmashNativeEndpoint **endpoint_out);
int32_t sc_datasmash_native_endpoint_start(
        ScDatasmashNativeEndpoint *endpoint);
int32_t sc_datasmash_native_endpoint_wait_ready(
        ScDatasmashNativeEndpoint *endpoint, uint32_t timeout_ms);
uint32_t sc_datasmash_native_endpoint_state(
        const ScDatasmashNativeEndpoint *endpoint);

/*
 * A Client config with certificate_sha256 == NULL pauses in PEER_VALIDATION.
 * The caller must validate this DER leaf certificate against the
 * StationConnect certificate profile, then explicitly approve it. No native
 * application queue is active before approval. Exact-fingerprint Client
 * configs retain automatic validation and proceed directly to READY.
 */
int32_t sc_datasmash_native_endpoint_peer_certificate(
        const ScDatasmashNativeEndpoint *endpoint,
        uint8_t *certificate, size_t certificate_capacity,
        size_t *certificate_size_out);
int32_t sc_datasmash_native_endpoint_approve_peer_certificate(
        ScDatasmashNativeEndpoint *endpoint);

/*
 * SETUP endpoints expose only reliable data while in SETUP_READY. After the
 * Host has completed PAM, ownership, display, and launch validation and sent
 * SESSION_READY, each peer authorizes its side of the same connection. Only
 * then are KyProto media and input endpoints registered and READY reached.
 */
int32_t sc_datasmash_native_endpoint_authorize_session(
        ScDatasmashNativeEndpoint *endpoint);

int32_t sc_datasmash_native_video_send(
        ScDatasmashNativeEndpoint *endpoint,
        const ScDatasmashNativeVideoFrameInfo *info,
        const uint8_t *payload, size_t payload_size);
/* Update the live video target and peak-inclusive native transport budget. */
int32_t sc_datasmash_native_set_video_bitrate(
        ScDatasmashNativeEndpoint *endpoint, uint32_t bitrate_kbps,
        uint32_t peak_bitrate_kbps);
int32_t sc_datasmash_native_video_receive(
        ScDatasmashNativeEndpoint *endpoint,
        ScDatasmashNativeVideoFrameInfo *info,
        uint8_t *payload, size_t payload_capacity,
        size_t *payload_size_out, uint32_t timeout_ms);

int32_t sc_datasmash_native_audio_send(
        ScDatasmashNativeEndpoint *endpoint,
        const ScDatasmashNativeAudioPacketInfo *info,
        const uint8_t *payload, size_t payload_size);
int32_t sc_datasmash_native_audio_receive(
        ScDatasmashNativeEndpoint *endpoint,
        ScDatasmashNativeAudioPacketInfo *info,
        uint8_t *payload, size_t payload_capacity,
        size_t *payload_size_out, uint32_t timeout_ms);

int32_t sc_datasmash_native_input_send(
        ScDatasmashNativeEndpoint *endpoint, uint8_t type,
        const uint8_t *payload, size_t payload_size);
int32_t sc_datasmash_native_input_receive(
        ScDatasmashNativeEndpoint *endpoint, uint8_t *type_out,
        uint8_t *payload, size_t payload_capacity,
        size_t *payload_size_out, uint32_t timeout_ms);

int32_t sc_datasmash_native_data_send(
        ScDatasmashNativeEndpoint *endpoint,
        const uint8_t *payload, size_t payload_size);
int32_t sc_datasmash_native_data_receive(
        ScDatasmashNativeEndpoint *endpoint,
        uint8_t *payload, size_t payload_capacity,
        size_t *payload_size_out, uint32_t timeout_ms);

int32_t sc_datasmash_native_endpoint_stats(
        const ScDatasmashNativeEndpoint *endpoint,
        ScDatasmashNativeStats *stats);
int32_t sc_datasmash_native_endpoint_stop(
        ScDatasmashNativeEndpoint *endpoint);
void sc_datasmash_native_endpoint_destroy(
        ScDatasmashNativeEndpoint *endpoint);
size_t sc_datasmash_native_endpoint_last_error(
        const ScDatasmashNativeEndpoint *endpoint,
        char *buffer, size_t buffer_size);

#ifdef __cplusplus
}
#endif

#endif
