// SPDX-License-Identifier: GPL-3.0-or-later
// Bounded ScreenCaptureKit probe. Reports metadata only, never writes pixels.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreVideo/CoreVideo.h>
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <string.h>
#import "virtual-display-probe.h"

int PLANKRunInputProbe(void);
#import "display-owner-probe.h"
int PLANKRunCaptureEncodeProbe(BOOL hevc, BOOL pattern, BOOL owned4K);
int PLANKRunFullRangeQualification(BOOL capture444);
int PLANKRunMediaOwnerQualification(BOOL crashOwner);
int PLANKRunSessionBoundaryQualification(BOOL injectBoundary, BOOL handoff);
int PLANKRunSessionTimingQualification(const char *mode);
int PLANKRunSpeedChartQualification(void);
int PLANKRunMixedChartQualification(BOOL speed);
int PLANKRunPointerProbe(CGEventSourceStateID state, CGEventTapLocation tap);

@interface PLANKCaptureProbe : NSObject <SCStreamOutput, SCStreamDelegate>
@property(nonatomic, strong) SCStream *stream;
@property(nonatomic) NSUInteger completeFrames;
@property(nonatomic) NSUInteger idleFrames;
@property(nonatomic) BOOL stopping;
@property(nonatomic) int result;
@property(nonatomic) CGDirectDisplayID targetDisplay;
@property(nonatomic) BOOL requiresOwnedDimensions;
- (void)begin;
- (void)finish:(int)result;
@end

@implementation PLANKCaptureProbe
/** All mutable state runs on the main queue, including capture callbacks. */
- (void)finish:(int)result {
    if (self.stopping) return;
    self.stopping = YES;
    self.result = result;
    printf("complete_frames=%lu idle_frames=%lu result=%d\n",
           (unsigned long)self.completeFrames, (unsigned long)self.idleFrames, result);
    if (!self.stream) {
        CFRunLoopStop(CFRunLoopGetMain());
        return;
    }
    [self.stream stopCaptureWithCompletionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                fprintf(stderr, "capture_stop_error=%s code=%ld\n",
                        error.domain.UTF8String, (long)error.code);
                self.result = 4;
            }
            CFRunLoopStop(CFRunLoopGetMain());
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        self.result = 4;
        CFRunLoopStop(CFRunLoopGetMain());
    });
}

/** Inspect complete IOSurface-backed frames without a CPU pixel mapping. */
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample
        ofType:(SCStreamOutputType)type {
    (void)stream;
    if (self.stopping || type != SCStreamOutputTypeScreen ||
        !CMSampleBufferIsValid(sample)) return;
    NSArray *attachments = (__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample, false);
    NSNumber *status = attachments.firstObject[SCStreamFrameInfoStatus];
    if (!status) return;
    if (status.integerValue == SCFrameStatusIdle) { self.idleFrames++; return; }
    if (status.integerValue != SCFrameStatusComplete) return;
    CVPixelBufferRef pixel = CMSampleBufferGetImageBuffer(sample);
    if (!pixel) return;
    self.completeFrames++;
    OSType format = CVPixelBufferGetPixelFormatType(pixel);
    printf("frame=%lu pixels=%zux%zu format=%c%c%c%c iosurface=%d pts=%.6f\n",
           (unsigned long)self.completeFrames,
           CVPixelBufferGetWidth(pixel), CVPixelBufferGetHeight(pixel),
           (int)((format >> 24) & 255), (int)((format >> 16) & 255),
           (int)((format >> 8) & 255), (int)(format & 255),
           CVPixelBufferGetIOSurface(pixel) != NULL,
           CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)));
    if (CVPixelBufferGetIOSurface(pixel) == NULL || format != kCVPixelFormatType_32BGRA ||
        (self.requiresOwnedDimensions &&
         (CVPixelBufferGetWidth(pixel) != 1920 || CVPixelBufferGetHeight(pixel) != 1080))) {
        [self finish:3];
    } else if (self.completeFrames >= 10) {
        [self finish:0];
    }
}

