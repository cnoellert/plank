// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import "input-events.h"

// The graphical agent supplies this device, never a network request. Tests
// replace it with a non-posting sink; production uses the public Quartz path.
@protocol PLANKMacInputDevice <NSObject>
- (PLANKMacInputEvents *)eventsForTopology:(NSDictionary *)topology;
- (BOOL)available;
- (void)postEvent:(CGEventRef)event;
@end

// Requires existing Device Control/Accessibility consent. No prompt, root
// helper, permission bypass, global event tap or private capture API.
@interface PLANKMacQuartzInput : NSObject <PLANKMacInputDevice>
@end

// Bounded product response to the OS acceleration preference, not Apple's
// hardware acceleration curve. Exposed for non-posting qualification only.
double PLANKMacScrollLinesForPreference(CFTypeRef value);
