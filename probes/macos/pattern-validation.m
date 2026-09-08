// SPDX-License-Identifier: GPL-3.0-or-later
// Owned SDR chart and bounded, read-only pixel inspection for qualification only.
#import "pattern-validation.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <fcntl.h>
#include <unistd.h>
#import "annexb-sample.h"

static const CGFloat chartColors[8][3] = {
    {1,1,1}, {1,1,0}, {0,1,1}, {0,1,0}, {1,0,1}, {1,0,0}, {0,0,1}, {0,0,0}
};

@interface PLANKChartWindow : NSWindow
@property(nonatomic, strong) NSTimer *cadenceTimer;
@end
@implementation PLANKChartWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
- (void)close {
    [self.cadenceTimer invalidate];
    self.cadenceTimer = nil;
    [super close];
}
@end

@interface PLANKChartView : NSView
@end
@implementation PLANKChartView
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextSetFillColorSpace(context, space);
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    for (unsigned int i = 0; i < 8; i++) {
        CGFloat components[] = {chartColors[i][0], chartColors[i][1], chartColors[i][2], 1};
        CGContextSetFillColor(context, components);
        CGContextFillRect(context, CGRectMake(i * width / 8, height / 3, width / 8 + 1, height * 2 / 3));
    }
    CGFloat black[] = {0,0,0,1};
    CGContextSetFillColor(context, black);
    CGContextFillRect(context, CGRectMake(0, 0, width, height / 3));
    for (unsigned int i = 0; i < 32; i++) {
        CGFloat grey = i / 31.0;
        CGFloat components[] = {grey, grey, grey, 1};
        CGContextSetFillColor(context, components);
        CGContextFillRect(context, CGRectMake(i * width / 32, height / 8, width / 32 + 1, height / 8));
    }
    CGColorSpaceRelease(space);
}
@end

static BOOL chartWindowReady(NSWindow *window, CGDirectDisplayID display, BOOL report) {
    CGRect target = CGDisplayBounds(display);
    NSRect screen = window.screen.frame, frame = window.frame;
    NSArray *items = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow,
        (CGWindowID)window.windowNumber));
    NSDictionary *item = items.firstObject;
    CGRect compositor = CGRectZero;
    NSDictionary *bounds = item[(__bridge NSString *)kCGWindowBounds];
    BOOL boundsAvailable = [bounds isKindOfClass:NSDictionary.class] && CGRectMakeWithDictionaryRepresentation(
        (__bridge CFDictionaryRef)bounds, &compositor);
    BOOL onscreen = [item[(__bridge NSString *)kCGWindowIsOnscreen] boolValue];
    BOOL ready = window.visible && boundsAvailable && onscreen &&
        [window.screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == display &&
        !CGRectIsEmpty(target) && CGRectEqualToRect(target, compositor);
    if (report) {
    printf("chart_geometry target=%u target_cg=%.0f,%.0f,%.0f,%.0f ns_screen=%u ns_frame=%.0f,%.0f,%.0f,%.0f window_frame=%.0f,%.0f,%.0f,%.0f visible=%d compositor_bounds=%d compositor=%.0f,%.0f,%.0f,%.0f onscreen=%d\n",
        display, target.origin.x, target.origin.y, target.size.width, target.size.height,
        [window.screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue],
        screen.origin.x, screen.origin.y, screen.size.width, screen.size.height,
        frame.origin.x, frame.origin.y, frame.size.width, frame.size.height, window.visible,
        boundsAvailable, compositor.origin.x, compositor.origin.y, compositor.size.width, compositor.size.height,
        onscreen);
    }
    return ready;
}

