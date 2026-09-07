// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import "input-events.h"
#import "authentication-session.h"
#include "plank_transport.h"

// Authorized delivery of an already received native InputPacket. The capture
// owner drains the existing input API on its serial queue (no extra worker).
// Endpoint, mapper and desktop validity must describe the same captured lease.
@interface PLANKMacNativeInput : NSObject
- (instancetype)initWithEndpoint:(PlankTransportNativeEndpoint *)endpoint
                        sessions:(PLANKMacAuthenticationSession *)sessions
                           lease:(PLANKMacStreamLease *)lease
                          events:(PLANKMacInputEvents *)events
                        validity:(BOOL (^)(void))validity
                         deliver:(void (^)(CGEventRef))deliver;
// deliver is an internal, bounded/nonblocking sink (event posting, not a UI
// callback). Only it executes under lease revocation serialization. Never log
// event contents. time is the local monotonic clock, not untrusted packet data.
- (PLANKMacInputResult)consumeType:(uint8_t)type payload:(NSData *)payload time:(uint64_t)time;
// Call BEFORE ending the lease on an orderly disconnect. Releases are attempted
// only while the same desktop/topology is still authorized, even if QUIC closed.
// After ownership loss, discard instead of posting releases into the next user.
// Returns the count submitted, not proof of OS receipt. Always latches stop.
- (NSUInteger)stop;
@end
