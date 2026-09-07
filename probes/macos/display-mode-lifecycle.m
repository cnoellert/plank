// SPDX-License-Identifier: GPL-3.0-or-later
// Isolate temporary mode selection from capture, AppKit and encoding.
#import "virtual-display-probe.h"

static BOOL runCase(BOOL selectMode, BOOL restoreMode) {
    CGDirectDisplayID target = kCGNullDirectDisplay;
    __weak PLANKVirtualDisplay *observed = nil;
    BOOL selected = !selectMode;
    @autoreleasepool {
        // Keep destructive mode-change reproductions on the old diagnostic
        // identity, never poisoning the geometry-qualified capture identity.
        PLANKVirtualDisplay *display = selectMode ? createProbeDisplayWithIdentity(3840, 2160, 1, 1) :
                                                   createProbeDisplay(3840, 2160);
        if (!display) return NO;
        target = display.displayID;
        observed = display;
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
        printf("mode_lifetime_case=%s\n", restoreMode ? "change-restore" : selectMode ? "app-mode-change" : "no-mode-selection");
        BOOL initialMode = report(target, 3840, 2160);
        printf("owned_identity vendor=%u product=%u serial=%u pixels=%zux%zu\n",
            CGDisplayVendorNumber(target), CGDisplayModelNumber(target), CGDisplaySerialNumber(target),
            CGDisplayPixelsWide(target), CGDisplayPixelsHigh(target));
        if (!selectMode) selected = initialMode;
        if (selectMode && !CGDisplayIsInMirrorSet(target)) {
            CGDisplayModeRef original = CGDisplayCopyDisplayMode(target);
            // Force a real change even if the session already selected 4K.
            size_t width = CGDisplayPixelsWide(target) == 3840 ? 1920 : 3840;
            size_t height = width == 1920 ? 1080 : 2160;
            CFArrayRef modes = CGDisplayCopyAllDisplayModes(target, NULL);
            if (modes && CFArrayGetCount(modes) < 128) {
                for (CFIndex i = 0; i < CFArrayGetCount(modes); ++i) {
                    CGDisplayModeRef mode = (CGDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
                    if (CGDisplayModeGetPixelWidth(mode) == width && CGDisplayModeGetPixelHeight(mode) == height &&
                        CGDisplayModeGetWidth(mode) == width && CGDisplayModeGetHeight(mode) == height &&
                        fabs(CGDisplayModeGetRefreshRate(mode) - 60) < 0.01) {
                        selected = CGDisplaySetDisplayMode(target, mode, NULL) == kCGErrorSuccess;
                        break;
                    }
                }
            }
            if (modes) CFRelease(modes);
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
            selected &= report(target, (unsigned int)width, (unsigned int)height);
            if (restoreMode) {
                CGError error = original ? CGDisplaySetDisplayMode(target, original, NULL) : kCGErrorFailure;
                printf("owned_mode_restore_status=%d\n", error);
                selected &= error == kCGErrorSuccess;
                if (!error) {
                    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
                    selected &= report(target, (unsigned int)CGDisplayModeGetPixelWidth(original),
                                       (unsigned int)CGDisplayModeGetPixelHeight(original));
                }
            }
            if (original) CFRelease(original);
        }
        display = nil;
    }
    BOOL objectReleased = observed == nil;
    __block unsigned int ticks = 0;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, NSEC_PER_MSEC * 100, NSEC_PER_MSEC * 10);
    dispatch_source_set_event_handler(timer, ^{
        if (onlineState(target) == 0 || ++ticks >= 50) CFRunLoopStop(CFRunLoopGetMain());
    });
    dispatch_resume(timer);
    CFRunLoopRun();
    dispatch_source_cancel(timer);
    BOOL removed = onlineState(target) == 0;
    printf("mode_lifetime selected=%d object_released=%d removed=%d\n", selected, objectReleased, removed);
    return selected && objectReleased && removed;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        setbuf(stdout, NULL);
        BOOL restoreMode = argc == 2 && strcmp(argv[1], "--restore-mode") == 0;
        if (argc > 2 || (argc == 2 && !restoreMode && strcmp(argv[1], "--select-mode") != 0)) return 2;
        // One lifecycle per process: WindowServer can replace the fallback
        // display between invocations. Never reuse a previous display ID.
        return runCase(argc == 2, restoreMode) ? 0 : 7;
    }
}
