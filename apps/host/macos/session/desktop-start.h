// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>

// Startup scheduling only. This grants no graphical or remote-user authority.
typedef struct { uint32_t uid, audit; unsigned attempts; BOOL finished; } PLANKMacDesktopStartState;
BOOL PLANKMacDesktopStartObserve(PLANKMacDesktopStartState *state, NSDictionary *console);
BOOL PLANKMacDesktopStartNext(PLANKMacDesktopStartState *state);

// Main-queue object owned by the existing root coordinator. No extra service.
@interface PLANKMacDesktopStart : NSObject
- (BOOL)start;
- (void)stop;
@end
