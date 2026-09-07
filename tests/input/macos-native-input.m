// SPDX-License-Identifier: GPL-3.0-or-later
// Real native QUIC + synthetic account/desktop + non-posting Quartz event sink.
#import "native-input.h"
#include "plank_transport_input.h"
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
    if (argc != 4) return 2; // fixture cert/key/fingerprint, no real account
    alarm(60);
    struct rlimit noCore = {0, 0}; CHECK(!setrlimit(RLIMIT_CORE, &noCore));
    @autoreleasepool {
        CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStatePrivate); CHECK(source != NULL);
        for (unsigned scenario = 0; scenario < 7; ++scenario) {
            __block PLANKMacDesktopIdentity desktop = {true, 1, {123, {1}}};
            PLANKMacAuthenticationSession *sessions = [[PLANKMacAuthenticationSession alloc]
                initWithDesktopSnapshot:^{ return desktop; }];
            NSData *peer = [NSData dataWithBytes:"test" length:4];
            NSDictionary *challenge = [sessions startForPeer:peer username:@"synthetic"];
            NSString *token = [sessions respondForPeer:peer conversation:challenge[@"conversation_id"]
                password:[NSMutableData dataWithBytes:"test" length:4]][@"session_token"];
            PLANKMacStreamLease *lease = [sessions claimToken:token peer:peer]; CHECK(lease != nil);
            PlankTransportConfig serverConfig = config(PLANK_TRANSPORT_MODE_SERVER, lease.transportToken);
            serverConfig.bind_address = "127.0.0.1:47494";
            serverConfig.certificate_path = argv[1]; serverConfig.private_key_path = argv[2];
            PlankTransportConfig clientConfig = config(PLANK_TRANSPORT_MODE_CLIENT, lease.transportToken);
            clientConfig.remote_address = "127.0.0.1:47494"; clientConfig.server_name = "localhost";
            clientConfig.certificate_sha256 = argv[3];
            PlankTransportNativeEndpoint *server = NULL, *client = NULL;
            CHECK(plank_transport_native_endpoint_create(&serverConfig, &server) == PLANK_TRANSPORT_OK);
            CHECK(plank_transport_native_endpoint_create(&clientConfig, &client) == PLANK_TRANSPORT_OK);
            CHECK(plank_transport_native_endpoint_start(server) == PLANK_TRANSPORT_OK);
            CHECK(plank_transport_native_endpoint_start(client) == PLANK_TRANSPORT_OK);
            CHECK(plank_transport_native_endpoint_wait_ready(client, 5000) == PLANK_TRANSPORT_OK);
            CHECK(plank_transport_native_endpoint_wait_ready(server, 5000) == PLANK_TRANSPORT_OK);
            if (scenario != 1) CHECK([sessions activateStreamLease:lease]);
            PLANKMacInputEvents *events = [[PLANKMacInputEvents alloc] initWithSource:source
                bounds:CGRectMake(-1920, 0, 1920, 1080) pixels:CGSizeMake(3840, 2160)
                initialPosition:CGPointMake(-1920, 0) doubleClickInterval:0.5]; CHECK(events != nil);
            __block unsigned delivered = 0, validityCalls = 0;
            __block BOOL topology = YES, permission = YES;
            PLANKMacNativeInput *input = [[PLANKMacNativeInput alloc] initWithEndpoint:server
                sessions:sessions lease:lease events:events validity:^BOOL {
                    ++validityCalls;
                    // Simulate ownership loss between event construction and
                    // the last bounded delivery check, without a racing thread.
                    if (scenario == 6 && validityCalls == 2) { [sessions revokeAll]; return NO; }
                    return topology && permission;
                } deliver:^(CGEventRef event) {
                    CHECK(event != NULL); ++delivered; // NEVER CGEventPost
                }]; CHECK(input != nil);
            uint8_t p[] = {0x80, 0x41, 1, 0, 0}; // normalized A down
            CHECK(plank_transport_native_input_send(client, 5, p, sizeof(p)) == PLANK_TRANSPORT_OK);
            uint8_t type = 0, payload[8192]; size_t size = 0;
            CHECK(plank_transport_native_input_receive(server, &type, payload, sizeof(payload), &size, 3000) == PLANK_TRANSPORT_OK);
            CHECK(type == 5 && size == sizeof(p) && !memcmp(p, payload, size));
            PLANKMacInputResult result = [input consumeType:type payload:[NSData dataWithBytes:payload length:size] time:1000000000];
            if (scenario == 1 || scenario == 6) {
                CHECK(result == PLANKMacInputDenied && delivered == 0);
                if (scenario == 1) CHECK([sessions activateStreamLease:lease]);
                CHECK([input consumeType:type payload:[NSData dataWithBytes:p length:sizeof(p)] time:1000000001] == PLANKMacInputStopped);
                CHECK([input stop] == 0 && [input stop] == 0 && delivered == 0);
            } else {
                CHECK(result == PLANKMacInputEvent && delivered == 1);
                if (scenario == 0) {
                    // Transport loss does not prevent safe release in the same
                    // authorized desktop. No further input may be delivered.
                    CHECK(plank_transport_native_endpoint_stop(server) == PLANK_TRANSPORT_OK);
                    CHECK([input stop] == 1 && delivered == 2);
                } else {
                    if (scenario == 2) desktop.active = false;
                    if (scenario == 3) desktop.generation++;
                    if (scenario == 4) topology = NO;
                    if (scenario == 5) permission = NO;
                    CHECK([input consumeType:type payload:[NSData dataWithBytes:p length:sizeof(p)] time:1000000001] == PLANKMacInputDenied);
                    CHECK([input stop] == 0 && delivered == 1);
                    desktop.active = true; topology = YES; permission = YES;
                    CHECK([input consumeType:type payload:[NSData dataWithBytes:p length:sizeof(p)] time:1000000002] == PLANKMacInputStopped);
                }
                CHECK([input stop] == 0);
            }
            [sessions revokeAll]; input = nil; events = nil;
            plank_transport_native_endpoint_stop(client); plank_transport_native_endpoint_stop(server);
            plank_transport_native_endpoint_destroy(client); plank_transport_native_endpoint_destroy(server);
        }
        CFRelease(source);
        printf("macos_native_input checks=%u scenarios=7 posted_events=0\n", checks);
    }
    return 0;
}
