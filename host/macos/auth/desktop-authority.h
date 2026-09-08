// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>
#include "account-policy.h"

// Desktop-preview authority: create in the actual logged-in Aqua agent, not
// SSH/a root network daemon. Never re-arms after revocation; replace the agent.
@interface PLANKMacDesktopAuthority : NSObject
- (PLANKMacGraphicalIdentity)snapshot;
- (void)revoke;
@end