NSWindow *PLANKCreatePatternWindow(CGDirectDisplayID display, BOOL mixedCadence) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSScreen *screen = nil;
    for (NSScreen *candidate in NSScreen.screens)
        if ([candidate.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == display) screen = candidate;
    if (!screen) return nil;
    PLANKChartWindow *window = [[PLANKChartWindow alloc] initWithContentRect:screen.frame
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.ignoresMouseEvents = YES;
    window.level = NSScreenSaverWindowLevel;
    window.opaque = YES;
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    window.colorSpace = [[NSColorSpace alloc] initWithCGColorSpace:space];
    CGColorSpaceRelease(space);
    PLANKChartView *view = [[PLANKChartView alloc] initWithFrame:NSMakeRect(0, 0, screen.frame.size.width, screen.frame.size.height)];
    window.contentView = view;
    view.wantsLayer = YES;
    CALayer *marker = [CALayer layer];
    marker.backgroundColor = NSColor.whiteColor.CGColor;
    marker.bounds = CGRectMake(0, 0, screen.frame.size.width / 16, screen.frame.size.height / 16);
    marker.position = CGPointMake(screen.frame.size.width / 32, screen.frame.size.height / 32);
    [view.layer addSublayer:marker];
    CABasicAnimation *motion = [CABasicAnimation animationWithKeyPath:@"position.x"];
    motion.fromValue = @(screen.frame.size.width / 32);
    motion.toValue = @(screen.frame.size.width * 31 / 32);
    motion.duration = 1.5;
    motion.autoreverses = YES;
    motion.repeatCount = HUGE_VALF;
    [marker addAnimation:motion forKey:@"bounded-probe-motion"];
    if (mixedCadence) {
        // A constant-value animation still makes WindowServer produce frames.
        // Remove it completely during idle phases; close invalidates this timer.
        __block BOOL moving = YES;
        window.cadenceTimer = [NSTimer scheduledTimerWithTimeInterval:9 repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            moving = !moving;
            if (moving) [marker addAnimation:motion forKey:@"bounded-probe-motion"];
            else [marker removeAnimationForKey:@"bounded-probe-motion"];
            printf("chart_phase moving=%d uptime_s=%.3f\n", moving, NSProcessInfo.processInfo.systemUptime);
        }];
    }
    printf("chart_mixed_cadence=%d moving_seconds=9 idle_seconds=9\n", mixedCadence);
    [window orderFrontRegardless];
    [window display];
    // AppKit's visible flag precedes WindowServer registration. Require the
    // owned chart to actually cover the requested display before capture starts.
    // This is a bounded test-fixture readiness check, not a color-check bypass.
    double started = NSProcessInfo.processInfo.systemUptime;
    while (!chartWindowReady(window, display, NO) &&
           NSProcessInfo.processInfo.systemUptime - started < 3)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
    BOOL ready = chartWindowReady(window, display, YES);
    printf("chart_ready=%d wait_ms=%.3f\n", ready,
        (NSProcessInfo.processInfo.systemUptime - started) * 1000);
    if (!ready) { [window close]; return nil; }
    return window;
}

NSArray<NSNumber *> *PLANKReadPatternSamples(CVPixelBufferRef pixel) {
    OSType format = CVPixelBufferGetPixelFormatType(pixel);
    BOOL fullChroma = format == kCVPixelFormatType_444YpCbCr10BiPlanarFullRange;
    BOOL tenBit = fullChroma || format == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ||
                  format == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange;
    if ((!tenBit && format != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) ||
        CVPixelBufferGetPlaneCount(pixel) != 2 || CVPixelBufferGetWidth(pixel) < 640 ||
        CVPixelBufferGetHeight(pixel) < 400 || CVPixelBufferLockBaseAddress(pixel, kCVPixelBufferLock_ReadOnly)) return nil;
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:120];
    const uint8_t *luma = CVPixelBufferGetBaseAddressOfPlane(pixel, 0);
    const uint8_t *chroma = CVPixelBufferGetBaseAddressOfPlane(pixel, 1);
    size_t width = CVPixelBufferGetWidth(pixel), height = CVPixelBufferGetHeight(pixel);
    size_t yStride = CVPixelBufferGetBytesPerRowOfPlane(pixel, 0);
    size_t cStride = CVPixelBufferGetBytesPerRowOfPlane(pixel, 1);
    for (unsigned int i = 0; i < 40 && luma && chroma; i++) {
        size_t x = (size_t)((i < 8 ? (i + 0.5) / 8 : (i - 8 + 0.5) / 32) * width);
        size_t y = (size_t)((i < 8 ? 0.25 : 0.8125) * height);
        size_t cx = fullChroma ? x * 2 : (x / 2) * 2;
        size_t cy = fullChroma ? y : y / 2;
        unsigned int yy = tenBit ? ((const uint16_t *)(luma + y * yStride))[x] >> 6 : luma[y * yStride + x];
        unsigned int cb = tenBit ? ((const uint16_t *)(chroma + cy * cStride))[cx] >> 6 : chroma[cy * cStride + cx];
        unsigned int cr = tenBit ? ((const uint16_t *)(chroma + cy * cStride))[cx + 1] >> 6 : chroma[cy * cStride + cx + 1];
        [values addObjectsFromArray:@[@(yy), @(cb), @(cr)]];
    }
    CVPixelBufferUnlockBaseAddress(pixel, kCVPixelBufferLock_ReadOnly);
    return values.count == 120 ? values : nil;
}

