// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>

// Startup scheduling only. This grants no graphical or remote-user authority.
typedef struct {
    uint32_t uid, audit;
    unsigned attempts;
    BOOL finished, workerExited;
} PLANKMacDesktopStartState;
BOOL PLANKMacDesktopStartObserve(PLANKMacDesktopStartState *state, NSDictionary *console);
BOOL PLANKMacDesktopStartNext(PLANKMacDesktopStartState *state);
void PLANKMacDesktopStartComplete(PLANKMacDesktopStartState *state, uint32_t uid, uint32_t audit, BOOL success);
BOOL PLANKMacDesktopStartExited(PLANKMacDesktopStartState *state, uint32_t uid, uint32_t audit);
unsigned PLANKMacDesktopStartRetrySeconds(const PLANKMacDesktopStartState *state);

// Main-queue object owned by the existing root coordinator. No extra service.
@interface PLANKMacDesktopStart : NSObject
- (BOOL)start;
// Call only after the coordinator observes the admitted desktop process exit
// and releases its exact lease. Never an IPC retirement request or peer error.
- (void)desktopProcessExitedForUID:(uint32_t)uid audit:(uint32_t)audit;
- (void)stop;
@end
