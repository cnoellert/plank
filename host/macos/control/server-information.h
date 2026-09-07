// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>

// Public, immutable discovery metadata. No account, desktop geometry, token,
// hardware serial number or active-session state belongs in this object.
// The installer/service must supply its persisted workstation UUID; do not
// derive it from an account or regenerate it for every graphical agent.
@interface PLANKMacServerInformation : NSObject
- (instancetype)initWithName:(NSString *)name workstationUUID:(NSUUID *)uuid
                    version:(NSString *)version;
- (NSData *)XMLForControlPort:(uint16_t)port;
@end

// Accept current Client cache-busting identifiers, not credentials or arbitrary
// query parameters. These optional values are ignored, never authorization.
BOOL PLANKMacIsServerInformationTarget(NSString *target);
BOOL PLANKMacIsTopologyTarget(NSString *target);
