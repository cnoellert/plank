// SPDX-License-Identifier: GPL-3.0-or-later
#import "https-auth-server.h"
#import "http-request.h"
#import <Network/Network.h>
#include <arpa/inet.h>
#include <sys/resource.h>
#include <time.h>

@interface PLANKMacHTTPSRequest : NSObject
@property nw_connection_t connection;
@property NSMutableData *bytes;
@property NSData *peer;
@property BOOL finished;
@property BOOL dispatched;
@property uint64_t deadline;
@end
@implementation PLANKMacHTTPSRequest
@end

@implementation PLANKMacHTTPSAuthServer {
    sec_identity_t _identity;
    PLANKMacAuthenticationSession *_sessions;
    PLANKMacServerInformation *_information;
    NSData *_serverInformationXML;
    NSDictionary *(^_topology)(void);
    nw_listener_t _listener;
    dispatch_queue_t _networkQueue;
    dispatch_queue_t _authQueue;
    NSMutableSet<PLANKMacHTTPSRequest *> *_requests;
    BOOL _stopped;
    BOOL _authBusy;
    dispatch_source_t _expiryTimer;
}

- (instancetype)initWithIdentity:(SecIdentityRef)identity sessions:(PLANKMacAuthenticationSession *)sessions
                    information:(PLANKMacServerInformation *)information topology:(NSDictionary *(^)(void))topology {
    if (!identity || !sessions || !information || !topology) return nil;
    struct rlimit core;
    if (getrlimit(RLIMIT_CORE, &core) || core.rlim_cur != 0) return nil;
    self = [super init];
    if (self) {
        _identity = sec_identity_create(identity);
        if (!_identity) return nil;
        _sessions = sessions;
        _information = information;
        _topology = [topology copy];
        _requests = [NSMutableSet set];
        _networkQueue = dispatch_queue_create("la.instinctual.PLANK.Host.https", DISPATCH_QUEUE_SERIAL);
        _authQueue = dispatch_queue_create("la.instinctual.PLANK.Host.authentication", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)finish:(PLANKMacHTTPSRequest *)request {
    if (request.finished) return;
    request.finished = YES;
    [request.bytes resetBytesInRange:NSMakeRange(0, request.bytes.length)];
    request.bytes = nil;
    nw_connection_set_state_changed_handler(request.connection, NULL);
    nw_connection_cancel(request.connection);
    [_requests removeObject:request];
}

- (void)replyBytes:(NSData *)bytes type:(NSString *)type token:(NSString *)token
           status:(unsigned)status request:(PLANKMacHTTPSRequest *)request {
    if (request.finished) {
        if (token) dispatch_async(_authQueue, ^{ [self->_sessions revokeToken:token]; });
        return;
    }
    NSString *header = [NSString stringWithFormat:@"HTTP/1.1 %u %@\r\nContent-Type: %@\r\nContent-Length: %lu\r\nCache-Control: no-store\r\nPragma: no-cache\r\nConnection: close\r\n\r\n",
        status, status == 200 ? @"OK" : @"Rejected", type, (unsigned long)bytes.length];
    NSMutableData *response = [[header dataUsingEncoding:NSASCIIStringEncoding] mutableCopy];
    [response appendData:bytes];
    dispatch_data_t content = dispatch_data_create(response.bytes, response.length, _networkQueue, ^{
        [response resetBytesInRange:NSMakeRange(0, response.length)];
    });
    __weak typeof(self) weakSelf = self;
    nw_connection_send(request.connection, content, NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT, true,
        ^(nw_error_t error) {
            typeof(self) owner = weakSelf;
            if (error && owner && token)
                dispatch_async(owner->_authQueue, ^{ [owner->_sessions revokeToken:token]; });
            [owner finish:request];
        });
}

- (void)reply:(NSDictionary *)object status:(unsigned)status request:(PLANKMacHTTPSRequest *)request {
    [self replyBytes:[NSJSONSerialization dataWithJSONObject:object options:0 error:NULL]
               type:@"application/json" token:object[@"session_token"] status:status request:request];
}

- (void)handlePath:(NSString *)path body:(NSMutableData *)body request:(PLANKMacHTTPSRequest *)request {
    // Body and Foundation's transient JSON values never enter a log. Mutable
    // buffers are wiped; framework-managed NSString copies cannot be promised
    // erased. Bound them to this per-request autorelease pool.
    @autoreleasepool {
        @try {
            if (request.finished) return;
            id value = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
            NSDictionary *reply = @{@"state": @"denied"};
            unsigned status = 400;
            if ([value isKindOfClass:NSDictionary.class]) {
                if ([path isEqual:@"/plank/auth/start"] && [value count] == 1 &&
                    [value[@"username"] isKindOfClass:NSString.class]) {
                    reply = [_sessions startForPeer:request.peer username:value[@"username"]];
                    status = 200;
                } else if ([path isEqual:@"/plank/auth/respond"] && [value count] == 2 &&
                    [value[@"conversation_id"] isKindOfClass:NSString.class] &&
                    [value[@"responses"] isKindOfClass:NSArray.class] && [value[@"responses"] count] == 1 &&
                    [value[@"responses"][0] isKindOfClass:NSString.class]) {
                    NSMutableData *password = [[value[@"responses"][0] dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
                    reply = [_sessions respondForPeer:request.peer conversation:value[@"conversation_id"] password:password];
                    status = 200;
                }
            }
            dispatch_async(_networkQueue, ^{ [self reply:reply status:status request:request]; });
        } @catch (NSException *exception) {
            (void)exception;
            dispatch_async(_networkQueue, ^{ [self reply:@{@"state": @"denied"} status:400 request:request]; });
        } @finally {
            [body resetBytesInRange:NSMakeRange(0, body.length)];
            dispatch_async(_networkQueue, ^{ self->_authBusy = NO; });
        }
    }
}

- (void)receive:(PLANKMacHTTPSRequest *)request {
    if (request.finished || request.dispatched) return;
    __weak typeof(self) weakSelf = self;
    nw_connection_receive(request.connection, 1, 4096,
        ^(dispatch_data_t content, nw_content_context_t context, bool complete, nw_error_t error) {
            (void)context;
            typeof(self) owner = weakSelf;
            if (!owner || request.finished) return;
            if (error) { [owner finish:request]; return; }
            if (content) dispatch_data_apply(content, ^bool(dispatch_data_t region, size_t offset, const void *bytes, size_t size) {
                (void)region; (void)offset;
                [request.bytes appendBytes:bytes length:size];
                return true;
            });
            NSString *path, *method, *authorization;
            NSRange range;
            PLANKMacHTTPParseResult result = PLANKMacParseControlRequest(request.bytes, &method, &path, &range, &authorization);
            if (result == PLANKMacHTTPInvalid) {
                [owner reply:@{@"state": @"denied"} status:400 request:request];
            } else if (result == PLANKMacHTTPComplete) {
                request.dispatched = YES;
                if ([method isEqual:@"GET"]) {
                    if (PLANKMacIsServerInformationTarget(path) && owner->_serverInformationXML) {
                        [owner replyBytes:owner->_serverInformationXML type:@"application/xml; charset=utf-8"
                                    token:nil status:200 request:request];
                    } else if (PLANKMacIsTopologyTarget(path)) {
                        if (owner->_authBusy) { [owner reply:@{@"state": @"denied"} status:503 request:request]; return; }
                        [request.bytes resetBytesInRange:NSMakeRange(0, request.bytes.length)];
                        request.bytes = nil;
                        owner->_authBusy = YES;
                        dispatch_async(owner->_authQueue, ^{
                            @autoreleasepool {
                                NSDictionary *topology = nil;
                                unsigned status = 401;
                                @try {
                                    NSString *token = [authorization hasPrefix:@"Bearer "] && authorization.length == 51 ?
                                        [authorization substringFromIndex:7] : nil;
                                    PLANKMacAccountIdentity before = {0}, after = {0};
                                    if (token && [owner->_sessions authorizeToken:token peer:request.peer identity:&before]) {
                                        topology = owner->_topology();
                                        status = topology ? 200 : 503;
                                        if (![owner->_sessions authorizeToken:token peer:request.peer identity:&after] ||
                                            before.uid != after.uid || memcmp(before.uuid, after.uuid, sizeof(before.uuid))) {
                                            topology = nil; status = 401;
                                        }
                                    }
                                } @catch (NSException *exception) {
                                    (void)exception; topology = nil; status = 503;
                                }
                                dispatch_async(owner->_networkQueue, ^{
                                    [owner reply:topology ?: @{@"state": @"denied"} status:status request:request];
                                    owner->_authBusy = NO;
                                });
                            }
                        });
                    } else [owner reply:@{@"state": @"denied"} status:404 request:request];
                    return;
                }
                if (owner->_authBusy) {
                    [owner reply:@{@"state": @"denied"} status:503 request:request];
                    return;
                }
                if (![path isEqual:@"/plank/auth/start"] && ![path isEqual:@"/plank/auth/respond"]) {
                    [owner reply:@{@"state": @"denied"} status:404 request:request];
                    return;
                }
                NSMutableData *body = [NSMutableData dataWithBytes:(const char *)request.bytes.bytes + range.location length:range.length];
                [request.bytes resetBytesInRange:NSMakeRange(0, request.bytes.length)];
                request.bytes = nil;
                owner->_authBusy = YES;
                dispatch_async(owner->_authQueue, ^{ [owner handlePath:path body:body request:request]; });
            } else if (complete) {
                [owner finish:request];
            } else [owner receive:request];
        });
}

- (void)accept:(nw_connection_t)connection {
    if (_stopped || _requests.count >= 8) { nw_connection_cancel(connection); return; }
    nw_endpoint_t endpoint = nw_connection_copy_endpoint(connection);
    const struct sockaddr *address = nw_endpoint_get_address(endpoint);
    NSData *peer = nil;
    if (address && address->sa_family == AF_INET) {
        peer = [NSData dataWithBytes:&((const struct sockaddr_in *)address)->sin_addr length:4];
    } else if (address && address->sa_family == AF_INET6) {
        const struct in6_addr *ip = &((const struct sockaddr_in6 *)address)->sin6_addr;
        peer = IN6_IS_ADDR_V4MAPPED(ip) ? [NSData dataWithBytes:ip->s6_addr + 12 length:4] :
            [NSData dataWithBytes:ip length:16];
    }
    if (!peer) { nw_connection_cancel(connection); return; }
    PLANKMacHTTPSRequest *request = [PLANKMacHTTPSRequest new];
    request.connection = connection;
    request.peer = peer;
    request.bytes = [NSMutableData data];
    request.deadline = clock_gettime_nsec_np(CLOCK_MONOTONIC) + 5 * NSEC_PER_SEC;
    [_requests addObject:request];
    nw_connection_set_queue(connection, _networkQueue);
    __weak typeof(self) weakSelf = self;
    nw_connection_set_state_changed_handler(connection, ^(nw_connection_state_t state, nw_error_t error) {
        (void)error;
        if (state == nw_connection_state_ready) [weakSelf receive:request];
        else if (state == nw_connection_state_failed || state == nw_connection_state_cancelled) [weakSelf finish:request];
    });
    nw_connection_start(connection);
}

- (BOOL)startOnAddress:(NSString *)address port:(uint16_t)port ready:(void (^)(uint16_t))ready {
    struct in_addr ip;
    if (_listener || _stopped || !ready || inet_pton(AF_INET, address.UTF8String, &ip) != 1) return NO;
    sec_identity_t identity = _identity;
    nw_parameters_t parameters = nw_parameters_create_secure_tcp(^(nw_protocol_options_t tls) {
        sec_protocol_options_t security = nw_tls_copy_sec_protocol_options(tls);
        sec_protocol_options_set_local_identity(security, identity);
        sec_protocol_options_set_min_tls_protocol_version(security, tls_protocol_version_TLSv13);
        sec_protocol_options_set_max_tls_protocol_version(security, tls_protocol_version_TLSv13);
        sec_protocol_options_add_tls_application_protocol(security, "http/1.1");
    }, NW_PARAMETERS_DEFAULT_CONFIGURATION);
    nw_parameters_set_local_endpoint(parameters, nw_endpoint_create_host(address.UTF8String,
        [NSString stringWithFormat:@"%u", port].UTF8String));
    _listener = nw_listener_create(parameters);
    if (!_listener) return NO;
    nw_listener_set_queue(_listener, _networkQueue);
    __weak typeof(self) weakSelf = self;
    nw_listener_set_new_connection_handler(_listener, ^(nw_connection_t connection) { [weakSelf accept:connection]; });
    nw_listener_set_state_changed_handler(_listener, ^(nw_listener_state_t state, nw_error_t error) {
        (void)error;
        typeof(self) owner = weakSelf;
        if (!owner) return;
        if (state == nw_listener_state_ready) {
            uint16_t boundPort = nw_listener_get_port(owner->_listener);
            owner->_serverInformationXML = [owner->_information XMLForControlPort:boundPort];
            if (!owner->_serverInformationXML) { [owner stop]; return; }
            ready(boundPort);
        }
        else if (state == nw_listener_state_failed) [owner stop];
    });
    // One watchdog for at most eight admitted requests. Do not retain a timer
    // closure for every completed/rejected connection during a request flood.
    _expiryTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _networkQueue);
    dispatch_source_set_timer(_expiryTimer, DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(_expiryTimer, ^{
        typeof(self) owner = weakSelf;
        if (!owner) return;
        uint64_t now = clock_gettime_nsec_np(CLOCK_MONOTONIC);
        for (PLANKMacHTTPSRequest *request in owner->_requests.allObjects)
            if (request.deadline <= now) [owner finish:request];
    });
    dispatch_resume(_expiryTimer);
    nw_listener_start(_listener);
    return YES;
}

- (void)stop {
    dispatch_async(_networkQueue, ^{
        self->_stopped = YES;
        if (self->_listener) nw_listener_cancel(self->_listener);
        if (self->_expiryTimer) dispatch_source_cancel(self->_expiryTimer);
        for (PLANKMacHTTPSRequest *request in self->_requests.allObjects) [self finish:request];
        // Serialized after any in-flight verification: no token survives stop.
        dispatch_async(self->_authQueue, ^{ [self->_sessions revokeAll]; });
    });
}

- (void)dealloc {
    if (_expiryTimer) dispatch_source_cancel(_expiryTimer);
    if (_listener) nw_listener_cancel(_listener);
    for (PLANKMacHTTPSRequest *request in _requests) {
        [request.bytes resetBytesInRange:NSMakeRange(0, request.bytes.length)];
        nw_connection_set_state_changed_handler(request.connection, NULL);
        nw_connection_cancel(request.connection);
    }
}
@end
