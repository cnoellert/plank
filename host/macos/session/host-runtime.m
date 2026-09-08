// SPDX-License-Identifier: GPL-3.0-or-later
#import "host-runtime.h"
#include <arpa/inet.h>
#include <stdatomic.h>

@implementation PLANKMacHostRuntime {
    PLANKMacAuthenticationSession *_sessions;
    PLANKMacHTTPSAuthServer *_server;
    PLANKMacPreviewSession *_stream;
    PLANKMacGraphicalSnapshot _snapshot;
    NSDictionary *(^_topology)(void);
    id<PLANKMacPreviewCapture> (^_capture)(void);
    id<PLANKMacInputDevice> (^_input)(void);
    NSString *_address, *_certificate, *_privateKey;
    BOOL _started;
    atomic_bool _stopping;
}
- (instancetype)init { return nil; }
- (instancetype)initWithIdentity:(SecIdentityRef)identity
                     information:(PLANKMacServerInformation *)information
                        snapshot:(PLANKMacGraphicalSnapshot)snapshot
                        topology:(NSDictionary *(^)(void))topology address:(NSString *)address
                     certificate:(NSString *)certificate privateKey:(NSString *)privateKey
                         capture:(id<PLANKMacPreviewCapture> (^)(void))capture
                           input:(id<PLANKMacInputDevice> (^)(void))input {
    struct in_addr ip;
    if (!identity || !information || !snapshot || !topology || !capture || !input ||
        !address || inet_pton(AF_INET, address.UTF8String, &ip) != 1 ||
        !certificate.isAbsolutePath || !privateKey.isAbsolutePath) return nil;
    self = [super init];
    if (!self) return nil;
    _snapshot = [snapshot copy]; _topology = [topology copy];
    _capture = [capture copy]; _input = [input copy];
    _address = [address copy]; _certificate = [certificate copy]; _privateKey = [privateKey copy];
    _sessions = [[PLANKMacAuthenticationSession alloc] initWithGraphicalSnapshot:snapshot];
    __weak typeof(self) weakSelf = self;
    _server = [[PLANKMacHTTPSAuthServer alloc] initWithIdentity:identity sessions:_sessions
        information:information topology:topology
        launch:^NSDictionary *(NSDictionary *request, NSString *token, NSData *peer, uint16_t port, unsigned *status) {
            typeof(self) owner = weakSelf;
            if (!owner) { *status = 503; return nil; }
            return [owner launch:request token:token peer:peer port:port status:status];
        }];
    return _server ? self : nil;
}
- (BOOL)startOnPort:(uint16_t)port ready:(void (^)(uint16_t))ready failed:(void (^)(void))failed {
    @synchronized(self) {
        if (_started || atomic_load(&_stopping) || !ready || !plank_macos_graphical_identity_valid(_snapshot())) return NO;
        _started = YES;
        return [_server startOnAddress:_address port:port ready:ready failed:failed];
    }
}
- (NSDictionary *)launch:(NSDictionary *)request token:(NSString *)token peer:(NSData *)peer
                    port:(uint16_t)port status:(unsigned *)status {
    // Serialize endpoint construction with shutdown's stream snapshot, NOT
    // account verification or capture/encoding. Shutdown never waits on the UI.
    @synchronized(self) {
        if (atomic_load(&_stopping) || !_started || !plank_macos_graphical_identity_valid(_snapshot())) {
            *status = 503; return nil;
        }
        NSDictionary *selected = _topology();
        if (!PLANKMacPreviewRequestMatchesTopology(request, selected)) { *status = 400; return nil; }
        if (_stream && _stream.state != PLANKMacPreviewStopped) { *status = 409; return nil; }
        NSString *bind = [NSString stringWithFormat:@"%@:%u", _address, port];
        PlankTransportConfig config = {0};
        config.struct_size = sizeof(config); config.abi_version = PLANK_TRANSPORT_ABI_VERSION;
        config.mode = PLANK_TRANSPORT_MODE_SERVER;
        config.bind_address = bind.UTF8String;
        config.certificate_path = _certificate.UTF8String;
        config.private_key_path = _privateKey.UTF8String;
        config.idle_timeout_ms = 10000; config.keep_alive_interval_ms = 1000;
        _stream = [[PLANKMacPreviewSession alloc] initWithSessions:_sessions token:token peer:peer
            request:request topology:_topology config:&config capture:_capture() input:_input()];
        if (!_stream) { *status = 503; return nil; }
        // Snapshot after endpoint creation as well. Do not put a later display
        // generation into a manifest for a stream created against an older one.
        NSString *transportToken = _stream.transportToken;
        if (atomic_load(&_stopping) || !transportToken || ![selected isEqual:_topology()] ||
            !plank_macos_graphical_identity_valid(_snapshot())) {
            [_stream stopWithCompletion:nil]; *status = 503; return nil;
        }
        NSDictionary *reply = @{@"schema_version": @1, @"state": @"connecting",
            @"transport_token": transportToken, @"udp_port": @(port),
            @"max_udp_payload_size": request[@"max_udp_payload_size"], @"capture": selected[@"capture"],
            @"services": @{@"audio": @YES, @"input": @YES, @"cursor": @"embedded"}};
        [_stream start]; *status = 200; return reply;
    }
}
- (void)stopWithCompletion:(void (^)(void))completion {
    atomic_store(&_stopping, true);
    // Endpoint construction may still be finishing on the auth lane. Never
    // make the graphical event loop wait for its lock or filesystem I/O.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        PLANKMacPreviewSession *stream;
        @synchronized(self) { stream = self->_stream; }
        // Normal stop releases held input before the HTTP owner revokes tokens.
        // Scope loss independently blocks release into another account. During
        // this bounded drain HTTP can still answer, but launch is already closed.
        void (^finish)(void) = ^{
            [self->_server stopWithCompletion:completion];
        };
        if (stream) [stream stopWithCompletion:finish]; else finish();
    });
}
@end
