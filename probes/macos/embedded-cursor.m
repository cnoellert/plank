// SPDX-License-Identifier: GPL-3.0-or-later
// Own-window cursor pixels only; no keyboard/buttons, network or saved images.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#include <math.h>
#include <unistd.h>

@interface PLANKCursorWindow : NSWindow
@end
@implementation PLANKCursorWindow
- (BOOL)canBecomeKeyWindow { return YES; }
@end

@interface PLANKCursorView : NSView
@property NSCursor *testCursor;
@property BOOL tick;
@end
@implementation PLANKCursorView
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    [[NSColor colorWithWhite:self.tick ? 0.25 : 0.30 alpha:1] setFill];
    NSRectFill(self.bounds);
}
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:self.testCursor]; }
@end

static NSCursor *cursor(BOOL reversed) {
    NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
        pixelsWide:32 pixelsHigh:32 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
        isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:128 bitsPerPixel:32];
    for (unsigned y = 0; y < 32; ++y) for (unsigned x = 0; x < 32; ++x) {
        BOOL pink = (x < 16) != reversed;
        uint8_t *p = bitmap.bitmapData + y * bitmap.bytesPerRow + x * 4;
        p[0] = p[2] = pink ? 255 : 0; p[1] = pink ? 0 : 255; p[3] = 255;
    }
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(32, 32)];
    [image addRepresentation:bitmap];
    return [[NSCursor alloc] initWithImage:image hotSpot:NSMakePoint(4, 5)];
}

@interface PLANKCursorCheck : NSObject <SCStreamOutput, SCStreamDelegate>
@property PLANKCursorWindow *window;
@property PLANKCursorView *view;
@property SCStream *stream;
@property SCStreamConfiguration *config;
@property CGDirectDisplayID display;
@property CGPoint expected;
@property NSUInteger phase, matches;
@property uint64_t changedAt;
@property BOOL updating, stopping;
@property int result;
- (void)start;
- (void)advance;
- (void)finish:(int)result;
@end
@implementation PLANKCursorCheck
- (BOOL)ownedFocus {
    return NSApp.active && self.window.keyWindow && CGPreflightPostEventAccess() && AXIsProcessTrusted();
}
- (void)finish:(int)result {
    if (self.stopping) return;
    self.stopping = YES; self.result = result;
    void (^done)(void) = ^{
        [NSApp stop:nil];
        [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined
            location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil
            subtype:0 data1:0 data2:0] atStart:NO];
    };
    if (self.stream) [self.stream stopCaptureWithCompletionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ if (error) self.result = 8; done(); });
    }];
    else done();
}
- (void)start {
    if (![self ownedFocus]) { [self finish:3]; return; }
    [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:YES
        completionHandler:^(SCShareableContent *content, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.stopping) return;
                SCDisplay *display = nil; SCWindow *window = nil;
                for (SCDisplay *item in content.displays) if (item.displayID == self.display) display = item;
                for (SCWindow *item in content.windows)
                    if (item.windowID == (CGWindowID)self.window.windowNumber &&
                        item.owningApplication.processID == getpid()) window = item;
                if (error || !display || !window || ![self ownedFocus]) { [self finish:4]; return; }
                // Display capture, but include only our window; never sample other applications.
                SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display includingWindows:@[window]];
                self.config = [SCStreamConfiguration new];
                self.config.width = CGDisplayPixelsWide(self.display);
                self.config.height = CGDisplayPixelsHigh(self.display);
                self.config.pixelFormat = kCVPixelFormatType_32BGRA;
                self.config.colorSpaceName = kCGColorSpaceSRGB;
                self.config.minimumFrameInterval = CMTimeMake(1, 10);
                self.config.queueDepth = 3;
                self.config.showsCursor = NO;
                self.config.capturesAudio = NO;
                self.config.captureMicrophone = NO;
                self.stream = [[SCStream alloc] initWithFilter:filter configuration:self.config delegate:self];
                if (![self.stream addStreamOutput:self type:SCStreamOutputTypeScreen
                    sampleHandlerQueue:dispatch_get_main_queue() error:NULL]) { [self finish:4]; return; }
                [self advance];
                [self.stream startCaptureWithCompletionHandler:^(NSError *failure) {
                    if (failure) dispatch_async(dispatch_get_main_queue(), ^{ [self finish:4]; });
                }];
            });
        }];
}
- (void)advance {
    if (self.stopping) return;
    if (![self ownedFocus]) { [self finish:3]; return; }
    if (self.phase == 5) { [self finish:0]; return; }
    self.matches = 0; self.updating = YES;
    self.view.testCursor = cursor(self.phase == 3);
    [self.window invalidateCursorRectsForView:self.view];
    NSPoint cocoa = [self.window convertPointToScreen:NSMakePoint(self.phase < 2 ? 180 : 420, 200)];
    self.expected = CGPointMake(cocoa.x, CGRectGetHeight(CGDisplayBounds(CGMainDisplayID())) - cocoa.y);
    CGEventRef motion = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, self.expected, kCGMouseButtonLeft);
    if (!motion) { [self finish:4]; return; }
    CGEventPost(kCGHIDEventTap, motion); CFRelease(motion);
    [self.view.testCursor set];
    self.config.showsCursor = self.phase > 0 && self.phase < 4;
    void (^updated)(NSError *) = ^(NSError *error) {
        if (error) { [self finish:4]; return; }
        self.changedAt = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        self.updating = NO;
    };
    if (!self.phase) updated(nil);
    else [self.stream updateConfiguration:self.config completionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ updated(error); });
    }];
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    (void)stream; (void)error;
    dispatch_async(dispatch_get_main_queue(), ^{ [self finish:4]; });
}
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    (void)stream;
    if (type != SCStreamOutputTypeScreen || self.stopping || self.updating ||
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - self.changedAt < 300 * NSEC_PER_MSEC) return;
    if (![self ownedFocus]) { [self finish:3]; return; }
    CVPixelBufferRef buffer = CMSampleBufferGetImageBuffer(sample);
    if (!buffer) return;
    if (CVPixelBufferGetWidth(buffer) != self.config.width || CVPixelBufferGetHeight(buffer) != self.config.height ||
        CVPixelBufferGetPixelFormatType(buffer) != kCVPixelFormatType_32BGRA ||
        CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly)) { [self finish:4]; return; }
    CGRect bounds = CGDisplayBounds(self.display);
    double sx = self.config.width / bounds.size.width, sy = self.config.height / bounds.size.height;
    // Scan only the interior of our window, including both cursor locations.
    NSPoint top = [self.window convertPointToScreen:NSMakePoint(40, 350)];
    double ox = (top.x - bounds.origin.x) * sx;
    double oy = (CGRectGetHeight(CGDisplayBounds(CGMainDisplayID())) - top.y - bounds.origin.y) * sy;
    size_t count[2] = {0, 0}; double sumX[2] = {0, 0}, sumY[2] = {0, 0};
    const uint8_t *base = CVPixelBufferGetBaseAddress(buffer);
    size_t stride = CVPixelBufferGetBytesPerRow(buffer);
    for (size_t y = (size_t)fmax(0, oy); y < fmin(self.config.height, oy + 300 * sy); ++y)
        for (size_t x = (size_t)fmax(0, ox); x < fmin(self.config.width, ox + 560 * sx); ++x) {
            const uint8_t *p = base + y * stride + x * 4;
            int c = p[0] > 200 && p[1] < 70 && p[2] > 200 ? 0 :
                (p[0] < 70 && p[1] > 200 && p[2] < 70 ? 1 : -1);
            if (c >= 0) { count[c]++; sumX[c] += x; sumY[c] += y; }
        }
    CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    BOOL match = YES;
    if (!self.phase || self.phase == 4) match = count[0] == 0 && count[1] == 0;
    else for (unsigned c = 0; c < 2; ++c) {
        double cx = self.expected.x - bounds.origin.x - 4 + (((c == 0) != (self.phase == 3)) ? 8 : 24);
        double cy = self.expected.y - bounds.origin.y - 5 + 16;
        match &= count[c] > 300 * sx * sy && count[c] < 700 * sx * sy;
        if (count[c]) match &= fabs(sumX[c] / count[c] - cx * sx) < 3 * sx &&
                              fabs(sumY[c] / count[c] - cy * sy) < 3 * sy;
    }
    if (!match) { self.matches = 0; return; }
    if (++self.matches == 2) {
        printf("embedded_cursor phase=%lu match=1\n", (unsigned long)self.phase);
        self.phase++; [self advance];
    }
}
@end