double PLANKPatternReferenceError(NSArray<NSNumber *> *samples, BOOL tenBit, BOOL bt601) {
    return PLANKPatternReferenceRangeError(samples, tenBit, bt601, NO);
}
double PLANKPatternReferenceRangeError(NSArray<NSNumber *> *samples, BOOL tenBit, BOOL bt601, BOOL fullRange) {
    if (samples.count != 120) return INFINITY;
    double maximum = 0, scale = tenBit ? 4 : 1;
    double yMin = fullRange ? 0 : 16, ySpan = fullRange ? (tenBit ? 255.75 : 255) : 219;
    double cSpan = fullRange ? (tenBit ? 255.75 : 255) : 224;
    double kr = bt601 ? 0.299 : 0.2126, kb = bt601 ? 0.114 : 0.0722;
    for (unsigned int i = 0; i < 40; i++) {
        double r = i < 8 ? chartColors[i][0] : (i - 8) / 31.0;
        double g = i < 8 ? chartColors[i][1] : r;
        double b = i < 8 ? chartColors[i][2] : r;
        double y = kr * r + (1 - kr - kb) * g + kb * b;
        double expected[] = {yMin + ySpan * y, 128 + cSpan * (b - y) / (2 * (1 - kb)),
                            128 + cSpan * (r - y) / (2 * (1 - kr))};
        for (unsigned int c = 0; c < 3; c++)
            maximum = MAX(maximum, fabs(samples[i * 3 + c].doubleValue / scale - expected[c]));
        printf("chart_patch=%u y=%.2f cb=%.2f cr=%.2f units=8bit_equivalent\n", i,
            samples[i*3].doubleValue / scale, samples[i*3+1].doubleValue / scale, samples[i*3+2].doubleValue / scale);
    }
    printf("chart_reference_matrix=%s max_error=%.3f units=8bit_equivalent native_10bit_precision_qualified=0\n",
        bt601 ? "BT601" : "BT709", maximum);
    return maximum;
}

// Convert only the 40 diagnostic sample triples, never a production pixel buffer.
NSArray<NSNumber *> *PLANKPatternMap601To709(NSArray<NSNumber *> *samples, BOOL tenBit) {
    return PLANKPatternMap601To709Range(samples, tenBit, NO);
}
NSArray<NSNumber *> *PLANKPatternMap601To709Range(NSArray<NSNumber *> *samples, BOOL tenBit, BOOL fullRange) {
    if (samples.count != 120) return nil;
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:120];
    double scale = tenBit ? 4 : 1;
    double yMin = fullRange ? 0 : 16, ySpan = fullRange ? (tenBit ? 255.75 : 255) : 219;
    double cSpan = fullRange ? (tenBit ? 255.75 : 255) : 224;
    for (NSUInteger i = 0; i < 40; i++) {
        double y = (samples[i*3].doubleValue / scale - yMin) / ySpan;
        double cb = (samples[i*3+1].doubleValue / scale - 128) / cSpan;
        double cr = (samples[i*3+2].doubleValue / scale - 128) / cSpan;
        double r = y + 2 * (1 - 0.299) * cr, b = y + 2 * (1 - 0.114) * cb;
        double g = (y - 0.299 * r - 0.114 * b) / (1 - 0.299 - 0.114);
        double mapped = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        [result addObjectsFromArray:@[@(scale * (yMin + ySpan * mapped)),
            @(scale * (128 + cSpan * (b - mapped) / (2 * (1 - 0.0722)))),
            @(scale * (128 + cSpan * (r - mapped) / (2 * (1 - 0.2126))))]];
    }
    return result;
}

