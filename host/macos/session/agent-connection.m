// SPDX-License-Identifier: GPL-3.0-or-later
#import "agent-connection.h"
#include <time.h>

@implementation PLANKMacAgentConnection {
    xpc_connection_t _peer;
    dispatch_queue_t _queue;
    dispatch_source_t _watch;
    uid_t _serverUID;
    PLANKMacAgentPhase _phase;
    BOOL (^_valid)(void);
    void (^_event)(PLANKMacAgentConnectionState, uint64_t);
    PLANKMacAgentConnectionState _state;
    uint64_t _generation, _sequence, _pending, _sentAt, _ackAt;
    BOOL _started, _retireRequested;
}

static uint64_t now(void) { return clock_gettime_nsec_np(CLOCK_MONOTONIC); }
static void discardCreatedPeer(xpc_connection_t peer) {
    // Unlike listener-delivered peers, create*() connections must be activated
    // before their last reference is released, even on constructor rejection.
    xpc_connection_set_event_handler(peer, ^(xpc_object_t event) { (void)event; });
    xpc_connection_cancel(peer);
    xpc_connection_activate(peer);
}
static BOOL number(xpc_object_t message, const char *key, uint64_t *value) {
    xpc_object_t item = xpc_dictionary_get_value(message, key);
    if (!item || xpc_get_type(item) != XPC_TYPE_UINT64) return NO;
    *value = xpc_uint64_get_value(item); return YES;
}

