// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import "agent-registry.h"

typedef NS_ENUM(unsigned, PLANKMacAgentConnectionState) {
    PLANKMacAgentConnecting, PLANKMacAgentReady, PLANKMacAgentRetiring,
    PLANKMacAgentFinished, PLANKMacAgentDisconnected
};

// Graphical-agent side of the machine IPC boundary. All operations and callbacks
// use the supplied serial queue. The trusted caller supplies its latched local
// session/permission predicate; IPC registration alone never grants remote input.
@interface PLANKMacAgentConnection : NSObject
- (instancetype)initWithPeer:(xpc_connection_t)peer queue:(dispatch_queue_t)queue
                requirement:(NSString *)requirement serverUID:(uid_t)uid
                      phase:(PLANKMacAgentPhase)phase valid:(BOOL (^)(void))valid
                      event:(void (^)(PLANKMacAgentConnectionState, uint64_t))event;
- (BOOL)start;
// Rechecks local scope and freshness; false latches retirement/disconnection.
- (BOOL)authorized;
- (void)revoke;
// Call AFTER local capture/input/display cleanup, never just on revocation.
- (void)retire;
- (void)stop;
@end
