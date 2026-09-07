// SPDX-License-Identifier: GPL-3.0-or-later
// Generated Opus fixture and synthetic account only. Real native QUIC.
#import "native-audio.h"
#include <unistd.h>
#include <sys/resource.h>

static unsigned checks;
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "failed line %d: %s\n", __LINE__, #x); exit(1); } ++checks; } while (0)
PLANKMacAuthenticationResult PLANKMacVerifyAccountIsolated(
        NSString *name, NSMutableData *password, PLANKMacAccountIdentity *identity) {
    BOOL valid = [name isEqual:@"synthetic"] && password.length == 4 && !memcmp(password.bytes, "test", 4);
    [password resetBytesInRange:NSMakeRange(0, password.length)];
    *identity = (PLANKMacAccountIdentity){123, {1}};
    return valid ? PLANKMacAuthenticationVerified : PLANKMacAuthenticationDenied;
}
static uint32_t read32(const uint8_t *bytes) {
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}
static PlankTransportConfig config(uint32_t mode, NSString *token) {
    PlankTransportConfig value = {0};
    value.struct_size = sizeof(value); value.abi_version = PLANK_TRANSPORT_ABI_VERSION;
    value.mode = mode; value.session_token = token.UTF8String;
    value.handshake_timeout_ms = 5000; value.idle_timeout_ms = 10000;
    value.keep_alive_interval_ms = 1000; value.max_udp_payload_size = 1200;
    value.initial_video_bitrate_kbps = 10000;
    return value;
}
int main(int argc, const char **argv) {
    if (argc != 5) return 2; // cert, key, fingerprint, generated PAO1 fixture
    alarm(30);
    struct rlimit noCore = {0, 0}; CHECK(!setrlimit(RLIMIT_CORE, &noCore));
    @autoreleasepool {
        NSData *fixture = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[4]]];
        CHECK(fixture.length >= 16 && fixture.length < 1000000);
        const uint8_t *bytes = fixture.bytes;
        CHECK(!memcmp(bytes, "PAO1", 4) && read32(bytes + 4) == 48000 &&
              read32(bytes + 8) == 2 && read32(bytes + 12) == 240);
        __block PLANKMacDesktopIdentity desktop = {true, 1, {123, {1}}};
        __block BOOL validTopology = YES;
        PLANKMacAuthenticationSession *sessions = [[PLANKMacAuthenticationSession alloc]
            initWithDesktopSnapshot:^{ return desktop; }];
        NSData *peer = [NSData dataWithBytes:"test" length:4];
        NSDictionary *challenge = [sessions startForPeer:peer username:@"synthetic"];
        NSString *token = [sessions respondForPeer:peer conversation:challenge[@"conversation_id"]
            password:[NSMutableData dataWithBytes:"test" length:4]][@"session_token"];
        PLANKMacStreamLease *lease = [sessions claimToken:token peer:peer];
        CHECK(lease != nil);
        PlankTransportConfig serverConfig = config(PLANK_TRANSPORT_MODE_SERVER, lease.transportToken);
        serverConfig.bind_address = "127.0.0.1:47493";
        serverConfig.certificate_path = argv[1]; serverConfig.private_key_path = argv[2];
        PlankTransportConfig clientConfig = config(PLANK_TRANSPORT_MODE_CLIENT, lease.transportToken);
        clientConfig.remote_address = "127.0.0.1:47493"; clientConfig.server_name = "localhost";
        clientConfig.certificate_sha256 = argv[3];
        PlankTransportNativeEndpoint *server = NULL, *client = NULL;
        CHECK(plank_transport_native_endpoint_create(&serverConfig, &server) == PLANK_TRANSPORT_OK);
        CHECK(plank_transport_native_endpoint_create(&clientConfig, &client) == PLANK_TRANSPORT_OK);
        CHECK(plank_transport_native_endpoint_start(server) == PLANK_TRANSPORT_OK);
        CHECK(plank_transport_native_endpoint_start(client) == PLANK_TRANSPORT_OK);
        CHECK(plank_transport_native_endpoint_wait_ready(client, 5000) == PLANK_TRANSPORT_OK);
        CHECK(plank_transport_native_endpoint_wait_ready(server, 5000) == PLANK_TRANSPORT_OK);
        PLANKMacNativeAudio *audio = [[PLANKMacNativeAudio alloc] initWithEndpoint:server
            sessions:sessions lease:lease validity:^BOOL { return validTopology; }];
        CHECK(audio != nil);
        CHECK([audio sendOpusPacket:nil presentationTime:kCMTimeZero] == PLANK_TRANSPORT_ERROR_INVALID_STATE);
        CHECK([sessions activateStreamLease:lease]);
        CHECK([audio sendOpusPacket:nil presentationTime:kCMTimeZero] == PLANK_TRANSPORT_ERROR_INVALID_ARGUMENT);
        unsigned count = 0;
        NSData *lastPacket = nil;
        for (size_t offset = 16; offset < fixture.length;) {
            CHECK(fixture.length - offset >= 4);
            uint32_t size = read32(bytes + offset); offset += 4;
            CHECK(size > 0 && size <= 65536 && size <= fixture.length - offset);
            NSData *packet = [NSData dataWithBytes:bytes + offset length:size]; offset += size;
            // Source time starts at 10.0005 s, proving both conversion and
            // fractional-millisecond rounding independently of callback time.
            CMTime pts = CMTimeMake(480024 + (int64_t)count * 240, 48000);
            if (!count) {
                CHECK([audio sendOpusPacket:packet presentationTime:kCMTimeInvalid] == PLANK_TRANSPORT_ERROR_INVALID_ARGUMENT);
                CHECK([audio sendOpusPacket:packet presentationTime:CMTimeMake(-1, 48000)] == PLANK_TRANSPORT_ERROR_INVALID_ARGUMENT);
                CHECK([audio sendOpusPacket:packet presentationTime:CMTimeMakeWithEpoch(1, 48000, 1)] == PLANK_TRANSPORT_ERROR_INVALID_ARGUMENT);
                validTopology = NO;
                CHECK([audio sendOpusPacket:packet presentationTime:pts] == PLANK_TRANSPORT_ERROR_INVALID_STATE);
                validTopology = YES;
            }
            CHECK([audio sendOpusPacket:packet presentationTime:pts] == PLANK_TRANSPORT_OK);
            CHECK([audio sendOpusPacket:packet presentationTime:pts] == PLANK_TRANSPORT_ERROR_INVALID_ARGUMENT);
            CHECK([audio sendOpusPacket:packet presentationTime:CMTimeAdd(pts, CMTimeMake(1, 1))] == PLANK_TRANSPORT_ERROR_INVALID_ARGUMENT);
            uint8_t output[65536]; size_t receivedSize = 0;
            PlankTransportNativeAudioPacketInfo info = {0}; info.struct_size = sizeof(info);
            CHECK(plank_transport_native_audio_receive(client, &info, output, sizeof(output), &receivedSize, 3000) == PLANK_TRANSPORT_OK);
            CHECK(receivedSize == size && !memcmp(output, packet.bytes, size));
            CHECK(info.frame_samples == 240 && info.missing_samples == 0 && info.pts == 10000 + (uint64_t)count * 5);
            lastPacket = packet; ++count;
        }
        CHECK(count == 402);
        desktop.active = false;
        CHECK([audio sendOpusPacket:lastPacket presentationTime:CMTimeMake(480024 + count * 240, 48000)] == PLANK_TRANSPORT_ERROR_INVALID_STATE);
        CHECK(lease.transportToken == nil);
        desktop.active = true; // must not resurrect the old lease
        CHECK([audio sendOpusPacket:lastPacket presentationTime:CMTimeMake(480024 + count * 240, 48000)] == PLANK_TRANSPORT_ERROR_INVALID_STATE);
        uint8_t absent[65536]; size_t absentSize = 0;
        PlankTransportNativeAudioPacketInfo absentInfo = {0}; absentInfo.struct_size = sizeof(absentInfo);
        CHECK(plank_transport_native_audio_receive(client, &absentInfo, absent, sizeof(absent), &absentSize, 50) == PLANK_TRANSPORT_TIMEOUT);
        [sessions revokeAll]; audio = nil;
        plank_transport_native_endpoint_destroy(client);
        plank_transport_native_endpoint_destroy(server);
        printf("macos_native_audio=pass checks=%u packets=%u exact_quic_payload=1 pts_milliseconds=1 revoked_audio_absent=1 synthetic_only=1\n", checks, count);
    }
    return 0;
}
