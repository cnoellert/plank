// SPDX-License-Identifier: GPL-3.0-or-later
// Metadata-only capture isolation: no encoder, transport, pixel read or input.
#import <AppKit/AppKit.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#include <time.h>
#include <unistd.h>
#include <string.h>

enum { Capacity = 8192 };
typedef struct { uint64_t callback; int64_t pts; NSInteger status; } Record;
@interface PLANKCaptureCadence : NSObject <SCStreamOutput, SCStreamDelegate> {
    dispatch_queue_t _queue;
    SCStream *_stream;
    Record _records[Capacity];
    size_t _count, _complete, _width, _height;
    BOOL _stopping;
    CGDirectDisplayID _display;
    NSPanel *_pattern;
}
@property BOOL nativeRate;
@property BOOL animatedPattern;
@property int result;
- (void)begin;
@end

@implementation PLANKCaptureCadence
- (void)finish:(int)result {
    if (_stopping) return;
    _stopping = YES;
    self.result = result;
    void (^done)(void) = ^{
        printf("cadence_end rows=%zu complete=%zu result=%d\n", self->_count, self->_complete, self.result);
        for (size_t i = 0; i < self->_count; ++i) {
            Record r = self->_records[i];
            printf("cadence_row %llu,%lld,%ld\n", (unsigned long long)r.callback,
                   (long long)r.pts, (long)r.status);
        }
        fflush(stdout);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_pattern orderOut:nil]; self->_pattern = nil;
            CFRunLoopStop(CFRunLoopGetMain());
        });
    };
    if (!_stream) { done(); return; }
    [_stream stopCaptureWithCompletionHandler:^(NSError *error) {
        dispatch_async(self->_queue, ^{ if (error) self.result = 4; done(); });
    }];
}
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample
        ofType:(SCStreamOutputType)type {
    (void)stream;
    uint64_t callback = clock_gettime_nsec_np(CLOCK_MONOTONIC);
    if (_stopping || type != SCStreamOutputTypeScreen) return;
    if (_count == Capacity) { [self finish:5]; return; }
    NSArray *attachments = (__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample, false);
    NSNumber *status = attachments.firstObject[SCStreamFrameInfoStatus];
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sample);
    int64_t ns = CMTIME_IS_NUMERIC(pts)
        ? CMTimeConvertScale(pts, 1000000000, kCMTimeRoundingMethod_RoundTowardZero).value : -1;
    NSInteger state = [status isKindOfClass:NSNumber.class] ? status.integerValue : -1;
    _records[_count++] = (Record){callback, ns, state};
    if (state != SCFrameStatusComplete) return;
    CVPixelBufferRef pixel = CMSampleBufferGetImageBuffer(sample);
    if (!CMSampleBufferIsValid(sample) || ns < 0 || !pixel || !CVPixelBufferGetIOSurface(pixel) ||
        CVPixelBufferGetWidth(pixel) != _width || CVPixelBufferGetHeight(pixel) != _height ||
        CVPixelBufferGetPixelFormatType(pixel) != kCVPixelFormatType_420YpCbCr10BiPlanarFullRange) {
        [self finish:3]; return;
    }
    ++_complete;
    // Do not retain the sample/surface or dispatch work with it. No per-frame I/O.
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    (void)stream; (void)error;
    dispatch_async(_queue, ^{ [self finish:3]; });
}
- (void)begin {
    _display = CGMainDisplayID();
    if (self.animatedPattern) {
        NSScreen *screen = nil;
        for (NSScreen *candidate in NSScreen.screens)
            if ([candidate.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == _display) screen = candidate;
        if (!screen) { self.result = 3; CFRunLoopStop(CFRunLoopGetMain()); return; }
        _pattern = [[NSPanel alloc] initWithContentRect:screen.frame
            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
            backing:NSBackingStoreBuffered defer:NO];
        _pattern.level = NSFloatingWindowLevel; _pattern.ignoresMouseEvents = YES;
        _pattern.contentView.wantsLayer = YES;
        _pattern.contentView.layer.backgroundColor = NSColor.darkGrayColor.CGColor;
        CALayer *bar = [CALayer layer];
        bar.bounds = CGRectMake(0, 0, 100, screen.frame.size.height);
        bar.position = CGPointMake(50, screen.frame.size.height / 2);
        bar.backgroundColor = NSColor.whiteColor.CGColor;
        [_pattern.contentView.layer addSublayer:bar];
        CABasicAnimation *motion = [CABasicAnimation animationWithKeyPath:@"position.x"];
        motion.fromValue = @50; motion.toValue = @(screen.frame.size.width - 50);
        motion.duration = 2; motion.autoreverses = YES; motion.repeatCount = HUGE_VALF;
        motion.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        [bar addAnimation:motion forKey:@"cadence"];
        [_pattern orderFrontRegardless]; // No key window, activation, or input.
    }
    _queue = dispatch_queue_create("la.instinctual.PLANK.capture-cadence", DISPATCH_QUEUE_SERIAL);
    dispatch_async(_queue, ^{
        BOOL allowed = CGPreflightScreenCaptureAccess();
        printf("cadence_begin native_rate=%d pattern=%d capture_preflight=%d encoder=0 network=0 audio=0\n",
               self.nativeRate, self.animatedPattern, allowed);
        if (!allowed) { [self finish:2]; return; } // Never request new consent.
        [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:YES
            completionHandler:^(SCShareableContent *content, NSError *error) {
            dispatch_async(self->_queue, ^{
                if (self->_stopping) return;
                SCDisplay *selected = nil;
                for (SCDisplay *display in content.displays)
                    if (display.displayID == self->_display) selected = display;
                if (error || !selected) { [self finish:3]; return; }
                SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:selected excludingWindows:@[]];
                self->_width = (size_t)(filter.contentRect.size.width * filter.pointPixelScale);
                self->_height = (size_t)(filter.contentRect.size.height * filter.pointPixelScale);
                SCStreamConfiguration *config = [SCStreamConfiguration new];
                config.width = self->_width; config.height = self->_height;
                config.minimumFrameInterval = self.nativeRate ? kCMTimeZero : CMTimeMake(1, 60);
                config.queueDepth = 3;
                config.pixelFormat = kCVPixelFormatType_420YpCbCr10BiPlanarFullRange;
                config.captureDynamicRange = SCCaptureDynamicRangeSDR;
                config.colorSpaceName = kCGColorSpaceSRGB;
                config.showsCursor = YES; config.capturesAudio = NO; config.captureMicrophone = NO;
                CGDisplayModeRef mode = CGDisplayCopyDisplayMode(self->_display);
                printf("cadence_config pixels=%zux%zu refresh=%.6f queue_depth=3\n",
                       self->_width, self->_height, mode ? CGDisplayModeGetRefreshRate(mode) : 0);
                if (mode) CGDisplayModeRelease(mode);
                self->_stream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:self];
                if (![self->_stream addStreamOutput:self type:SCStreamOutputTypeScreen
                        sampleHandlerQueue:self->_queue error:NULL]) { [self finish:3]; return; }
                [self->_stream startCaptureWithCompletionHandler:^(NSError *startError) {
                    dispatch_async(self->_queue, ^{
                        if (self->_stopping) return;
                        if (startError) { [self finish:3]; return; }
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 25*NSEC_PER_SEC), self->_queue, ^{
                            if (CGMainDisplayID() != self->_display || !CGDisplayIsActive(self->_display))
                                [self finish:3];
                            else [self finish:self->_complete ? 0 : 5];
                        });
                    });
                }];
            });
        }];
    });
}
@end

int main(int argc, const char **argv) {
    if (argc != 2 || (strcmp(argv[1], "--cadence-60") && strcmp(argv[1], "--cadence-native") &&
        strcmp(argv[1], "--cadence-pattern-60") && strcmp(argv[1], "--cadence-pattern-native"))) return 2;
    alarm(35); // Bound framework setup/teardown too; runner is the outer guard.
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        PLANKCaptureCadence *probe = [PLANKCaptureCadence new];
        probe.nativeRate = strstr(argv[1], "native") != NULL;
        probe.animatedPattern = strstr(argv[1], "pattern") != NULL; probe.result = 4;
        dispatch_async(dispatch_get_main_queue(), ^{ [probe begin]; });
        CFRunLoopRun();
        return probe.result;
    }
}
