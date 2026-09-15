// SPDX-License-Identifier: GPL-3.0-or-later
#import "host-runtime.h"
#import "fixed-capture.h"
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
    _server.prepareDisplay = ^NSDictionary *(NSDictionary *request, NSString *token, NSData *peer,
                                             uint16_t port, unsigned *status) {
        (void)port;
        typeof(self) owner = weakSelf;
        if (!owner) { *status = 503; return nil; }
        return [owner prepareDisplayRequest:request token:token peer:peer status:status];
    };
    _server.recoverTopology = ^BOOL(BOOL (^authorized)(void)) {
        typeof(self) owner = weakSelf;
        if (!owner) return NO;
        @synchronized(owner) {
            if (!owner.recoverDisplay || !owner->_started || atomic_load(&owner->_stopping) ||
                (owner->_stream && owner->_stream.state != PLANKMacPreviewStopped)) return NO;
            PLANKMacGraphicalIdentity scope = owner->_snapshot();
            BOOL (^valid)(void) = ^BOOL {
                return !atomic_load(&owner->_stopping) && authorized() &&
                    plank_macos_same_graphical_scope(scope, owner->_snapshot());
            };
            unsigned status = 0;
            if (!valid() || [owner permissionError:&status]) return NO;
            return owner.recoverDisplay(valid) && valid();
        }
    };
    return _server ? self : nil;
}
- (NSDictionary *)prepareDisplayRequest:(NSDictionary *)request token:(NSString *)token
                                  peer:(NSData *)peer status:(unsigned *)status {
    @synchronized(self) {
        if (!self.prepareDisplay || atomic_load(&_stopping) || !_started) {
            NSLog(@"PLANK desktop preparation unavailable: provider=%d stopping=%d started=%d",
                self.prepareDisplay != nil, atomic_load(&_stopping), _started);
            *status = 503; return nil;
        }
        if (_stream && _stream.state != PLANKMacPreviewStopped) { *status = 409; return nil; }
        if (request.count != 4 || !PLANKMacEncodingProfile(request[@"encoding_mode"])) { *status = 400; return nil; }
        for (NSString *key in @[@"schema_version", @"width", @"height"]) {
            id number = request[key];
            if (![number isKindOfClass:NSNumber.class] ||
                CFGetTypeID((__bridge CFTypeRef)number) == CFBooleanGetTypeID() ||
                [number doubleValue] != [number unsignedIntValue]) { *status = 400; return nil; }
        }
        unsigned width = [request[@"width"] unsignedIntValue], height = [request[@"height"] unsignedIntValue];
        if ([request[@"schema_version"] unsignedIntValue] != 2 || width < 2 || height < 2 ||
            width > 8192 || height > 8192) { *status = 400; return nil; }
        PLANKMacGraphicalIdentity scope = _snapshot();
        BOOL (^valid)(void) = ^BOOL {
            PLANKMacAccountIdentity account = {0};
            return !atomic_load(&self->_stopping) &&
                plank_macos_same_graphical_scope(scope, self->_snapshot()) &&
                [self->_sessions authorizeToken:token peer:peer identity:&account];
        };
        if (!valid()) { *status = 401; return nil; }
        NSDictionary *permissionError = [self permissionError:status];
        if (permissionError) return permissionError;
        if (!self.prepareDisplay(width, height, request[@"encoding_mode"], valid) || !valid()) {
            NSLog(@"PLANK desktop preparation failed: %ux%u", width, height);
            *status = 503; return nil;
        }
        NSDictionary *topology = _topology();
        if (!topology || [topology[@"capture"][@"width"] unsignedIntValue] != width ||
            [topology[@"capture"][@"height"] unsignedIntValue] != height ||
            ![topology[@"capture"][@"encoding_profile"] isEqual:PLANKMacEncodingProfile(request[@"encoding_mode"])] || !valid()) {
            *status = 503; return nil;
        }
        *status = 200; return topology;
    }
}
- (BOOL)startOnPort:(uint16_t)port ready:(void (^)(uint16_t))ready failed:(void (^)(void))failed {
    @synchronized(self) {
        if (_started || atomic_load(&_stopping) || !ready || !plank_macos_graphical_identity_valid(_snapshot())) return NO;
        _started = YES;
        return [_server startOnAddress:_address port:port ready:ready failed:failed];
    }
}
// Called only after HTTPS authentication, before changing display geometry or
// consuming a stream lease. Discovery/auth remain available for remediation.
- (NSDictionary *)permissionError:(unsigned *)status {
    BOOL screen = [_capture() available], input = [_input() available];
    if (screen && input) return nil;
    NSLog(@"PLANK stream admission denied: screen-capture=%d input=%d; approve PLANK Host in System Settings > Privacy & Security", screen, input);
    *status = 403;
    return @{@"state": @"denied", @"error": @"host_permissions_required"};
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
        NSDictionary *permissionError = [self permissionError:status];
        if (permissionError) return permissionError;
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
        NSDictionary *reply = @{@"schema_version": @2, @"state": @"connecting",
            @"transport_token": transportToken, @"udp_port": @(port),
            @"max_udp_payload_size": request[@"max_udp_payload_size"], @"capture": selected[@"capture"],
            @"services": @{@"audio": @YES, @"input": @YES, @"pen": @"normalized", @"cursor": @"embedded"}};
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
