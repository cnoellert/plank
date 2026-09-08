// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import "https-auth-server.h"
#import "preview-session.h"

// A graphical Host's actual control + A/V/input runtime, not a test server.
// The supervisor/agent supplies an admission-bound graphical snapshot. Only
// authenticated launch starts media; one stream may exist at a time.
// Certificate paths must name the SAME identity supplied to HTTPS and belong
// to this role. Never give a desktop agent the machine coordinator's private key.
// Factories permit non-posting/synthetic qualification without a second launch
// implementation; the application supplies ScreenCapture and QuartzInput.
@interface PLANKMacHostRuntime : NSObject
- (instancetype)initWithIdentity:(SecIdentityRef)identity
                     information:(PLANKMacServerInformation *)information
                        snapshot:(PLANKMacGraphicalSnapshot)snapshot
                        topology:(NSDictionary *(^)(void))topology
                         address:(NSString *)address
                     certificate:(NSString *)certificate privateKey:(NSString *)privateKey
                         capture:(id<PLANKMacPreviewCapture> (^)(void))capture
                           input:(id<PLANKMacInputDevice> (^)(void))input;
// Start exactly once, after machine admission. Port zero is for qualification.
- (BOOL)startOnPort:(uint16_t)port ready:(void (^)(uint16_t))ready failed:(void (^)(void))failed;
// Immediately closes launch admission. Completion waits for authentication,
// capture, encoder, input receiver and native endpoint destruction. No main-
// thread wait and no fixed delay in place of completion. Safe to call repeatedly.
- (void)stopWithCompletion:(void (^)(void))completion;
@end