/** Unexpected capture termination is a failed qualification, not EOF success. */
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    (void)stream;
    dispatch_async(dispatch_get_main_queue(), ^{
        fprintf(stderr, "capture_error=%s code=%ld\n", error.domain.UTF8String, (long)error.code);
        [self finish:3];
    });
}

/** Capture the exact selected display; never silently substitute the main one. */
- (void)begin {
    printf("probe_build=%s\n",
           [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] UTF8String]);
    printf("capture_preflight=%d input_preflight=%d\n",
           CGPreflightScreenCaptureAccess(), CGPreflightPostEventAccess());
    [SCShareableContent getShareableContentExcludingDesktopWindows:NO
        onScreenWindowsOnly:YES completionHandler:^(SCShareableContent *content, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.stopping) return;
            if (error) {
                fprintf(stderr, "shareable_content_error=%s code=%ld\n",
                        error.domain.UTF8String, (long)error.code);
                [self finish:2];
                return;
            }
            SCDisplay *selected = nil;
            for (SCDisplay *display in content.displays) {
                if (display.displayID == self.targetDisplay) selected = display;
            }
            if (!selected) { [self finish:2]; return; }
            printf("capture_display=%u owned=%d\n", selected.displayID, self.requiresOwnedDimensions);
            CGDisplayModeRef mode = CGDisplayCopyDisplayMode(selected.displayID);
            if (!mode) { [self finish:2]; return; }
            SCStreamConfiguration *configuration = [[SCStreamConfiguration alloc] init];
            configuration.width = CGDisplayModeGetPixelWidth(mode);
            configuration.height = CGDisplayModeGetPixelHeight(mode);
            CGDisplayModeRelease(mode);
            configuration.minimumFrameInterval = CMTimeMake(1, 60);
            configuration.queueDepth = 3;
            configuration.pixelFormat = kCVPixelFormatType_32BGRA;
            configuration.showsCursor = YES;
            configuration.capturesAudio = NO;
            SCContentFilter *filter = [[SCContentFilter alloc]
                initWithDisplay:selected excludingWindows:@[]];
            self.stream = [[SCStream alloc] initWithFilter:filter
                configuration:configuration delegate:self];
            NSError *outputError = nil;
            if (![self.stream addStreamOutput:self type:SCStreamOutputTypeScreen
                sampleHandlerQueue:dispatch_get_main_queue() error:&outputError]) {
                fprintf(stderr, "add_output_error=%ld\n", (long)outputError.code);
                [self finish:3];
                return;
            }
            [self.stream startCaptureWithCompletionHandler:^(NSError *startError) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (startError) {
                        fprintf(stderr, "start_capture_error=%s code=%ld\n",
                                startError.domain.UTF8String, (long)startError.code);
                        [self finish:3];
                    }
                });
            }];
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{
            // A static desktop can legitimately produce only one complete frame.
            [self finish:self.completeFrames > 0 ? 0 : 5];
        });
}
@end

/** Interactive consent setup; it never captures pixels or posts input. */
@interface PLANKPermissionSetup : NSObject <NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSTimer *timer;
- (void)show;
@end

