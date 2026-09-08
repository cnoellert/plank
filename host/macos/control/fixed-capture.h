// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// Authenticated metadata only. Caller must recheck desktop authority before
// and after snapshot. This neither starts capture nor grants remote input.
// Construction fails if display-change observation cannot be installed.
// Every observed reconfiguration changes generation, including change-back.
// The eventual stream owner must compare this generation and stop on change.
@interface PLANKMacFixedCapture : NSObject
// Zero describes the current main display. Nonzero describes only the selected
// owned display, never silently falling back to a different screen.
@property CGDirectDisplayID selectedDisplay;
- (NSDictionary *)snapshot;
@end

// Shared serializer also used by synthetic tests, never a source of authority.
NSDictionary *PLANKMacFixedCaptureDescription(NSString *generation, NSString *identifier,
    size_t width, size_t height, CGRect logicalBounds);
