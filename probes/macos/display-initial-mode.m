// SPDX-License-Identifier: GPL-3.0-or-later
// Isolated initial-mode experiment. Never changes a mode after activation.
#import "virtual-display-probe.h"
#include <mach-o/dyld.h>
#include <limits.h>
#include <signal.h>
#include <unistd.h>

static void inspectDisplay(CGDirectDisplayID display) {
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(display);
    printf("independent_display display=%u online=%d cg_pixels=%zux%zu mode_pixels=%zux%zu mode_points=%zux%zu hz=%.3f\n",
        display, onlineState(display), CGDisplayPixelsWide(display), CGDisplayPixelsHigh(display),
        mode ? CGDisplayModeGetPixelWidth(mode) : 0, mode ? CGDisplayModeGetPixelHeight(mode) : 0,
        mode ? CGDisplayModeGetWidth(mode) : 0, mode ? CGDisplayModeGetHeight(mode) : 0,
        mode ? CGDisplayModeGetRefreshRate(mode) : 0);
    if (mode) CGDisplayModeRelease(mode);
}
static BOOL waitFor(double seconds, BOOL (^condition)(void)) {
    double deadline = NSProcessInfo.processInfo.systemUptime + seconds;
    __block BOOL ready = NO;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC, 5 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
        ready = condition();
        if (ready || NSProcessInfo.processInfo.systemUptime >= deadline) CFRunLoopStop(CFRunLoopGetMain());
    });
    dispatch_resume(timer);
    CFRunLoopRun();
    dispatch_source_cancel(timer);
    return ready;
}

