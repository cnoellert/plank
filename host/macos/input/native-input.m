// SPDX-License-Identifier: GPL-3.0-or-later
#import "native-input.h"

@implementation PLANKMacNativeInput {
    PlankTransportNativeEndpoint *_endpoint;
    PLANKMacAuthenticationSession *_sessions;
    PLANKMacStreamLease *_lease;
    PLANKMacInputEvents *_events;
    BOOL (^_validity)(void);
    void (^_deliver)(CGEventRef);
    BOOL _stopped;
}
- (instancetype)init { return nil; }
- (instancetype)initWithEndpoint:(PlankTransportNativeEndpoint *)endpoint
                        sessions:(PLANKMacAuthenticationSession *)sessions
                           lease:(PLANKMacStreamLease *)lease
                          events:(PLANKMacInputEvents *)events
                        validity:(BOOL (^)(void))validity
                         deliver:(void (^)(CGEventRef))deliver {
    if (!endpoint || !sessions || !lease || !events || !validity || !deliver) return nil;
    self = [super init];
    if (self) {
        _endpoint = endpoint; _sessions = sessions; _lease = lease; _events = events;
        _validity = [validity copy]; _deliver = [deliver copy];
    }
    return self;
}
- (PLANKMacInputResult)consumeType:(uint8_t)type payload:(NSData *)payload time:(uint64_t)time {
    if (_stopped) return PLANKMacInputStopped;
    PLANKMacAccountIdentity identity = {0};
    if (![_sessions authorizeStreamLease:_lease identity:&identity] || !_validity() ||
        plank_transport_native_endpoint_state(_endpoint) != PLANK_TRANSPORT_STATE_READY) {
        _stopped = YES; return PLANKMacInputDenied;
    }
    // Event construction is outside the auth lock. Recheck authority immediately
    // before bounded delivery, linearized with end/revoke. No event queue/retry.
    PLANKMacInputResult result = [_events consumeType:type payload:payload time:time accept:^BOOL(CGEventRef event) {
        return [self deliverAuthorized:event];
    }];
    if (result == PLANKMacInputDenied || result == PLANKMacInputStopped) _stopped = YES;
    return result;
}
- (BOOL)deliverAuthorized:(CGEventRef)event {
    __block BOOL delivered = NO;
    [_sessions performWithStreamLease:_lease action:^{
        if (self->_validity() && plank_transport_native_endpoint_state(self->_endpoint) == PLANK_TRANSPORT_STATE_READY) {
            self->_deliver(event); delivered = YES;
        }
    }];
    return delivered;
}
- (uint64_t)nextRepeatTime { return _stopped ? 0 : _events.nextRepeatTime; }
- (PLANKMacInputResult)repeatAtTime:(uint64_t)time {
    if (_stopped) return PLANKMacInputStopped;
    PLANKMacAccountIdentity identity = {0};
    if (![_sessions authorizeStreamLease:_lease identity:&identity] || !_validity() ||
        plank_transport_native_endpoint_state(_endpoint) != PLANK_TRANSPORT_STATE_READY) {
        _stopped = YES; return PLANKMacInputDenied;
    }
    PLANKMacInputResult result = [_events repeatAtTime:time accept:^BOOL(CGEventRef event) {
        return [self deliverAuthorized:event];
    }];
    if (result == PLANKMacInputDenied || result == PLANKMacInputStopped) _stopped = YES;
    return result;
}
- (NSUInteger)stop {
    _stopped = YES;
    NSArray *events = [_events stopAndCopyReleaseEvents];
    __block NSUInteger count = 0;
    for (id event in events) {
        // Each release rechecks the current authority; stop cannot clear a key
        // in a new session merely because it was held in a previous session.
        if (![_sessions performWithStreamLease:_lease action:^{
            if (self->_validity()) {
                self->_deliver((__bridge CGEventRef)event); ++count;
            }
        }]) break;
    }
    return count;
}
@end
