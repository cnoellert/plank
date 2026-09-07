// SPDX-License-Identifier: GPL-3.0-or-later
#import "fixed-capture.h"
#include <math.h>

NSDictionary *PLANKMacFixedCaptureDescription(NSString *generation, NSString *identifier,
        size_t width, size_t height, CGRect bounds) {
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:generation];
    if (!uuid || ![uuid.UUIDString.lowercaseString isEqual:generation] ||
        [generation isEqual:@"00000000-0000-0000-0000-000000000000"] ||
        !identifier.length || identifier.length > 128 || width < 2 || height < 2 ||
        width > 8192 || height > 8192 || width % 2 || height % 2 ||
        !isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) ||
        !isfinite(bounds.size.width) || !isfinite(bounds.size.height) ||
        fabs(bounds.origin.x) > 65536 || fabs(bounds.origin.y) > 65536 ||
        bounds.size.width <= 0 || bounds.size.height <= 0 ||
        bounds.size.width > 65536 || bounds.size.height > 65536) return nil;
    return @{@"schema_version": @13, @"feature_flags": @524401, @"generation": generation,
        @"capture": @{@"id": identifier, @"width": @(width), @"height": @(height),
            @"logical_bounds": @{@"x": @(bounds.origin.x), @"y": @(bounds.origin.y),
                @"width": @(bounds.size.width), @"height": @(bounds.size.height)},
            @"encoding_profile": @{@"capture_source": @"screencapturekit", @"encoder_backend": @"videotoolbox",
                @"encoding_mode": @"hevc-10-420-videotoolbox", @"codec": @"hevc", @"profile": @"main10",
                @"bit_depth": @10, @"chroma": @"4:2:0", @"range": @"limited", @"matrix": @"bt709",
                @"primaries": @"bt709", @"transfer": @"srgb", @"rgb_identity": @NO}}};
}

@implementation PLANKMacFixedCapture {
    NSDictionary *_previous;
    NSString *_generation;
}
- (NSDictionary *)snapshot {
    @synchronized(self) {
        CGDirectDisplayID display = CGMainDisplayID();
        if (!display || !CGDisplayIsActive(display)) { _previous = nil; _generation = nil; return nil; }
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(display);
        if (!mode) { _previous = nil; _generation = nil; return nil; }
        size_t width = CGDisplayModeGetPixelWidth(mode), height = CGDisplayModeGetPixelHeight(mode);
        int32_t modeID = CGDisplayModeGetIODisplayModeID(mode);
        CGDisplayModeRelease(mode);
        CGRect bounds = CGDisplayBounds(display);
        CGDisplayModeRef check = CGDisplayCopyDisplayMode(display);
        BOOL stable = check && display == CGMainDisplayID() && CGDisplayIsActive(display) &&
            modeID == CGDisplayModeGetIODisplayModeID(check) &&
            width == CGDisplayModeGetPixelWidth(check) && height == CGDisplayModeGetPixelHeight(check) &&
            CGRectEqualToRect(bounds, CGDisplayBounds(display));
        if (check) CGDisplayModeRelease(check);
        if (!stable) { _previous = nil; _generation = nil; return nil; }
        NSString *identifier = [NSString stringWithFormat:@"cgdisplay:%u", display];
        // Refresh/mode identity is part of the generation even if pixel size
        // is unchanged. No guessed point-to-pixel ratio or monitor provenance.
        NSDictionary *fingerprint = @{@"display": @(display), @"mode": @(modeID),
            @"width": @(width), @"height": @(height), @"bounds": [NSValue valueWithRect:NSRectFromCGRect(bounds)]};
        if (![_previous isEqual:fingerprint]) {
            _generation = NSUUID.UUID.UUIDString.lowercaseString;
            _previous = fingerprint;
        }
        return PLANKMacFixedCaptureDescription(_generation, identifier, width, height, bounds);
    }
}
@end
