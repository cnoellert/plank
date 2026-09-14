// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import "agent-registry.h"

typedef NS_ENUM(unsigned, PLANKMacAgentConnectionState) {
    PLANKMacAgentConnecting, PLANKMacAgentReady, PLANKMacAgentRetiring,
    PLANKMacAgentFinished, PLANKMacAgentDisconnected
};

// Graphical-agent side of the machine IPC boundary. Except bindGraphicalScope,
// operations and callbacks use the supplied serial queue. The caller supplies its latched local
// session/permission predicate; IPC registration alone never grants remote input.
@interface PLANKMacAgentConnection : NSObject
- (instancetype)initWithPeer:(xpc_connection_t)peer queue:(dispatch_queue_t)queue
                requirement:(NSString *)requirement serverUID:(uid_t)uid
                      phase:(PLANKMacAgentPhase)phase valid:(BOOL (^)(void))valid
                      event:(void (^)(PLANKMacAgentConnectionState, uint64_t))event;
- (BOOL)start;
// Rechecks local scope and freshness; false latches retirement/disconnection.
- (BOOL)authorized;
// The sole cross-queue operation: bind a freshly checked, trusted local scope
// to this machine admission. For the authentication owner's snapshot callback.
// No dispatch_sync, directory lookup or owner callback while holding its lock.
// Expiry/local-scope loss latches even if the IPC queue is stalled; a late reply
// cannot renew it. Does not authenticate a user or independently sample the OS.
- (PLANKMacGraphicalIdentity)bindGraphicalScope:(PLANKMacGraphicalIdentity)scope;
- (void)revoke;
// Call AFTER local capture/input/display cleanup, never just on revocation.
- (void)retire;
- (void)stop;
@end