@interface PLANKPatternValidator ()
@property(nonatomic) VTDecompressionSessionRef decoder;
@property(nonatomic, readwrite) BOOL complete, passed;
@end
@implementation PLANKPatternValidator
- (void)invalidate {
    if (self.decoder) { VTDecompressionSessionInvalidate(self.decoder); CFRelease(self.decoder); self.decoder = NULL; }
}
- (void)decode:(CMSampleBufferRef)sample reference:(NSArray<NSNumber *> *)reference
    pixelFormat:(OSType)format queue:(dispatch_queue_t)queue completion:(void (^)(void))completion {
    BOOL fullRange = format == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange ||
                     format == kCVPixelFormatType_444YpCbCr10BiPlanarFullRange;
    BOOL tenBit = fullRange || format == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange;
    // Chart-only diagnostic: a private keyframe artifact for independent FFmpeg
    // inspection. Never enabled by ordinary live capture/encode modes.
    char directory[] = "/tmp/plank-chart-bitstream.XXXXXX";
    if (mkdtemp(directory)) {
        BOOL hevc = tenBit;
        NSString *path = [[NSString stringWithUTF8String:directory] stringByAppendingPathComponent:hevc ? @"chart.hevc" : @"chart.h264"];
        int descriptor = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
        FILE *file = descriptor >= 0 ? fdopen(descriptor, "w") : NULL;
        if (file) {
            BOOL wrote = PLANKWriteAnnexBSample(file, sample, hevc, YES);
            if (fclose(file)) wrote = NO;
            if (wrote) printf("chart_keyframe=%s\n", path.fileSystemRepresentation);
            else unlink(path.fileSystemRepresentation);
        } else if (descriptor >= 0) close(descriptor);
    }
    NSDictionary *attributes = @{(__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(format),
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}};
    OSStatus status = VTDecompressionSessionCreate(NULL, CMSampleBufferGetFormatDescription(sample),
        NULL, (__bridge CFDictionaryRef)attributes, NULL, &_decoder);
    if (!status) status = VTDecompressionSessionDecodeFrameWithOutputHandler(self.decoder, sample, 0, NULL,
        ^(OSStatus decodeStatus, VTDecodeInfoFlags flags, CVImageBufferRef image, CMTime pts, CMTime duration) {
        (void)pts; (void)duration;
        if (image) CFRetain(image);
        dispatch_async(queue, ^{
            NSArray *decoded = image && !decodeStatus && !(flags & kVTDecodeInfo_FrameDropped)
                ? PLANKReadPatternSamples(image) : nil;
            double maximum = 0;
            BOOL valid = decoded.count == 120 && reference.count == 120 && image &&
                CVPixelBufferGetPixelFormatType(image) == format;
            if (image) {
                const CFStringRef keys[] = {kCVImageBufferColorPrimariesKey, kCVImageBufferTransferFunctionKey, kCVImageBufferYCbCrMatrixKey};
                for (unsigned int i = 0; i < 3; i++) {
                    CFTypeRef value = CVBufferCopyAttachment(image, keys[i], NULL);
                    printf("decoded_color_%u=%s\n", i, value ? [(__bridge id)value description].UTF8String : "missing");
                    if (value) CFRelease(value);
                }
                (void)PLANKPatternReferenceRangeError(decoded, tenBit, NO, fullRange);
            }
            for (NSUInteger i = 0; valid && i < 120; i++)
                maximum = MAX(maximum, fabs([decoded[i] doubleValue] - reference[i].doubleValue));
            maximum /= tenBit ? 4 : 1;
            self.passed = valid && maximum <= 6;
            self.complete = YES;
            printf("chart_decoded_match=%d max_error=%.3f units=8bit_equivalent decode_status=%d\n", self.passed, maximum, decodeStatus);
            if (image) CFRelease(image);
            [self invalidate];
            completion();
        });
    });
    if (status) {
        fprintf(stderr, "chart_decode_submit_status=%d\n", status);
        [self invalidate]; self.complete = YES; self.passed = NO; completion();
    }
}
@end
