// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import "quartz-input.h"
// Synthetic tests only. Never linked into the signed real-account app.
@interface PLANKFakeInput : NSObject <PLANKMacInputDevice>
@property(atomic) BOOL availableFlag;
@property(atomic) unsigned delivered, releases;
@end