static BOOL runCase(unsigned int width, unsigned int height, CGSize physicalSize,
                    BOOL deferInitialSettings, BOOL hiDPI, BOOL *removed) {
    CGDirectDisplayID target = kCGNullDirectDisplay;
    __weak PLANKVirtualDisplay *observed = nil;
    BOOL ready = NO;
    double started = NSProcessInfo.processInfo.systemUptime;
    @autoreleasepool {
        PLANKDisplayDescriptor *descriptor = [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
        descriptor.name = @"PLANK Feasibility Probe";
        // Capacity and monitor identity remain fixed across all requested sizes.
        // Reuse our diagnostic identity, not the reference product's identity.
        descriptor.maxPixelsWide = 4096;
        descriptor.maxPixelsHigh = 4096;
        descriptor.sizeInMillimeters = physicalSize;
        descriptor.vendorID = 0xF0F0;
        descriptor.productID = 1;
        descriptor.serialNum = 1;
        descriptor.queue = dispatch_get_main_queue();
        PLANKVirtualDisplay *display = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
        if (!display) return NO;
        target = display.displayID;
        observed = display;
        // Isolate initial registration ordering; no repeated apply or mode switch.
        if (deferInitialSettings) (void)waitFor(0.15, ^BOOL{ return NO; });
        printf("initial_descriptor physical_mm=%.2fx%.2f deferred=%d hidpi=%d before_apply_pixels=%zux%zu\n",
            physicalSize.width, physicalSize.height, deferInitialSettings, hiDPI,
            CGDisplayPixelsWide(target), CGDisplayPixelsHigh(target));
        PLANKDisplayMode *mode = [[NSClassFromString(@"CGVirtualDisplayMode") alloc]
            initWithWidth:width height:height refreshRate:60];
        PLANKDisplaySettings *settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
        settings.hiDPI = hiDPI;
        settings.modes = mode ? @[mode] : @[];
        BOOL applied = mode && settings && [display applySettings:settings];
        if (applied) ready = waitFor(5, ^BOOL{
            CGRect bounds = CGDisplayBounds(target);
            return onlineState(target) == 1 && CGDisplayIsActive(target) &&
                !CGDisplayIsInMirrorSet(target) && CGDisplayPixelsWide(target) == width &&
                CGDisplayPixelsHigh(target) == height && bounds.size.width == width && bounds.size.height == height;
        });
        CGDisplayModeRef current = CGDisplayCopyDisplayMode(target);
        printf("initial_mode requested=%ux%u display=%u applied=%d ready=%d actual_pixels=%zux%zu bounds=%.0fx%.0f mode_object=%d reported_hz=%.3f elapsed_ms=%.3f\n",
            width, height, target, applied, ready, CGDisplayPixelsWide(target), CGDisplayPixelsHigh(target),
            CGDisplayBounds(target).size.width, CGDisplayBounds(target).size.height, current != NULL,
            current ? CGDisplayModeGetRefreshRate(current) : 0, (NSProcessInfo.processInfo.systemUptime - started) * 1000);
        if (current) CGDisplayModeRelease(current);
        // Inspect from a fresh process in this same graphical session. This
        // distinguishes actual mode selection from the creator's mode cache.
        char path[PATH_MAX];
        uint32_t pathSize = sizeof(path);
        if (!_NSGetExecutablePath(path, &pathSize)) {
            NSTask *inspector = [[NSTask alloc] init];
            inspector.executableURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
            inspector.arguments = @[@"--inspect", [NSString stringWithFormat:@"%u", target]];
            NSError *error = nil;
            if ([inspector launchAndReturnError:&error]) {
                if (!waitFor(3, ^BOOL{ return !inspector.running; })) {
                    (void)kill(inspector.processIdentifier, SIGKILL);
                    [inspector waitUntilExit];
                }
            }
        }
        printf("initial_mode_owner_still_alive=%u\n", display.displayID);
        display = nil;
    }
    double releaseStarted = NSProcessInfo.processInfo.systemUptime;
    *removed = waitFor(5, ^BOOL{ return onlineState(target) == 0; });
    printf("initial_mode_cleanup display=%u object_released=%d removed=%d owner_survived=1 elapsed_ms=%.3f\n",
        target, observed == nil, *removed, (NSProcessInfo.processInfo.systemUptime - releaseStarted) * 1000);
    return ready && observed == nil && *removed;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        setbuf(stdout, NULL);
        if (argc == 3 && strcmp(argv[1], "--inspect") == 0) {
            char *end = NULL;
            unsigned long value = strtoul(argv[2], &end, 10);
            if (!value || value > UINT32_MAX || !end || *end) return 2;
            inspectDisplay((CGDirectDisplayID)value);
            return 0;
        }
        BOOL comparison = argc == 2 && strcmp(argv[1], "--descriptor-comparison") == 0;
        BOOL retinaComparison = argc == 2 && strcmp(argv[1], "--hidpi-comparison") == 0;
        if ((argc != 1 && !comparison && !retinaComparison) || !validateAPI()) return 2;
        const unsigned int sizes[][2] = {{1920, 1080}, {1440, 932}, {3840, 2160}, {1708, 1072}};
        BOOL passed = YES;
        for (unsigned int index = 0; index < 4; ++index) {
            BOOL removed = NO;
            if (retinaComparison) {
                passed &= runCase(index < 2 ? 3840 : 4096, 2160, CGSizeMake(641, 401), NO, index % 2, &removed);
            } else if (comparison) {
                // One-factor comparisons: physical size, then exact reference
                // resolution; final case isolates deferred initial registration.
                CGSize physical = index == 0 || index == 3 ? CGSizeMake(508, 285.75) : CGSizeMake(641, 401);
                passed &= runCase(index == 2 ? 4096 : 3840, 2160, physical, index == 3, NO, &removed);
            } else {
                passed &= runCase(sizes[index][0], sizes[index][1], CGSizeMake(508, 285.75), NO, NO, &removed);
            }
            if (!removed) break; // Never accumulate outputs after a cleanup failure.
        }
        printf("initial_mode_matrix_passed=%d explicit_mode_switches=0\n", passed);
        return passed ? 0 : 7;
    }
}
