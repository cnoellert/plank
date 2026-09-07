// SPDX-License-Identifier: GPL-3.0-or-later
// Passive public-API inventory: no capture, permission request, or mode change.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

/** Return display geometry without publishing serials or user identity. */
static NSDictionary *describeDisplay(CGDirectDisplayID display) {
    CGRect bounds = CGDisplayBounds(display);
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(display);
    NSMutableDictionary *result = [@{
        @"id": @(display),
        @"main": @(CGDisplayIsMain(display) != 0),
        @"builtin": @(CGDisplayIsBuiltin(display) != 0),
        @"active": @(CGDisplayIsActive(display) != 0),
        @"origin_x": @(bounds.origin.x),
        @"origin_y": @(bounds.origin.y),
        @"bounds_width": @(bounds.size.width),
        @"bounds_height": @(bounds.size.height)
    } mutableCopy];
    if (mode) {
        result[@"mode_width"] = @(CGDisplayModeGetWidth(mode));
        result[@"mode_height"] = @(CGDisplayModeGetHeight(mode));
        result[@"pixel_width"] = @(CGDisplayModeGetPixelWidth(mode));
        result[@"pixel_height"] = @(CGDisplayModeGetPixelHeight(mode));
        result[@"refresh_hz"] = @(CGDisplayModeGetRefreshRate(mode));
        CGDisplayModeRelease(mode);
    }
    return result;
}

/** Emit a bounded, read-only inventory; failures return nonzero. */
int main(void) {
    @autoreleasepool {
        CGDirectDisplayID displays[32];
        uint32_t count = 0;
        CGError status = CGGetOnlineDisplayList(32, displays, &count);
        if (status != kCGErrorSuccess || count >= 32) {
            fprintf(stderr, "Cannot enumerate bounded display list: %d\n", status);
            return 1;
        }
        NSMutableArray *items = [NSMutableArray array];
        for (uint32_t index = 0; index < count; ++index) {
            [items addObject:describeDisplay(displays[index])];
        }
        NSDictionary *report = @{
            @"probe": @"plank-macos-desktop-inventory",
            @"schema_version": @1,
            @"screen_capture_preflight": @(CGPreflightScreenCaptureAccess()),
            @"input_post_preflight": @(CGPreflightPostEventAccess()),
            @"displays": items,
            @"qualification": @"Inventory only; no capture or input tested"
        };
        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:report
            options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
            error:&error];
        if (!json) {
            fprintf(stderr, "Inventory serialization failed\n");
            return 1;
        }
        if (fwrite(json.bytes, 1, json.length, stdout) != json.length ||
            fputc('\n', stdout) == EOF) {
            return 1;
        }
    }
    return 0;
}
