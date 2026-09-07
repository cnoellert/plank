// SPDX-License-Identifier: GPL-3.0-or-later
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <math.h>
#import "fixed-capture.h"
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSData *data = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
        assert(data);
        NSDictionary *fixture = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        NSString *generation = @"98454815-80ab-4a88-b187-92f59353afca";
        CGRect bounds = CGRectMake(-1920, 0, 1920, 1080);
        assert([fixture isEqual:PLANKMacFixedCaptureDescription(generation, @"cgdisplay:42", 3840, 2160, bounds)]);
        for (NSNumber *bad in @[@0, @1, @3, @8193, @(SIZE_MAX)]) {
            assert(!PLANKMacFixedCaptureDescription(generation, @"id", bad.unsignedLongLongValue, 2160, bounds));
            assert(!PLANKMacFixedCaptureDescription(generation, @"id", 3840, bad.unsignedLongLongValue, bounds));
        }
        assert(!PLANKMacFixedCaptureDescription(@"", @"id", 3840, 2160, bounds));
        assert(!PLANKMacFixedCaptureDescription(@"00000000-0000-0000-0000-000000000000", @"id", 3840, 2160, bounds));
        assert(!PLANKMacFixedCaptureDescription(generation, @"", 3840, 2160, bounds));
        assert(!PLANKMacFixedCaptureDescription(generation, @"id", 3840, 2160, CGRectMake(NAN, 0, 1, 1)));
        assert(!PLANKMacFixedCaptureDescription(generation, @"id", 3840, 2160, CGRectMake(0, 0, INFINITY, 1)));
        assert(!PLANKMacFixedCaptureDescription(generation, @"id", 3840, 2160, CGRectZero));
        puts("macos_fixed_capture=pass shared_fixture=1 separate_pixel_point_geometry=1 invalid_bounds_rejected=1");
    }
}
