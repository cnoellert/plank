// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "authentication-session.h"
#import "server-information.h"

// Optional authenticated launch adapter. It must validate the exact request,
// consume the token into a lease, retain/start its stream owner and return only
// the launch manifest. It runs on the bounded auth lane, never the network loop.
// QUIC must bind the supplied control port and use the same certificate as TLS.
typedef NSDictionary *(^PLANKMacLaunchHandler)(NSDictionary *request, NSString *token,
    NSData *peer, uint16_t port, unsigned *status);

// Native TLS 1.3 discovery/authentication/authorized-topology adapter.
// No implicit streaming capability. A nil launch handler leaves launch absent.
// Topology provider must be bounded and must
// not change displays. It runs only after auth and is followed by an owner recheck.
// Caller supplies an administrator-controlled TLS identity and explicit local
// IPv4 bind address/port; no implicit wildcard and no insecure fallback.
// Core dumps must already be disabled before construction. Stop before release.
@interface PLANKMacHTTPSAuthServer : NSObject
// Configure before start. Runs on the bounded auth lane; authenticates before
// dispatch and rechecks ownership before returning any display description.
@property(copy) PLANKMacLaunchHandler prepareDisplay;
- (instancetype)initWithIdentity:(SecIdentityRef)identity sessions:(PLANKMacAuthenticationSession *)sessions
                    information:(PLANKMacServerInformation *)information
                       topology:(NSDictionary *(^)(void))topology
                         launch:(PLANKMacLaunchHandler)launch;
- (BOOL)startOnAddress:(NSString *)address port:(uint16_t)port
                ready:(void (^)(uint16_t boundPort))ready;
- (BOOL)startOnAddress:(NSString *)address port:(uint16_t)port
                ready:(void (^)(uint16_t boundPort))ready failed:(void (^)(void))failed;
- (void)stop;
// Completes after admitted authentication/launch work and reply scheduling have
// drained. Callback runs on the network queue, not the main/UI queue.
- (void)stopWithCompletion:(void (^)(void))completion;
@end
