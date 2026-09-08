// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// One experimental virtual display per graphical-agent lifetime. No root
// helper, public socket or physical-display mode mutation. Agent process exit
// is the removal boundary on SDK 27; do not pretend releasing the object removes it.
@interface PLANKMacDesktopDisplay : NSObject
@property(nonatomic, readonly) CGDirectDisplayID displayID;
- (void)prepareWidth:(unsigned)width height:(unsigned)height
              valid:(BOOL (^)(void))valid completion:(void (^)(BOOL))completion;
@end
BOOL PLANKMacDesktopModeSupported(unsigned width, unsigned height);