- (instancetype)init { return nil; }
- (instancetype)initWithPeer:(xpc_connection_t)peer queue:(dispatch_queue_t)queue
                 requirement:(NSString *)requirement serverUID:(uid_t)uid
                       phase:(PLANKMacAgentPhase)phase valid:(BOOL (^)(void))valid
                       event:(void (^)(PLANKMacAgentConnectionState, uint64_t))event {
    if (!peer) return nil;
    if (!queue || !valid || !event || uid == (uid_t)-1 ||
        (phase != PLANKMacAgentLoginWindow && phase != PLANKMacAgentDesktop) ||
        !requirement.length || requirement.length > 8192 ||
        strlen(requirement.UTF8String) != [requirement lengthOfBytesUsingEncoding:NSUTF8StringEncoding] ||
        xpc_connection_set_peer_code_signing_requirement(peer, requirement.UTF8String)) {
        discardCreatedPeer(peer); return nil;
    }
    self = [super init];
    if (!self) { discardCreatedPeer(peer); return nil; }
    _peer = peer; _queue = queue; _serverUID = uid; _phase = phase;
    _valid = [valid copy]; _event = [event copy]; _state = PLANKMacAgentConnecting;
    __weak typeof(self) weakSelf = self;
    xpc_connection_set_target_queue(peer, queue);
    xpc_connection_set_event_handler(peer, ^(xpc_object_t message) { [weakSelf receive:message]; });
    // This enables XPC lifecycle/error delivery, not registration or authority.
    // No application request is sent until start validates the local scope.
    xpc_connection_activate(peer);
    return self;
}
- (void)transition:(PLANKMacAgentConnectionState)state {
    if (_state == state || _state == PLANKMacAgentFinished || _state == PLANKMacAgentDisconnected) return;
    _state = state;
    if (state == PLANKMacAgentFinished || state == PLANKMacAgentDisconnected) {
        if (_watch) dispatch_source_cancel(_watch);
        xpc_connection_cancel(_peer);
    }
    _event(state, _generation);
}
- (BOOL)start {
    dispatch_assert_queue(_queue);
    if (_started || _state != PLANKMacAgentConnecting) return NO;
    _started = YES;
    if (!_valid()) { [self stop]; return NO; }
    __weak typeof(self) weakSelf = self;
    _watch = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_watch, DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC, 25 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(_watch, ^{
        typeof(self) owner = weakSelf;
        if (!owner) return;
        if (owner->_pending && now() - owner->_sentAt >= 2 * NSEC_PER_SEC) { [owner stop]; return; }
        if (owner->_state == PLANKMacAgentReady && [owner authorized] && !owner->_pending &&
            now() - owner->_ackAt >= 500 * NSEC_PER_MSEC) [owner send:2];
    });
    dispatch_resume(_watch); [self send:1]; return YES;
}
- (void)send:(uint64_t)operation {
    if (_pending || _state == PLANKMacAgentFinished || _state == PLANKMacAgentDisconnected) return;
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_uint64(message, "version", 1);
    xpc_dictionary_set_uint64(message, "operation", operation);
    if (operation == 1) xpc_dictionary_set_uint64(message, "phase", _phase);
    else {
        if (!_generation || _sequence == UINT64_MAX) { [self stop]; return; }
        xpc_dictionary_set_uint64(message, "generation", _generation);
        xpc_dictionary_set_uint64(message, "sequence", ++_sequence);
    }
    _pending = operation; _sentAt = now();
    __weak typeof(self) weakSelf = self;
    xpc_connection_send_message_with_reply(_peer, message, _queue, ^(xpc_object_t response) {
        [weakSelf reply:response operation:operation];
    });
}
- (void)reply:(xpc_object_t)reply operation:(uint64_t)operation {
    if (_state == PLANKMacAgentFinished || _state == PLANKMacAgentDisconnected) return;
    uint64_t version = 0, status = UINT64_MAX, generation = 0;
    if (_pending != operation || xpc_connection_get_euid(_peer) != _serverUID ||
        xpc_get_type(reply) != XPC_TYPE_DICTIONARY || !number(reply, "version", &version) || version != 1 ||
        !number(reply, "status", &status) || xpc_dictionary_get_count(reply) != (status ? 2u : 3u) ||
        (!status && (!number(reply, "generation", &generation) || !generation))) { [self stop]; return; }
    _pending = 0;
    if (operation == 3) {
        if (status != 2 || _state != PLANKMacAgentRetiring) { [self stop]; return; }
        [self transition:PLANKMacAgentFinished]; return;
    }
    if (status && status != 2) { [self stop]; return; }
    if (!status && operation == 1) _generation = generation;
    else if (!status && generation != _generation) { [self stop]; return; }
    _ackAt = now();
    if (status == 2 || !_valid()) [self revoke];
    else if (_state == PLANKMacAgentConnecting) [self transition:PLANKMacAgentReady];
    // A previously revoked connection can never be revived by a late OK reply.
    if (_retireRequested && _state == PLANKMacAgentRetiring) [self send:3];
}
- (void)receive:(xpc_object_t)message {
    if (_state == PLANKMacAgentFinished || _state == PLANKMacAgentDisconnected) return;
    uint64_t version = 0, operation = 0, generation = 0;
    if (xpc_connection_get_euid(_peer) != _serverUID || xpc_get_type(message) != XPC_TYPE_DICTIONARY ||
        xpc_dictionary_get_count(message) != 3 || !number(message, "version", &version) || version != 1 ||
        !number(message, "operation", &operation) || operation != 4 ||
        !number(message, "generation", &generation) || !_generation || generation != _generation) {
        [self stop]; return;
    }
    [self revoke];
}
- (BOOL)authorized {
    dispatch_assert_queue(_queue);
    if (_state != PLANKMacAgentReady) return NO;
    if (!_valid()) { [self revoke]; return NO; }
    if (now() - _ackAt >= 2 * NSEC_PER_SEC) { [self stop]; return NO; }
    return YES;
}
- (void)revoke {
    dispatch_assert_queue(_queue);
    if (_state == PLANKMacAgentConnecting) [self stop];
    else if (_state == PLANKMacAgentReady) [self transition:PLANKMacAgentRetiring];
}
- (void)retire {
    dispatch_assert_queue(_queue);
    [self revoke];
    if (_state != PLANKMacAgentRetiring) return;
    _retireRequested = YES;
    if (!_pending) [self send:3];
}
- (void)stop { dispatch_assert_queue(_queue); [self transition:PLANKMacAgentDisconnected]; }
- (void)dealloc {
    if (_watch) dispatch_source_cancel(_watch);
    if (_peer) xpc_connection_cancel(_peer);
}
@end
