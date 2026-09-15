// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// One experimental virtual display per graphical-agent lifetime. No root
// helper, public socket or physical-display mode mutation. Agent process exit
// is the removal boundary on SDK 27; do not pretend releasing the object removes it.
@interface PLANKMacDesktopDisplay : NSObject
// Distinct display identity, with the same selectable modes as the desktop.
- (instancetype)initForSignIn;
@property(nonatomic, readonly) CGDirectDisplayID displayID;
- (void)prepareWidth:(unsigned)width height:(unsigned)height
              valid:(BOOL (^)(void))valid completion:(void (^)(BOOL))completion;
// Authenticated recovery only. Reuse our display and last successful mode;
// never create another display or change a physical display's mode.
- (void)recoverWithValidity:(BOOL (^)(void))valid completion:(void (^)(BOOL))completion;
@end
BOOL PLANKMacDesktopModeSupported(unsigned width, unsigned height);
