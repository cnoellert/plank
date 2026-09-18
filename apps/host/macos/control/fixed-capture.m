// SPDX-License-Identifier: GPL-3.0-or-later
#import "fixed-capture.h"
#include <math.h>
#include <stdatomic.h>

// One process-lifetime observer; no object pointer can outlive its owner and
// no polling thread or per-frame WindowServer query is introduced. The low
// bit denotes reconfiguration in progress; other bits identify each event.
static atomic_uint_fast64_t displayRevision = 0;
static BOOL displayObservationAvailable;
static void displayChanged(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *context) {
    (void)display; (void)context;
    uint64_t previous = atomic_load(&displayRevision);
    uint64_t next;
    do {
        next = ((previous + 2) & ~UINT64_C(1)) |
            ((flags & kCGDisplayBeginConfigurationFlag) ? 1 : 0);
    } while (!atomic_compare_exchange_weak(&displayRevision, &previous, next));
}

NSDictionary *PLANKMacEncodingProfile(NSString *mode) {
    BOOL fullChroma = [mode isEqual:@"hevc-10-444-videotoolbox"];
    if (!fullChroma && ![mode isEqual:@"hevc-10-420-videotoolbox"]) return nil;
    return @{@"capture_source": @"screencapturekit", @"encoder_backend": @"videotoolbox",
        @"encoding_mode": mode, @"codec": @"hevc", @"profile": fullChroma ? @"rext" : @"main10",
        @"bit_depth": @10, @"chroma": fullChroma ? @"4:4:4" : @"4:2:0", @"range": @"full",
        @"matrix": @"bt709", @"primaries": @"bt709", @"transfer": @"srgb", @"rgb_identity": @NO};
}

NSDictionary *PLANKMacFixedCaptureDescription(NSString *generation, NSString *identifier,
        size_t width, size_t height, CGRect bounds, NSString *encodingMode) {
    NSDictionary *profile = PLANKMacEncodingProfile(encodingMode);
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:generation];
    if (!profile || !uuid || ![uuid.UUIDString.lowercaseString isEqual:generation] ||
        [generation isEqual:@"00000000-0000-0000-0000-000000000000"] ||
        !identifier.length || identifier.length > 128 || width < 2 || height < 2 ||
        width > 8192 || height > 8192 || width % 2 || height % 2 ||
        !isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) ||
        !isfinite(bounds.size.width) || !isfinite(bounds.size.height) ||
        fabs(bounds.origin.x) > 65536 || fabs(bounds.origin.y) > 65536 ||
        bounds.size.width <= 0 || bounds.size.height <= 0 ||
        bounds.size.width > 65536 || bounds.size.height > 65536) return nil;
    return @{@"schema_version": @13, @"feature_flags": @7864433, @"generation": generation,
        @"capture": @{@"id": identifier, @"width": @(width), @"height": @(height),
            @"logical_bounds": @{@"x": @(bounds.origin.x), @"y": @(bounds.origin.y),
                @"width": @(bounds.size.width), @"height": @(bounds.size.height)},
            @"encoding_profile": profile}};
}

@implementation PLANKMacFixedCapture {
    NSDictionary *_previous;
    NSString *_generation;
    NSString *_unavailableReason;
}
- (NSDictionary *)unavailable:(NSString *)reason {
    if (![_unavailableReason isEqual:reason]) NSLog(@"PLANK capture geometry unavailable: %@", reason);
    _unavailableReason = reason; _previous = nil; _generation = nil;
    return nil;
}
- (instancetype)init {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        displayObservationAvailable = CGDisplayRegisterReconfigurationCallback(displayChanged, NULL) == kCGErrorSuccess;
    });
    if (!displayObservationAvailable) return nil;
    self = [super init];
    if (self) _encodingMode = @"hevc-10-420-videotoolbox";
    return self;
}
- (NSDictionary *)snapshot {
    @synchronized(self) {
        uint64_t revision = atomic_load(&displayRevision);
        if (revision & 1) return [self unavailable:@"display reconfiguration in progress"];
        CGDirectDisplayID selection = self.selectedDisplay;
        NSString *encodingMode = self.encodingMode;
        if (!PLANKMacEncodingProfile(encodingMode)) return [self unavailable:@"unsupported encoding mode"];
        CGDirectDisplayID display = selection ?: CGMainDisplayID();
        if (!display || !CGDisplayIsActive(display)) return [self unavailable:@"selected display is inactive"];
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(display);
        if (!mode) return [self unavailable:@"display mode unavailable"];
        size_t width = CGDisplayModeGetPixelWidth(mode), height = CGDisplayModeGetPixelHeight(mode);
        int32_t modeID = CGDisplayModeGetIODisplayModeID(mode);
        CGDisplayModeRelease(mode);
        CGRect bounds = CGDisplayBounds(display);
        CGDisplayModeRef check = CGDisplayCopyDisplayMode(display);
        BOOL stable = check && selection == self.selectedDisplay && [encodingMode isEqual:self.encodingMode] &&
            display == (selection ?: CGMainDisplayID()) && CGDisplayIsActive(display) &&
            modeID == CGDisplayModeGetIODisplayModeID(check) &&
            width == CGDisplayModeGetPixelWidth(check) && height == CGDisplayModeGetPixelHeight(check) &&
            CGRectEqualToRect(bounds, CGDisplayBounds(display)) &&
            revision == atomic_load(&displayRevision);
        if (check) CGDisplayModeRelease(check);
        if (!stable) return [self unavailable:@"display changed during snapshot"];
        NSString *identifier = [NSString stringWithFormat:@"cgdisplay:%u", display];
        // Refresh/mode identity is part of the generation even if pixel size
        // is unchanged. No guessed point-to-pixel ratio or monitor provenance.
        NSDictionary *fingerprint = @{@"display": @(display), @"mode": @(modeID), @"revision": @(revision),
            @"width": @(width), @"height": @(height), @"encoding_mode": encodingMode,
            @"bounds": [NSValue valueWithRect:NSRectFromCGRect(bounds)]};
        if (![_previous isEqual:fingerprint]) {
            _generation = NSUUID.UUID.UUIDString.lowercaseString;
            _previous = fingerprint;
        }
        NSDictionary *description = PLANKMacFixedCaptureDescription(_generation, identifier, width, height, bounds, encodingMode);
        if (!description) return [self unavailable:@"unsupported pixel or desktop bounds"];
        _unavailableReason = nil;
        return description;
    }
}
@end