int main(int argc, const char **argv) {
    if (argc != 2 || strcmp(argv[1], "--cursor") || getuid() == 0) return 2;
    alarm(30); setbuf(stdout, NULL);
    @autoreleasepool {
        if (!CGPreflightScreenCaptureAccess() || !CGPreflightPostEventAccess() || !AXIsProcessTrusted()) return 2;
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSRunningApplication *previous = NSWorkspace.sharedWorkspace.frontmostApplication;
        CGEventRef initial = CGEventCreate(NULL); if (!initial) return 2;
        CGPoint original = CGEventGetLocation(initial); CFRelease(initial);
        PLANKCursorCheck *check = [PLANKCursorCheck new]; check.result = 5; check.display = CGMainDisplayID();
        check.window = [[PLANKCursorWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 400)
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        check.window.releasedWhenClosed = NO;
        check.view = [[PLANKCursorView alloc] initWithFrame:NSMakeRect(0, 0, 640, 400)];
        check.view.testCursor = cursor(NO); check.window.contentView = check.view; [check.window center];
        id launch = [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidFinishLaunchingNotification
            object:NSApp queue:nil usingBlock:^(NSNotification *notification) {
                (void)notification; [check.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [check start]; });
            }];
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(timer, ^{ check.view.tick = !check.view.tick; [check.view setNeedsDisplay:YES]; });
        dispatch_resume(timer);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 18 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [check finish:5]; });
        [NSApp run];
        dispatch_source_cancel(timer); [NSNotificationCenter.defaultCenter removeObserver:launch];
        if (NSApp.active && check.window.keyWindow && CGPreflightPostEventAccess()) {
            CGEventRef restore = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, original, kCGMouseButtonLeft);
            if (restore) { CGEventPost(kCGHIDEventTap, restore); CFRelease(restore); }
            [NSCursor.arrowCursor set];
            if (previous && previous.processIdentifier != getpid()) [previous activateWithOptions:0];
        }
        [check.window orderOut:nil];
        printf("embedded_cursor completed=%lu result=%d saved_images=0 clicks=0 keys=0\n",
            (unsigned long)check.phase, check.result);
        return check.result;
    }
}
