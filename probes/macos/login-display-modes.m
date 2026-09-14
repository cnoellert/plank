// SPDX-License-Identifier: GPL-3.0-or-later
// Bounded LoginWindow-only qualification. Own diagnostic display; no OS input,
// capture, persistent settings, or mutation of another application's display.
#import <AppKit/AppKit.h>
#import "virtual-display-probe.h"
#import "../../apps/host/macos/auth/graphical-authority.h"

int main(void) {
    @autoreleasepool {
        setbuf(stdout, NULL);
        [NSApplication.sharedApplication setActivationPolicy:NSApplicationActivationPolicyProhibited];
        PLANKMacGraphicalAuthority *authority = [[PLANKMacGraphicalAuthority alloc] initWithPhase:PLANKMacScopeSignIn];
        if (!plank_macos_graphical_identity_valid(authority.snapshot) || !validateAPI()) return 2;
        __block PLANKVirtualDisplay *display = nil;
        __block unsigned step = 0, attempts = 0, passed = 0;
        static const unsigned sizes[][2] = {{1920,1080}, {3840,2160}, {5120,2160}};
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), 250*NSEC_PER_MSEC, 0);
        dispatch_source_set_event_handler(timer, ^{
            if (!plank_macos_graphical_identity_valid(authority.snapshot)) exit(3);
            if (!display) {
                PLANKDisplayDescriptor *descriptor = [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
                descriptor.name = @"PLANK Login Mode Probe";
                descriptor.maxPixelsWide = 5120; descriptor.maxPixelsHigh = 2160;
                descriptor.sizeInMillimeters = CGSizeMake(600, 340);
                descriptor.vendorID = 0xF0F0; descriptor.productID = 62; descriptor.serialNum = 62;
                descriptor.queue = dispatch_get_main_queue();
                display = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
                NSMutableArray *modes = [NSMutableArray array];
                for (unsigned i = 0; i < 3; ++i) {
                    id mode = [[NSClassFromString(@"CGVirtualDisplayMode") alloc]
                        initWithWidth:sizes[i][0] height:sizes[i][1] refreshRate:60];
                    if (!mode) exit(4);
                    [modes addObject:mode];
                }
                PLANKDisplaySettings *settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
                settings.hiDPI = 0; settings.modes = modes;
                if (!display || ![display applySettings:settings]) exit(4);
            }
            CGDirectDisplayID target = display.displayID;
            CFArrayRef modes = CGDisplayCopyAllDisplayModes(target, NULL);
            CFIndex count = modes ? CFArrayGetCount(modes) : 0;
            BOOL selected = NO;
            if (count < 128) for (CFIndex i = 0; i < count; ++i) {
                CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
                if (CGDisplayModeGetPixelWidth(mode) == sizes[step][0] &&
                    CGDisplayModeGetPixelHeight(mode) == sizes[step][1] &&
                    CGDisplayModeGetWidth(mode) == sizes[step][0] &&
                    CGDisplayModeGetHeight(mode) == sizes[step][1]) {
                    selected = CGDisplaySetDisplayMode(target, mode, NULL) == kCGErrorSuccess;
                    break;
                }
            }
            if (modes) CFRelease(modes);
            CGRect bounds = CGDisplayBounds(target);
            BOOL ready = CGDisplayIsActive(target) && !CGDisplayIsInMirrorSet(target) &&
                CGDisplayPixelsWide(target) == sizes[step][0] && CGDisplayPixelsHigh(target) == sizes[step][1] &&
                bounds.size.width == sizes[step][0] && bounds.size.height == sizes[step][1];
            if (ready || ++attempts == 24) {
                printf("login_mode requested=%ux%u display=%u modes=%ld selected=%d actual=%zux%zu bounds=%.0fx%.0f ready=%d\n",
                    sizes[step][0], sizes[step][1], target, count, selected,
                    CGDisplayPixelsWide(target), CGDisplayPixelsHigh(target), bounds.size.width, bounds.size.height, ready);
                passed += ready; attempts = 0;
                if (++step == 3) {
                    printf("login_mode_passed=%u/3 removal_boundary=process_exit\n", passed);
                    exit(passed == 3 ? 0 : 7);
                }
            }
        });
        dispatch_resume(timer);
        [NSApp run];
    }
    return 5;
}