@implementation PLANKPermissionSetup
- (void)refresh {
    self.statusLabel.stringValue = [NSString stringWithFormat:
        @"Screen recording: %@\nDevice control: %@\nEvent posting: %@",
        CGPreflightScreenCaptureAccess() ? @"Allowed" : @"Not yet allowed",
        AXIsProcessTrusted() ? @"Allowed" : @"Not yet allowed",
        CGPreflightPostEventAccess() ? @"Allowed" : @"Not yet allowed"];
}
- (void)requestControl:(id)sender {
    (void)sender;
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    BOOL trusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    printf("device_control_request_issued=1 trusted_now=%d prompt_is_asynchronous=1\n", trusted);
    [self refresh];
}
- (void)requestCapture:(id)sender {
    (void)sender;
    (void)CGRequestScreenCaptureAccess();
    [self refresh];
}
- (void)openSettings:(id)sender {
    (void)sender;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:
        @"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}
- (void)quit:(id)sender {
    (void)sender;
    [self.timer invalidate];
    [NSApp terminate:nil];
}
- (BOOL)windowShouldClose:(NSWindow *)sender {
    [self quit:sender];
    return YES;
}
- (void)show {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 570, 290)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"PLANK Host Probe — Permissions";
    self.window.delegate = self;
    self.window.releasedWhenClosed = NO;
    NSTextField *instructions = [NSTextField wrappingLabelWithString:
        @"Approve PLANK Host Probe in the macOS permission prompt.\nIf macOS does not repeat the prompt, use Open Settings and enable it under Device Control and Data Access. This setup does not capture or control your desktop."];
    instructions.frame = NSMakeRect(20, 185, 530, 85);
    [self.window.contentView addSubview:instructions];
    self.statusLabel = [NSTextField wrappingLabelWithString:@""];
    self.statusLabel.frame = NSMakeRect(20, 105, 530, 70);
    [self.window.contentView addSubview:self.statusLabel];
    NSArray<NSString *> *titles = @[@"Request Control", @"Request Recording", @"Open Settings", @"Quit"];
    SEL actions[] = {@selector(requestControl:), @selector(requestCapture:), @selector(openSettings:), @selector(quit:)};
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSButton *button = [NSButton buttonWithTitle:titles[i] target:self action:actions[i]];
        button.frame = NSMakeRect(15 + 138 * i, 35, 135, 32);
        [self.window.contentView addSubview:button];
    }
    [self refresh];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
        selector:@selector(refresh) userInfo:nil repeats:YES];
    // Request once after the event loop starts. Never re-prompt from the timer.
    dispatch_async(dispatch_get_main_queue(), ^{ [self requestControl:nil]; });
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        setbuf(stdout, NULL);
        if (argc == 2 && strcmp(argv[1], "--encode-session") == 0) return PLANKRunSessionBoundaryQualification(NO, NO);
        if (argc == 2 && strcmp(argv[1], "--encode-session-revoke") == 0) return PLANKRunSessionBoundaryQualification(YES, NO);
        if (argc == 2 && strcmp(argv[1], "--handoff-session") == 0) return PLANKRunSessionBoundaryQualification(NO, YES);
        if (argc == 3 && strcmp(argv[1], "--handoff-session") == 0) return PLANKRunSessionTimingQualification(argv[2]);
        if (argc == 4 && strcmp(argv[1], "--handoff-display-owner") == 0) {
            if (strcmp(argv[2], "3840") == 0 && strcmp(argv[3], "2160") == 0) return PLANKRunDisplayOwner(3840, 2160, YES);
            if (strcmp(argv[2], "1920") == 0 && strcmp(argv[3], "1080") == 0) return PLANKRunDisplayOwner(1920, 1080, YES);
            return 2;
        }
        if (argc == 2 && strcmp(argv[1], "--encode-owned-replace") == 0) return PLANKRunMediaOwnerQualification(NO);
        if (argc == 2 && strcmp(argv[1], "--encode-owned-crash") == 0) return PLANKRunMediaOwnerQualification(YES);
        if (argc == 4 && strcmp(argv[1], "--display-owner") == 0) {
            if (strcmp(argv[2], "3840") == 0 && strcmp(argv[3], "2160") == 0) return PLANKRunDisplayOwner(3840, 2160, NO);
            if (strcmp(argv[2], "1920") == 0 && strcmp(argv[3], "1080") == 0) return PLANKRunDisplayOwner(1920, 1080, NO);
            return 2;
        }
        if (argc == 2 && strcmp(argv[1], "--encode-h264-owned") == 0) return PLANKRunCaptureEncodeProbe(NO, NO, YES);
        if (argc == 2 && strcmp(argv[1], "--encode-hevc-owned") == 0) return PLANKRunCaptureEncodeProbe(YES, NO, YES);
        if (argc == 2 && strcmp(argv[1], "--encode-h264") == 0) return PLANKRunCaptureEncodeProbe(NO, NO, NO);
        if (argc == 2 && strcmp(argv[1], "--encode-hevc") == 0) return PLANKRunCaptureEncodeProbe(YES, NO, NO);
        if (argc == 2 && strcmp(argv[1], "--encode-hevc-full-range") == 0) return PLANKRunFullRangeQualification(NO);
        if (argc == 2 && strcmp(argv[1], "--encode-hevc-full-range-444") == 0) return PLANKRunFullRangeQualification(YES);
        if (argc == 2 && strcmp(argv[1], "--pattern-h264") == 0) return PLANKRunCaptureEncodeProbe(NO, YES, NO);
        if (argc == 2 && strcmp(argv[1], "--pattern-hevc") == 0) return PLANKRunCaptureEncodeProbe(YES, YES, NO);
        if (argc == 2 && strcmp(argv[1], "--pattern-h264-2160") == 0) return PLANKRunCaptureEncodeProbe(NO, YES, YES);
        if (argc == 2 && strcmp(argv[1], "--pattern-hevc-2160") == 0) return PLANKRunCaptureEncodeProbe(YES, YES, YES);
        if (argc == 2 && strcmp(argv[1], "--pattern-hevc-2160-speed") == 0) return PLANKRunSpeedChartQualification();
        if (argc == 2 && strcmp(argv[1], "--pattern-hevc-2160-mixed") == 0) return PLANKRunMixedChartQualification(NO);
        if (argc == 2 && strcmp(argv[1], "--pattern-hevc-2160-mixed-speed") == 0) return PLANKRunMixedChartQualification(YES);
        if (argc == 2 && strcmp(argv[1], "--input") == 0) return PLANKRunInputProbe();
        if (argc == 2 && strcmp(argv[1], "--pointer") == 0)
            return PLANKRunPointerProbe(kCGEventSourceStateHIDSystemState, kCGHIDEventTap);
        if (argc == 2 && strcmp(argv[1], "--pointer-session") == 0)
            return PLANKRunPointerProbe(kCGEventSourceStateCombinedSessionState, kCGSessionEventTap);
        if (argc == 1 || (argc == 2 && strcmp(argv[1], "--request-permissions") == 0)) {
            [NSApplication sharedApplication];
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
            [NSApp activateIgnoringOtherApps:YES];
            PLANKPermissionSetup *setup = [[PLANKPermissionSetup alloc] init];
            [setup show];
            [NSApp run];
            return 0;
        }
        BOOL owned = argc == 2 && strcmp(argv[1], "--capture-virtual") == 0;
        if (argc != 2 || (!owned && strcmp(argv[1], "--capture") != 0)) {
            fprintf(stderr, "Usage: plank-host-probe [--request-permissions | --capture | --capture-virtual | --input | --pointer | --pointer-session | --encode-h264 | --encode-hevc | --pattern-h264 | --pattern-hevc]\n");
            return 2;
        }
        PLANKVirtualDisplay *display = nil;
        CGDirectDisplayID target = CGMainDisplayID();
        if (owned) {
            if (!CGPreflightScreenCaptureAccess()) return 2;
            display = createProbeDisplay(1920, 1080);
            if (!display) return 3;
            target = display.displayID;
        }
        PLANKCaptureProbe *probe = [[PLANKCaptureProbe alloc] init];
        probe.result = 5;
        probe.targetDisplay = target;
        probe.requiresOwnedDimensions = owned;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, owned ? 2 * NSEC_PER_SEC : 0),
            dispatch_get_main_queue(), ^{
                if (owned && !report(target, 1920, 1080)) [probe finish:3];
                else [probe begin];
            });
        CFRunLoopRun();
        if (owned) {
            // Stop the stream before releasing its display; keep recovery displays intact.
            probe.stream = nil;
            display = nil;
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
            while (onlineState(target) != 0 && deadline.timeIntervalSinceNow > 0) {
                [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            }
            BOOL gone = onlineState(target) == 0;
            printf("owned_display_removed=%d\n", gone);
            if (!gone) probe.result = 6;
        }
        return probe.result;
    }
}
