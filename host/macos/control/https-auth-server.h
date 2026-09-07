// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import "authentication-session.h"

// Native TLS 1.3 HTTP/1.1 authentication adapter. No capture/input endpoint.
// Caller supplies an administrator-controlled TLS identity and explicit local
// IPv4 bind address/port; no implicit wildcard and no insecure fallback.
// Core dumps must already be disabled before construction. Stop before release.
@interface PLANKMacHTTPSAuthServer : NSObject
- (instancetype)initWithIdentity:(SecIdentityRef)identity sessions:(PLANKMacAuthenticationSession *)sessions;
- (BOOL)startOnAddress:(NSString *)address port:(uint16_t)port
                ready:(void (^)(uint16_t boundPort))ready;
- (void)stop;
@end
