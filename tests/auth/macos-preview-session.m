// SPDX-License-Identifier: GPL-3.0-or-later
// Synthetic capture/account, actual native QUIC; no desktop pixels or changes.
#import "preview-session.h"
#import "fixed-capture.h"
#include "plank_transport_control.h"
#include <unistd.h>
#include <sys/resource.h>

static unsigned checks;
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "check failed line %d: %s\n", __LINE__, #x); exit(1); } ++checks; } while (0)
static BOOL until(BOOL (^predicate)(void)) {
    for (unsigned i = 0; i < 350; ++i) { if (predicate()) return YES; usleep(20000); }
    return NO;
}
PLANKMacAuthenticationResult PLANKMacVerifyAccountIsolated(
        NSString *name, NSMutableData *password, PLANKMacAccountIdentity *identity) {
    BOOL valid = [name isEqual:@"synthetic"] && password.length == 4 && !memcmp(password.bytes, "test", 4);
    [password resetBytesInRange:NSMakeRange(0, password.length)];
    *identity = valid ? (PLANKMacAccountIdentity){123, {1}} : (PLANKMacAccountIdentity){0};
    return valid ? PLANKMacAuthenticationVerified : PLANKMacAuthenticationDenied;
}
@interface PLANKFakeCapture : NSObject <PLANKMacPreviewCapture>
@property unsigned starts, stops;
@property BOOL deferStart, failStart, deferStop, revokedBeforeStop;
@property uint32_t bitrate;
@property PLANKMacNativeVideo *video;
@property dispatch_queue_t queue;
@property(copy) void (^pendingStop)(void);
@end
@implementation PLANKFakeCapture
- (void)startWithTopology:(NSDictionary *)topology bitrate:(uint32_t)bitrate video:(PLANKMacNativeVideo *)video
                   queue:(dispatch_queue_t)queue started:(void (^)(uint32_t))started failed:(void (^)(void))failed {
    (void)topology; self.queue = queue;
    self.starts++; self.bitrate = bitrate; self.video = video;
    if (self.failStart) failed();
    else if (!self.deferStart) started(2 * bitrate);
}
- (BOOL)setBitrate:(uint32_t)bitrate peak:(uint32_t *)peak {
    self.bitrate = bitrate; *peak = 2 * bitrate; return YES;
}
- (void)stopWithCompletion:(void (^)(void))completion {
    self.revokedBeforeStop = [self.video sendSample:NULL processingLatency:0] == PLANK_TRANSPORT_ERROR_INVALID_STATE;
    self.stops++; self.video = nil;
    if (self.deferStop) self.pendingStop = completion;
    else completion();
}
@end

static NSString *authenticate(PLANKMacAuthenticationSession *auth, NSData *peer) {
    NSDictionary *start = [auth startForPeer:peer username:@"synthetic"];
    NSString *token = [auth respondForPeer:peer conversation:start[@"conversation_id"]
        password:[NSMutableData dataWithBytes:"test" length:4]][@"session_token"];
    CHECK(token != nil);
    return token;
}

