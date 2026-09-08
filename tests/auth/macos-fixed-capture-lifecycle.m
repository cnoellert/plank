// SPDX-License-Identifier: GPL-3.0-or-later
// Test-only CG definitions: no real display modification or mode creation.
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <string.h>
#import "fixed-capture.h"

static CGDisplayReconfigurationCallBack observer;
static unsigned registered;
static BOOL available = YES, changeDuringRead, failRegistration;
static unsigned copyCount;
static int fakeMode;
static size_t width = 3840;
CGError CGDisplayRegisterReconfigurationCallback(CGDisplayReconfigurationCallBack callback, void *context) {
    assert(context == NULL);
    ++registered;
    if (failRegistration) return kCGErrorFailure;
    observer = callback;
    return kCGErrorSuccess;
}
CGDirectDisplayID CGMainDisplayID(void) { return 42; }
boolean_t CGDisplayIsActive(CGDirectDisplayID display) { return display == 42 && available; }
CGDisplayModeRef CGDisplayCopyDisplayMode(CGDirectDisplayID display) {
    assert(display == 42);
    if (changeDuringRead && ++copyCount == 2) observer(42, kCGDisplaySetModeFlag, NULL);
    return (CGDisplayModeRef)&fakeMode;
}
void CGDisplayModeRelease(CGDisplayModeRef mode) { assert(mode == (CGDisplayModeRef)&fakeMode); }
size_t CGDisplayModeGetPixelWidth(CGDisplayModeRef mode) { (void)mode; return width; }
size_t CGDisplayModeGetPixelHeight(CGDisplayModeRef mode) { (void)mode; return 2160; }
int32_t CGDisplayModeGetIODisplayModeID(CGDisplayModeRef mode) { (void)mode; return 17; }
CGRect CGDisplayBounds(CGDirectDisplayID display) { assert(display == 42); return CGRectMake(0, 0, 1920, 1080); }

int main(int argc, const char **argv) {
    @autoreleasepool {
        failRegistration = argc == 2 && !strcmp(argv[1], "--registration-failure");
        PLANKMacFixedCapture *capture = [PLANKMacFixedCapture new];
        if (failRegistration) {
            assert(!capture && registered == 1);
            assert(![PLANKMacFixedCapture new] && registered == 1);
            puts("macos_capture_observer=pass registration_failure_closed=1");
            return 0;
        }
        assert(capture && observer && registered == 1);
        NSDictionary *first = [capture snapshot];
        assert(first && [first isEqual:[capture snapshot]]);
        observer(42, kCGDisplayBeginConfigurationFlag, NULL);
        assert(![capture snapshot]);
        observer(42, kCGDisplaySetModeFlag, NULL);
        NSDictionary *second = [capture snapshot];
        assert(second && ![second[@"generation"] isEqual:first[@"generation"]]);
        assert([second isEqual:[capture snapshot]]);
        // Geometry can return to its original state without an intervening query.
        observer(42, kCGDisplaySetModeFlag, NULL);
        observer(42, kCGDisplaySetModeFlag, NULL);
        NSDictionary *third = [capture snapshot];
        assert(third && ![third[@"generation"] isEqual:second[@"generation"]]);
        changeDuringRead = YES;
        assert(![capture snapshot]);
        changeDuringRead = NO;
        NSDictionary *fourth = [capture snapshot];
        assert(fourth && ![fourth[@"generation"] isEqual:third[@"generation"]]);
        available = NO;
        assert(![capture snapshot]);
        available = YES;
        assert(![[capture snapshot][@"generation"] isEqual:fourth[@"generation"]]);
        // An unnotified geometry difference is still caught by the double read.
        NSDictionary *beforeWidth = [capture snapshot];
        width = 1920;
        assert(![[capture snapshot][@"generation"] isEqual:beforeWidth[@"generation"]]);
        assert([PLANKMacFixedCapture new] && registered == 1);
        NSDictionary *beforeProfile = [capture snapshot];
        capture.encodingMode = @"hevc-10-444-videotoolbox";
        NSDictionary *fullChroma = [capture snapshot];
        assert(fullChroma && ![fullChroma[@"generation"] isEqual:beforeProfile[@"generation"]]);
        assert([fullChroma[@"capture"][@"encoding_profile"][@"chroma"] isEqual:@"4:4:4"]);
        assert([fullChroma isEqual:[capture snapshot]]);
        capture.encodingMode = @"hevc-10-420-videotoolbox";
        assert(![[capture snapshot][@"generation"] isEqual:fullChroma[@"generation"]]);
        capture.encodingMode = @"invalid";
        assert(![capture snapshot]);
        capture = nil;
        observer(42, kCGDisplaySetModeFlag, NULL); // no dangling object context
        puts("macos_capture_observer=pass synthetic_cg=1 change_back_invalidated=1 mid_read_rejected=1 process_lifetime=1");
    }
}
