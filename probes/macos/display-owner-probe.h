// SPDX-License-Identifier: GPL-3.0-or-later
// Private, bounded feasibility IPC; not a product service or public endpoint.
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

int PLANKRunDisplayOwner(unsigned int width, unsigned int height, BOOL handoff);

@interface PLANKDisplayOwnerProbe : NSObject
@property(nonatomic, readonly) CGDirectDisplayID displayID;
@property(nonatomic, readonly) BOOL running;
@property(nonatomic) BOOL handoffQualification;
- (BOOL)startWidth:(unsigned int)width height:(unsigned int)height;
- (BOOL)stop;
- (BOOL)crashForQualification;
@end