int main(int argc, const char **argv) {
    if (argc != 5) return 2; // cert, key, pin, shared request fixture
    alarm(60);
    struct rlimit core = {0, 0}; CHECK(!setrlimit(RLIMIT_CORE, &core));
    @autoreleasepool {
        __block PLANKMacDesktopIdentity desktop = {true, 1, {123, {1}}};
        NSObject *guard = [NSObject new];
        __block NSDictionary *topology = PLANKMacFixedCaptureDescription(@"98454815-80ab-4a88-b187-92f59353afca",
            @"cgdisplay:42", 3840, 2160, CGRectMake(-1920, 0, 1920, 1080));
        NSDictionary *(^snapshot)(void) = ^{ @synchronized(guard) { return topology; } };
        PLANKMacAuthenticationSession *auth = [[PLANKMacAuthenticationSession alloc] initWithDesktopSnapshot:^{
            @synchronized(guard) { return desktop; }
        }];
        NSData *fixture = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[4]]];
        NSDictionary *request = fixture ? [NSJSONSerialization JSONObjectWithData:fixture options:0 error:NULL] : nil;
        CHECK(PLANKMacPreviewRequestMatchesTopology(request, topology));
        CHECK(!PLANKMacPreviewRequestMatchesTopology(nil, topology));
        CHECK(!PLANKMacPreviewRequestMatchesTopology(request, nil));
        for (NSString *field in request) {
            NSMutableDictionary *bad = [request mutableCopy]; [bad removeObjectForKey:field];
            CHECK(!PLANKMacPreviewRequestMatchesTopology(bad, topology));
            for (id value in @[[NSNull null], @[], @{}, @YES, @"invalid"]) {
                bad[field] = value;
                CHECK(!PLANKMacPreviewRequestMatchesTopology(bad, topology));
            }
        }
        for (NSString *field in @[@"width", @"height", @"frame_rate", @"bitrate_kbps", @"max_udp_payload_size"]) {
            for (NSNumber *value in @[@(-1), @1.5, @(UINT64_MAX)]) {
                NSMutableDictionary *bad = [request mutableCopy]; bad[field] = value;
                CHECK(!PLANKMacPreviewRequestMatchesTopology(bad, topology));
            }
        }
        NSMutableDictionary *extra = [request mutableCopy]; extra[@"audio"] = @YES;
        CHECK(!PLANKMacPreviewRequestMatchesTopology(extra, topology));

        PlankTransportConfig cfg = {0}; cfg.struct_size = sizeof(cfg); cfg.abi_version = PLANK_TRANSPORT_ABI_VERSION;
        cfg.mode = PLANK_TRANSPORT_MODE_SERVER; cfg.bind_address = "127.0.0.1:47492";
        cfg.certificate_path = argv[1]; cfg.private_key_path = argv[2];
        cfg.idle_timeout_ms = 10000; cfg.keep_alive_interval_ms = 1000;
        NSData *peer = [NSData dataWithBytes:"test" length:4];
        NSData *wrongPeer = [NSData dataWithBytes:"nope" length:4];
        NSString *token = authenticate(auth, peer);
        PLANKFakeCapture *source = [PLANKFakeCapture new];
        CHECK(![[PLANKMacPreviewSession alloc] initWithSessions:auth token:token peer:wrongPeer request:request
            topology:snapshot config:&cfg capture:source]);
        CHECK(![[PLANKMacPreviewSession alloc] initWithSessions:auth token:token peer:peer request:extra
            topology:snapshot config:&cfg capture:source]);
        PLANKMacAccountIdentity identity = {0};
        CHECK([auth authorizeToken:token peer:peer identity:&identity]);
        for (unsigned scenario = 0; scenario < 9; ++scenario) {
            if (scenario) token = authenticate(auth, peer);
            source = [PLANKFakeCapture new];
            source.failStart = scenario == 4;
            source.deferStart = scenario == 5;
            source.deferStop = scenario == 8;
            PLANKMacPreviewSession *session = [[PLANKMacPreviewSession alloc] initWithSessions:auth token:token peer:peer
                request:request topology:snapshot config:&cfg capture:source];
            CHECK(session && session.state == PLANKMacPreviewPrepared);
            CHECK(![auth authorizeToken:token peer:peer identity:&identity]);
            NSString *transportToken = session.transportToken;
            CHECK(transportToken.length == 44 && ![transportToken isEqual:token]);
            CHECK(!source.starts);
            [session start];
            PlankTransportConfig cc = cfg; cc.mode = PLANK_TRANSPORT_MODE_CLIENT;
            cc.remote_address = cfg.bind_address; cc.server_name = "localhost"; cc.certificate_sha256 = argv[3];
            cc.session_token = transportToken.UTF8String; cc.max_udp_payload_size = 1200;
            PlankTransportNativeEndpoint *client = NULL;
            CHECK(plank_transport_native_endpoint_create(&cc, &client) == PLANK_TRANSPORT_OK);
            CHECK(plank_transport_native_endpoint_start(client) == PLANK_TRANSPORT_OK);
            CHECK(plank_transport_native_endpoint_wait_ready(client, 5000) == PLANK_TRANSPORT_OK);
            if (scenario < 4 || scenario >= 6) {
                CHECK(until(^BOOL { return session.state == PLANKMacPreviewStreaming; }));
                CHECK(source.starts == 1 && source.bitrate == 50000);
            }
            uint8_t control[20]; size_t length = 0;
            if (scenario == 0) {
                uint32_t bitrate = 76500;
                CHECK(!plank_transport_control_encode(PLANK_TRANSPORT_CONTROL_SET_VIDEO_BITRATE, &bitrate, 1,
                    control, sizeof(control), &length));
                CHECK(plank_transport_native_data_send(client, control, length) == PLANK_TRANSPORT_OK);
                CHECK(plank_transport_native_data_receive(client, control, sizeof(control), &length, 5000) == PLANK_TRANSPORT_OK);
                PlankTransportControlPacket ack;
                CHECK(!plank_transport_control_decode(control, length, &ack));
                CHECK(ack.type == PLANK_TRANSPORT_CONTROL_VIDEO_BITRATE_APPLIED && ack.payload_size == 12);
                CHECK(plank_transport_control_read_u32(ack.payload) == bitrate &&
                    plank_transport_control_read_u32(ack.payload + 4) == bitrate &&
                    plank_transport_control_read_u32(ack.payload + 8) == 2 * bitrate);
                CHECK(source.bitrate == bitrate);
                CHECK(!plank_transport_control_encode(PLANK_TRANSPORT_CONTROL_CLIENT_DISCONNECT, NULL, 0, control, sizeof(control), &length));
                CHECK(plank_transport_native_data_send(client, control, length) == PLANK_TRANSPORT_OK);
            } else if (scenario == 1) {
                @synchronized(guard) { desktop.generation++; }
            } else if (scenario == 2) {
                @synchronized(guard) { topology = nil; }
            } else if (scenario == 3) {
                CHECK(!plank_transport_control_encode(999, NULL, 0, control, sizeof(control), &length));
                CHECK(plank_transport_native_data_send(client, control, length) == PLANK_TRANSPORT_OK);
            } else if (scenario == 6) {
                [auth revokeToken:token]; // failed HTTPS launch delivery cancellation
            } else if (scenario == 7) {
                session = nil; // accidental owner abandonment must still drain safely
                CHECK(until(^BOOL { return source.stops == 1; }));
                CHECK(source.revokedBeforeStop);
                plank_transport_native_endpoint_destroy(client);
                continue;
            } else if (scenario == 8) {
                CHECK(!plank_transport_control_encode(PLANK_TRANSPORT_CONTROL_CLIENT_DISCONNECT, NULL, 0,
                    control, sizeof(control), &length));
                CHECK(plank_transport_native_data_send(client, control, length) == PLANK_TRANSPORT_OK);
                CHECK(until(^BOOL { return source.pendingStop != nil; }));
                CHECK(session.state == PLANKMacPreviewStopping);
                CHECK(until(^BOOL { return plank_transport_native_endpoint_state(client) != PLANK_TRANSPORT_STATE_READY; }));
                dispatch_async(source.queue, ^{
                    void (^completion)(void) = source.pendingStop; source.pendingStop = nil; completion();
                });
            }
            CHECK(until(^BOOL { return session.state == PLANKMacPreviewStopped; }));
            CHECK(source.stops == 1 && source.revokedBeforeStop && session.transportToken == nil);
            dispatch_semaphore_t stopped = dispatch_semaphore_create(0);
            [session stopWithCompletion:^{ dispatch_semaphore_signal(stopped); }];
            CHECK(dispatch_semaphore_wait(stopped, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0);
            CHECK(source.stops == 1);
            plank_transport_native_endpoint_destroy(client);
            @synchronized(guard) {
                topology = PLANKMacFixedCaptureDescription(@"98454815-80ab-4a88-b187-92f59353afca", @"cgdisplay:42",
                    3840, 2160, CGRectMake(-1920, 0, 1920, 1080));
            }
        }
        [auth revokeAll];
        printf("macos_preview_session=pass checks=%u scenarios=9 synthetic_capture=1 real_quic=1 cleanup=1\n", checks);
    }
}
