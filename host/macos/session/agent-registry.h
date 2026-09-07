// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>
#import <xpc/xpc.h>

typedef NS_ENUM(uint32_t, PLANKMacAgentPhase) {
    PLANKMacAgentUnavailable, PLANKMacAgentLoginWindow, PLANKMacAgentDesktop
};

// Kernel-supplied peer identity, never fields supplied by the agent message.
typedef struct { uid_t uid; pid_t pid; uint32_t auditSession; } PLANKMacAgentPeer;
// Trusted machine observation. This does not authenticate a remote user or
// replace the graphical agent's own on-console/session/permission checks.
typedef PLANKMacAgentPhase (^PLANKMacAgentScope)(PLANKMacAgentPeer);
PLANKMacAgentPhase PLANKMacObserveAgentScope(PLANKMacAgentPeer peer);
NSString *PLANKMacOwnSigningRequirement(void);

@interface PLANKMacAgentLease : NSObject
@property(readonly) PLANKMacAgentPeer peer;
@property(readonly) PLANKMacAgentPhase phase;
@property(readonly) uint64_t generation;
@property(readonly) BOOL active;
@end

typedef NS_ENUM(unsigned, PLANKMacAgentEvent) {
    PLANKMacAgentAttached, PLANKMacAgentRevoked,
    PLANKMacAgentRetired, PLANKMacAgentLost
};

// All calls/callbacks belong on the supplied serial queue. No network listener,
// capture, input, process launcher or password handling lives here. An attached
// local agent is NOT a remote user's capture/input authorization.
@interface PLANKMacAgentRegistry : NSObject
- (instancetype)initWithQueue:(dispatch_queue_t)queue
                 requirement:(NSString *)requirement scope:(PLANKMacAgentScope)scope
                       event:(void (^)(PLANKMacAgentLease *, PLANKMacAgentEvent))event;
// Takes a newly accepted, inactive XPC peer. Sets per-message signing policy
// before activation. Admission is bounded; every rejected peer is cancelled.
- (void)accept:(xpc_connection_t)peer;
// Called on console/lock/ownership invalidation before stopping media/input.
- (void)revoke;
// Recheck current OS scope. Scope loss latches; it never re-arms a lease.
- (void)refresh;
// Only the trusted controller may release the exclusive slot AFTER old
// media/input/display cleanup is verified. XPC loss/retired alone cannot do it.
- (BOOL)completeRetirement:(PLANKMacAgentLease *)lease;
- (void)stop;
@end
