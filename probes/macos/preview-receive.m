// SPDX-License-Identifier: GPL-3.0-or-later
// Loopback qualification receiver. Launch secret arrives only over stdin.
#import <Foundation/Foundation.h>
#include "plank_transport.h"
#include "plank_transport_control.h"
#include <unistd.h>
#include <sys/resource.h>
#include <time.h>

#define REQUIRE(x) do { if (!(x)) { fprintf(stderr, "preview receiver check failed at line %d\n", __LINE__); return 1; } } while (0)
int main(int argc, const char **argv) {
    if (argc != 2 && !(argc == 3 && !strcmp(argv[2], "--no-media"))) return 2;
    BOOL media = argc == 2;
    alarm(15);
    struct rlimit core = {0, 0}; REQUIRE(!setrlimit(RLIMIT_CORE, &core));
    @autoreleasepool {
        uint8_t input[32769]; size_t used = 0;
        for (;;) {
            ssize_t size = read(STDIN_FILENO, input + used, sizeof(input) - used);
            REQUIRE(size >= 0);
            if (!size) break;
            used += (size_t)size; REQUIRE(used < sizeof(input));
        }
        NSDictionary *launch = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:input length:used] options:0 error:NULL];
        memset(input, 0, sizeof(input));
        REQUIRE([launch isKindOfClass:NSDictionary.class] && [launch[@"state"] isEqual:@"connecting"]);
        NSString *token = launch[@"transport_token"];
        unsigned width = [launch[@"capture"][@"width"] unsignedIntValue];
        unsigned height = [launch[@"capture"][@"height"] unsignedIntValue];
        unsigned port = [launch[@"udp_port"] unsignedIntValue];
        REQUIRE([token isKindOfClass:NSString.class] && token.length == 44 && port > 0 && port <= UINT16_MAX);
        PlankTransportConfig config = {0}; config.struct_size = sizeof(config); config.abi_version = PLANK_TRANSPORT_ABI_VERSION;
        config.mode = PLANK_TRANSPORT_MODE_CLIENT; config.session_token = token.UTF8String;
        config.remote_address = [NSString stringWithFormat:@"127.0.0.1:%u", port].UTF8String;
        config.server_name = "localhost"; config.certificate_sha256 = argv[1];
        config.handshake_timeout_ms = 5000; config.idle_timeout_ms = 5000; config.keep_alive_interval_ms = 1000;
        config.max_udp_payload_size = [launch[@"max_udp_payload_size"] unsignedIntValue];
        PlankTransportNativeEndpoint *endpoint = NULL;
        REQUIRE(plank_transport_native_endpoint_create(&config, &endpoint) == PLANK_TRANSPORT_OK);
        token = nil; launch = nil;
        REQUIRE(plank_transport_native_endpoint_start(endpoint) == PLANK_TRANSPORT_OK);
        REQUIRE(plank_transport_native_endpoint_wait_ready(endpoint, 5000) == PLANK_TRANSPORT_OK);
        uint64_t frames = 0, totalBytes = 0, lastPTS = 0;
        if (media) {
            NSMutableData *payload = [NSMutableData dataWithLength:64 * 1024 * 1024];
            uint64_t deadline = clock_gettime_nsec_np(CLOCK_MONOTONIC) + 3 * NSEC_PER_SEC;
            while (clock_gettime_nsec_np(CLOCK_MONOTONIC) < deadline) {
                PlankTransportNativeVideoFrameInfo info = {0}; info.struct_size = sizeof(info);
                size_t count = 0;
                int32_t result = plank_transport_native_video_receive(endpoint, &info, payload.mutableBytes, payload.length, &count, 100);
                if (result == PLANK_TRANSPORT_TIMEOUT) continue;
                REQUIRE(result == PLANK_TRANSPORT_OK && count >= 6 && info.codec == PLANK_TRANSPORT_NATIVE_VIDEO_CODEC_HEVC);
                REQUIRE(frames ? info.pts > lastPTS : (info.flags & PLANK_TRANSPORT_NATIVE_VIDEO_FLAG_KEY));
                static const uint8_t start[] = {0, 0, 0, 1};
                REQUIRE(!memcmp(payload.bytes, start, 4));
                ++frames; totalBytes += count; lastPTS = info.pts;
            }
            REQUIRE(frames > 0);
        }
        uint8_t control[20]; size_t count = 0;
        uint32_t target = 111500;
        REQUIRE(!plank_transport_control_encode(PLANK_TRANSPORT_CONTROL_SET_VIDEO_BITRATE, &target, 1, control, sizeof(control), &count));
        REQUIRE(plank_transport_native_data_send(endpoint, control, count) == PLANK_TRANSPORT_OK);
        REQUIRE(plank_transport_native_data_receive(endpoint, control, sizeof(control), &count, 5000) == PLANK_TRANSPORT_OK);
        PlankTransportControlPacket ack;
        REQUIRE(!plank_transport_control_decode(control, count, &ack));
        REQUIRE(ack.type == PLANK_TRANSPORT_CONTROL_VIDEO_BITRATE_APPLIED && ack.payload_size == 12);
        REQUIRE(plank_transport_control_read_u32(ack.payload) == target && plank_transport_control_read_u32(ack.payload + 4) == target);
        REQUIRE(plank_transport_control_read_u32(ack.payload + 8) >= target);
        REQUIRE(!plank_transport_control_encode(PLANK_TRANSPORT_CONTROL_CLIENT_DISCONNECT, NULL, 0, control, sizeof(control), &count));
        REQUIRE(plank_transport_native_data_send(endpoint, control, count) == PLANK_TRANSPORT_OK);
        uint64_t deadline = clock_gettime_nsec_np(CLOCK_MONOTONIC) + 3 * NSEC_PER_SEC;
        while (plank_transport_native_endpoint_state(endpoint) == PLANK_TRANSPORT_STATE_READY &&
            clock_gettime_nsec_np(CLOCK_MONOTONIC) < deadline) usleep(10000);
        REQUIRE(plank_transport_native_endpoint_state(endpoint) != PLANK_TRANSPORT_STATE_READY);
        plank_transport_native_endpoint_destroy(endpoint);
        printf("macos_preview_receiver=pass media=%d negotiated_pixels=%ux%u frames=%llu bytes=%llu bitrate_ack=1 disconnected=1\n",
            media, width, height, (unsigned long long)frames, (unsigned long long)totalBytes);
    }
}
