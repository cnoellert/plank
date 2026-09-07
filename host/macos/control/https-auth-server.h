// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "authentication-session.h"
#import "server-information.h"

// Native TLS 1.3 discovery/authentication/authorized-topology adapter.
// No pixel capture/input endpoint. Topology provider must be bounded and must
// not change displays. It runs only after auth and is followed by an owner recheck.
// Caller supplies an administrator-controlled TLS identity and explicit local
// IPv4 bind address/port; no implicit wildcard and no insecure fallback.
// Core dumps must already be disabled before construction. Stop before release.
@interface PLANKMacHTTPSAuthServer : NSObject
- (instancetype)initWithIdentity:(SecIdentityRef)identity sessions:(PLANKMacAuthenticationSession *)sessions
                    information:(PLANKMacServerInformation *)information
                       topology:(NSDictionary *(^)(void))topology;
- (BOOL)startOnAddress:(NSString *)address port:(uint16_t)port
                ready:(void (^)(uint16_t boundPort))ready;
- (void)stop;
@end
