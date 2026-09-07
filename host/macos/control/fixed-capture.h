// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Authenticated metadata only. Caller must recheck desktop authority before
// and after snapshot. This neither starts capture nor grants remote input.
@interface PLANKMacFixedCapture : NSObject
- (NSDictionary *)snapshot;
@end

// Shared serializer also used by synthetic tests, never a source of authority.
NSDictionary *PLANKMacFixedCaptureDescription(NSString *generation, NSString *identifier,
    size_t width, size_t height, CGRect logicalBounds);
