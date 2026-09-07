// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import "account-channel.h"

// Supplied by the trusted graphical-session owner, never by request JSON.
typedef PLANKMacDesktopIdentity (^PLANKMacDesktopSnapshot)(void);

// Existing HTTPS start/respond conversation state for the desktop preview.
// The future HTTPS adapter must enforce TLS, body limits, no-cache responses,
// and obtain the canonical peer IP bytes from its accepted connection (not a
// forwarded header). Calls belong on a background authentication queue.
// This component opens no socket and does not log or retain passwords.
@interface PLANKMacAuthenticationSession : NSObject
- (instancetype)initWithDesktopSnapshot:(PLANKMacDesktopSnapshot)snapshot;
- (NSDictionary *)startForPeer:(NSData *)peer username:(NSString *)username;
- (NSDictionary *)respondForPeer:(NSData *)peer conversation:(NSString *)conversation
                       password:(NSMutableData *)password;
- (BOOL)authorizeToken:(NSString *)token peer:(NSData *)peer
             identity:(PLANKMacAccountIdentity *)identity;
- (void)revokeToken:(NSString *)token;
- (void)revokeAll;
@end
