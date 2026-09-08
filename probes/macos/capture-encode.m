// SPDX-License-Identifier: GPL-3.0-or-later
// Bounded live SCK -> VideoToolbox; pixel readback/keyframe output only in chart validation.
#import <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreGraphics/CoreGraphics.h>
#include <mach/mach_time.h>
#include <unistd.h>
#include <math.h>
#import "pattern-validation.h"
#import "display-owner-probe.h"
#import "session-boundary.h"
#include <notify.h>
#include <signal.h>

static double hostSeconds(void) {
    return CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()));
}

// Selected once by the explicit diagnostic entry point before any queue starts.
// Normal media and handoff entry points leave both disabled.
static BOOL timingRetainSample = NO, timingSyntheticPTS = NO;
static BOOL timingRelativePTS = NO;
static BOOL timingLowLatency = NO;
static BOOL timingEncodingSpeed = NO;
static BOOL chartMixedCadence = NO;
static BOOL qualifyFullRange = NO;
static BOOL qualifyFullRange444 = NO;
static BOOL qualifyMain44410 = NO;

// Fixed one-second records, emitted only after capture stops. Updates stay on
// the existing serial queue; no tracing thread, frame log or pixel readback.
typedef struct {
    NSUInteger complete, overflow, callbacks;
    double submitMax, callbackMax, callbackDispatchMax;
} PLANKTimingBucket;

@interface PLANKCaptureEncodeProbe : NSObject <SCStreamOutput, SCStreamDelegate> {
    PLANKTimingBucket _timing[181];
}
@property(nonatomic) BOOL hevc;
@property(nonatomic) BOOL pattern, sourceColorPassed;
@property(nonatomic, strong) PLANKPatternValidator *validator;
@property(nonatomic, strong) PLANKDisplayOwnerProbe *ownerToCrash;
@property(nonatomic) CGDirectDisplayID displayID;
@property(nonatomic, strong) SCStream *stream;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) dispatch_queue_t validationQueue;
@property(nonatomic) BOOL validationPending, validationPassed;
@property(nonatomic) VTCompressionSessionRef encoder;
@property(nonatomic) size_t width, height;
@property(nonatomic) size_t expectedWidth, expectedHeight;
@property(nonatomic) OSType pixelFormat;
@property(nonatomic) NSUInteger submitted, encoded, idle, overflow, dropped, inFlight, peakInFlight;
@property(nonatomic) NSUInteger outputBytes;
@property(nonatomic) NSUInteger unavailableDisplayTimes;
@property(nonatomic) CMTime firstInputPTS, lastInputPTS, lastOutputPTS;
@property(nonatomic) BOOL stopping, stopped, finished;
@property(nonatomic) BOOL sessionGuarded, injectSessionBoundary, sessionRevoked;
@property(nonatomic) BOOL handoffQualification;
@property(nonatomic) int result;
@property(nonatomic) double started;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *encodeTimes;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *captureAges;
- (void)begin;
- (void)stop:(int)result;
- (void)finishIfDrained;
- (PLANKTimingBucket *)timingBucket;
@end

@implementation PLANKCaptureEncodeProbe
- (PLANKTimingBucket *)timingBucket {
    if (!self.handoffQualification) return NULL;
    NSUInteger second = (NSUInteger)MAX(0.0, hostSeconds() - self.started);
    return &_timing[MIN(second, (NSUInteger)180)];
}

- (BOOL)prepareEncoder {
    NSMutableDictionary *spec = [@{(__bridge NSString *)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: @YES} mutableCopy];
    if (timingLowLatency)
        spec[(__bridge NSString *)kVTVideoEncoderSpecification_EnableLowLatencyRateControl] = @YES;
    NSDictionary *source = @{
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(self.pixelFormat),
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    OSStatus status = VTCompressionSessionCreate(NULL, (int32_t)self.width, (int32_t)self.height,
        self.hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264,
        (__bridge CFDictionaryRef)spec, (__bridge CFDictionaryRef)source,
        NULL, NULL, NULL, &_encoder);
    if (status) { fprintf(stderr, "encoder_create_status=%d\n", status); return NO; }
    // Fixed qualification inputs only, not product defaults or bookmark policy.
    NSDictionary *properties = @{
        (__bridge NSString *)kVTCompressionPropertyKey_RealTime: @YES,
        (__bridge NSString *)kVTCompressionPropertyKey_AllowFrameReordering: @NO,
        (__bridge NSString *)kVTCompressionPropertyKey_ExpectedFrameRate: @60,
        (__bridge NSString *)kVTCompressionPropertyKey_MaxKeyFrameInterval: @120,
        (__bridge NSString *)kVTCompressionPropertyKey_AverageBitRate: @20000000,
        (__bridge NSString *)kVTCompressionPropertyKey_ProfileLevel: (__bridge NSString *)(qualifyMain44410 ?
            CFSTR("HEVC_Main44410_AutoLevel") : (self.hevc ?
            kVTProfileLevel_HEVC_Main10_AutoLevel : kVTProfileLevel_H264_High_AutoLevel)),
        (__bridge NSString *)kVTCompressionPropertyKey_ColorPrimaries: (__bridge NSString *)kCVImageBufferColorPrimaries_ITU_R_709_2,
        (__bridge NSString *)kVTCompressionPropertyKey_TransferFunction: (__bridge NSString *)kCVImageBufferTransferFunction_sRGB,
        (__bridge NSString *)kVTCompressionPropertyKey_YCbCrMatrix: (__bridge NSString *)kCVImageBufferYCbCrMatrix_ITU_R_709_2
    };
    status = VTSessionSetProperties(self.encoder, (__bridge CFDictionaryRef)properties);
    if (!status && timingEncodingSpeed)
        status = VTSessionSetProperty(self.encoder, kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, kCFBooleanTrue);
    if (!status) status = VTCompressionSessionPrepareToEncodeFrames(self.encoder);
    CFTypeRef hardware = NULL;
    if (!status) status = VTSessionCopyProperty(self.encoder,
        kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder, NULL, &hardware);
    BOOL accelerated = hardware && CFEqual(hardware, kCFBooleanTrue);
    if (hardware) CFRelease(hardware);
    printf("encoder_codec=%s requested_profile=%s hardware=%d status=%d\n",
        self.hevc ? "HEVC" : "H264", qualifyMain44410 ? "Main44410" : (self.hevc ? "Main10" : "High"), accelerated, status);
    return status == 0 && accelerated;
}

- (void)begin {
    self.started = hostSeconds();
    self.firstInputPTS = self.lastInputPTS = self.lastOutputPTS = kCMTimeInvalid;
    self.encodeTimes = [NSMutableArray array];
    self.captureAges = [NSMutableArray array];
    self.pixelFormat = self.hevc ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange :
                                 kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
    if (qualifyFullRange) self.pixelFormat = kCVPixelFormatType_420YpCbCr10BiPlanarFullRange;
    if (qualifyFullRange444) self.pixelFormat = kCVPixelFormatType_444YpCbCr10BiPlanarFullRange;
    printf("capture_encode_build=%s capture_preflight=%d display=%u\n",
        [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] UTF8String],
        CGPreflightScreenCaptureAccess(), self.displayID);
    if (self.handoffQualification)
        printf("timing_variant retain_sample=%d synthetic_pts=%d relative_pts=%d low_latency=%d encoding_speed=%d\n",
            timingRetainSample, timingSyntheticPTS, timingRelativePTS, timingLowLatency, timingEncodingSpeed);
    if (!CGPreflightScreenCaptureAccess()) { [self stop:2]; return; }
    [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:YES
        completionHandler:^(SCShareableContent *content, NSError *error) {
        dispatch_async(self.queue, ^{
            if (self.stopping) return;
            if (error) { fprintf(stderr, "content_error=%ld\n", (long)error.code); [self stop:2]; return; }
            SCDisplay *selected = nil;
            for (SCDisplay *display in content.displays)
                if (display.displayID == self.displayID) selected = display;
            if (!selected) { [self stop:2]; return; }
            SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:selected excludingWindows:@[]];
            // SCK reports content in points plus its backing scale. Ask the
            // capture API for actual source pixels, not a cached CG mode object
            // or requested dimensions which would silently enable rescaling.
            double sourceWidth = filter.contentRect.size.width * filter.pointPixelScale;
            double sourceHeight = filter.contentRect.size.height * filter.pointPixelScale;
            if (!isfinite(sourceWidth) || !isfinite(sourceHeight) || sourceWidth <= 0 || sourceHeight <= 0 ||
                sourceWidth > 8192 || sourceHeight > 8192 || sourceWidth != floor(sourceWidth) || sourceHeight != floor(sourceHeight)) {
                [self stop:2]; return;
            }
            self.width = (size_t)sourceWidth;
            self.height = (size_t)sourceHeight;
            printf("capture_source_geometry points=%.0fx%.0f scale=%.3f pixels=%zux%zu\n",
                filter.contentRect.size.width, filter.contentRect.size.height, filter.pointPixelScale, self.width, self.height);
            if (self.expectedWidth && (self.width != self.expectedWidth || self.height != self.expectedHeight)) {
                fprintf(stderr, "capture_source_geometry_mismatch\n"); [self stop:2]; return;
            }
            if (!self.width || !self.height || self.width > 8192 || self.height > 8192 ||
                self.width % 2 || self.height % 2 || ![self prepareEncoder]) { [self stop:3]; return; }
            SCStreamConfiguration *configuration = [[SCStreamConfiguration alloc] init];
            configuration.width = self.width;
            configuration.height = self.height;
            configuration.minimumFrameInterval = qualifyMain44410 ? kCMTimeZero : CMTimeMake(1, 60);
            configuration.queueDepth = 3;
            configuration.pixelFormat = self.pixelFormat;
            configuration.colorSpaceName = kCGColorSpaceSRGB;
            // SDK documents colorMatrix only for 420v/420f; inspect x420 attachments.
            if (!self.hevc) configuration.colorMatrix = kCGDisplayStreamYCbCrMatrix_ITU_R_709_2;
            configuration.captureDynamicRange = SCCaptureDynamicRangeSDR;
            configuration.showsCursor = !self.pattern;
            configuration.capturesAudio = NO;
            self.stream = [[SCStream alloc] initWithFilter:filter configuration:configuration delegate:self];
            NSError *outputError = nil;
            if (![self.stream addStreamOutput:self type:SCStreamOutputTypeScreen
                sampleHandlerQueue:self.queue error:&outputError]) { [self stop:3]; return; }
            [self.stream startCaptureWithCompletionHandler:^(NSError *startError) {
                dispatch_async(self.queue, ^{
                    if (startError) { fprintf(stderr, "start_error=%ld\n", (long)startError.code); [self stop:3]; }
                });
            }];
        });
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (self.handoffQualification ? 180 : 15) * NSEC_PER_SEC), self.queue, ^{ [self stop:0]; });
}

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    (void)stream;
    if (self.stopping || type != SCStreamOutputTypeScreen || !CMSampleBufferIsValid(sample)) return;
    NSArray *attachments = (__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample, false);
    NSNumber *status = attachments.firstObject[SCStreamFrameInfoStatus];
    if (!status) return;
    if (status.integerValue == SCFrameStatusIdle) { self.idle++; return; }
    if (status.integerValue != SCFrameStatusComplete) return;
    CVPixelBufferRef pixel = CMSampleBufferGetImageBuffer(sample);
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sample);
    if (!pixel || CVPixelBufferGetIOSurface(pixel) == NULL ||
        CVPixelBufferGetPixelFormatType(pixel) != self.pixelFormat ||
        CVPixelBufferGetWidth(pixel) != self.width || CVPixelBufferGetHeight(pixel) != self.height ||
        !CMTIME_IS_NUMERIC(pts) || (CMTIME_IS_VALID(self.lastInputPTS) && CMTimeCompare(pts, self.lastInputPTS) <= 0)) {
        fprintf(stderr, "capture_surface_or_pts_mismatch requested_format=%08x actual_format=%08x\n",
            (unsigned)self.pixelFormat, pixel ? (unsigned)CVPixelBufferGetPixelFormatType(pixel) : 0);
        [self stop:4]; return;
    }
    if (!self.submitted) {
        printf("capture_surface=%s pixels=%zux%zu iosurface=1 encode_path_cpu_pixel_maps=0 app_pixel_copies=0 chart_readback=%d\n",
            qualifyFullRange444 ? "xf44" : (qualifyFullRange ? "xf20" : (self.hevc ? "x420" : "420v")),
            self.width, self.height, self.pattern);
        const CFStringRef keys[] = {kCVImageBufferColorPrimariesKey, kCVImageBufferTransferFunctionKey,
                                   kCVImageBufferYCbCrMatrixKey};
        for (unsigned int i = 0; i < 3; i++) {
            CFTypeRef value = CVBufferCopyAttachment(pixel, keys[i], NULL);
            printf("capture_color_%u=%s\n", i, value ? [(__bridge id)value description].UTF8String : "missing");
            if (value) CFRelease(value);
        }
    }
    PLANKTimingBucket *timing = [self timingBucket];
    if (timing) timing->complete++;
    if (self.inFlight >= 3) {
        self.overflow++;
        if (timing) timing->overflow++;
        return;
    }
    {
        // Probe-only measured contract on this beta: requested sRGB samples are
        // tagged BT.709 transfer in 420v and untagged/BT.601-matrix in x420.
        // Declare actual sample meaning, not intended encoder output. The chart
        // must qualify this choice; this is not a production OS-version rule.
        CVBufferSetAttachment(pixel, kCVImageBufferColorPrimariesKey,
            kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
        CVBufferSetAttachment(pixel, kCVImageBufferTransferFunctionKey,
            kCVImageBufferTransferFunction_sRGB, kCVAttachmentMode_ShouldPropagate);
        CVBufferSetAttachment(pixel, kCVImageBufferYCbCrMatrixKey,
            self.hevc ? kCVImageBufferYCbCrMatrix_ITU_R_601_4 : kCVImageBufferYCbCrMatrix_ITU_R_709_2,
            kCVAttachmentMode_ShouldPropagate);
    }
    if (!self.submitted) self.firstInputPTS = pts;
    self.lastInputPTS = pts;
    self.submitted++;
    self.inFlight++;
    self.peakInFlight = MAX(self.peakInFlight, self.inFlight);
    double before = hostSeconds();
    // Presentation timestamps are for media ordering, not an assumed host clock.
    // SCK explicitly documents displayTime as mach absolute WindowServer time.
    NSNumber *displayTime = attachments.firstObject[SCStreamFrameInfoDisplayTime];
    uint64_t now = mach_absolute_time();
    uint64_t displayed = [displayTime isKindOfClass:NSNumber.class] ? displayTime.unsignedLongLongValue : 0;
    if (displayed && displayed <= now) {
        mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);
        double age = (now - displayed) * (double)timebase.numer / timebase.denom / 1e6;
        [self.captureAges addObject:@(age)];
    } else self.unavailableDisplayTimes++;
    BOOL verifyChart = self.pattern && self.submitted == 30;
    NSArray<NSNumber *> *reference = verifyChart ? PLANKReadPatternSamples(pixel) : nil;
    if (verifyChart) {
        if (qualifyMain44410) {
            // Measure both hypotheses before accepting the source contract.
            (void)PLANKPatternReferenceRangeError(reference, YES, NO, YES);
        }
        self.sourceColorPassed = PLANKPatternReferenceRangeError(reference, self.hevc, self.hevc, qualifyFullRange) <= 4;
        if (self.hevc) reference = PLANKPatternMap601To709Range(reference, YES, qualifyFullRange);
    }
    NSDictionary *frameProperties = verifyChart ? @{(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES} : nil;
    // Diagnostic only: retaining the enclosing sample tests SCK lifetime without
    // mapping/copying pixels. ARC captures the lease until the VT handler ends,
    // including safe disposal if submission fails without invoking the handler.
    id sampleLease = timingRetainSample ? (__bridge id)sample : nil;
    CMTime encodePTS = timingSyntheticPTS ? CMTimeMake((int64_t)self.submitted - 1, 60) : pts;
    if (timingRelativePTS) encodePTS = CMTimeSubtract(pts, self.firstInputPTS);
    // VT retains this exact buffer as needed. No lock, map, copy or transfer stage.
    OSStatus encodeStatus = VTCompressionSessionEncodeFrameWithOutputHandler(self.encoder, pixel,
        encodePTS, kCMTimeInvalid, (__bridge CFDictionaryRef)frameProperties, NULL, ^(OSStatus callbackStatus, VTEncodeInfoFlags flags, CMSampleBufferRef encoded) {
        double callbackAt = hostSeconds();
        double elapsed = (callbackAt - before) * 1000;
        BOOL valid = callbackStatus == 0 && !(flags & kVTEncodeInfo_FrameDropped) && encoded &&
            CMSampleBufferDataIsReady(encoded) && CMSampleBufferGetNumSamples(encoded) == 1;
        CMTime outputPTS = encoded ? CMSampleBufferGetPresentationTimeStamp(encoded) : kCMTimeInvalid;
        size_t bytes = encoded ? CMSampleBufferGetTotalSampleSize(encoded) : 0;
        valid = valid && bytes > 0 && CMTIME_IS_NUMERIC(outputPTS) && CMTimeCompare(outputPTS, encodePTS) == 0;
        if (sampleLease && !CMSampleBufferIsValid((__bridge CMSampleBufferRef)sampleLease)) valid = NO;
        if (verifyChart && encoded) CFRetain(encoded);
        dispatch_async(self.queue, ^{
            if (self.finished) { if (verifyChart && encoded) CFRelease(encoded); return; }
            PLANKTimingBucket *completed = [self timingBucket];
            if (completed) {
                completed->callbacks++;
                completed->callbackMax = MAX(completed->callbackMax, elapsed);
                completed->callbackDispatchMax = MAX(completed->callbackDispatchMax,
                    (hostSeconds() - callbackAt) * 1000);
            }
            if (self.inFlight) self.inFlight--;
            if (!valid || (CMTIME_IS_VALID(self.lastOutputPTS) && CMTimeCompare(outputPTS, self.lastOutputPTS) <= 0)) {
                self.dropped++; [self stop:4];
            } else {
                self.lastOutputPTS = outputPTS;
                self.encoded++;
                if (self.handoffQualification && self.encoded == 1)
                    printf("first_encoded_frame pixels=%zux%zu\n", self.width, self.height);
                if (self.injectSessionBoundary && !self.sessionRevoked) {
                    self.sessionRevoked = YES;
                    printf("session_boundary_revoked reason=synthetic-test encoded_before_revoke=%lu\n", (unsigned long)self.encoded);
                    [self stop:10];
                }
                if (self.ownerToCrash) {
                    PLANKDisplayOwnerProbe *owner = self.ownerToCrash;
                    self.ownerToCrash = nil;
                    dispatch_async(dispatch_get_main_queue(), ^{ [owner crashForQualification]; });
                }
                self.outputBytes += bytes;
                [self.encodeTimes addObject:@(elapsed)];
                if (verifyChart && !self.sourceColorPassed) {
                    // Never persist an arbitrary desktop keyframe if chart placement
                    // failed. This also leaves the color gate explicitly failed.
                    fprintf(stderr, "chart_not_verified_skipping_decode_and_artifact\n");
                    [self stop:6];
                } else if (verifyChart) {
                    self.validator = [[PLANKPatternValidator alloc] init];
                    self.validationPending = YES;
                    CFRetain(encoded);
                    dispatch_async(self.validationQueue, ^{
                        [self.validator decode:encoded reference:reference pixelFormat:self.pixelFormat
                            queue:self.validationQueue completion:^{
                                BOOL passed = self.validator.passed;
                                dispatch_async(self.queue, ^{
                                    self.validationPending = NO;
                                    self.validationPassed = passed;
                                    [self finishIfDrained];
                                });
                            }];
                        CFRelease(encoded);
                    });
                }
            }
            if (verifyChart && encoded) CFRelease(encoded);
            [self finishIfDrained];
        });
    });
    if (timing) timing->submitMax = MAX(timing->submitMax, (hostSeconds() - before) * 1000);
    if (encodeStatus) {
        fprintf(stderr, "encode_submit_status=%d\n", encodeStatus);
        if (self.inFlight) self.inFlight--;
        [self stop:4];
    } else if (self.submitted >= (self.handoffQualification ? 10800 : (self.pattern || self.sessionGuarded ? 900 : 180))) [self stop:0];
}

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    (void)stream;
    dispatch_async(self.queue, ^{ fprintf(stderr, "capture_error=%ld\n", (long)error.code); [self stop:4]; });
}

- (void)stop:(int)result {
    if (self.finished) return;
    if (result) self.result = result;
    if (self.stopping) return;
    self.stopping = YES;
    if (self.handoffQualification)
        printf("capture_stop_elapsed_s=%.3f requested_result=%d\n", hostSeconds() - self.started, result);
    if (self.stream) {
        [self.stream stopCaptureWithCompletionHandler:^(NSError *error) {
            dispatch_async(self.queue, ^{
                if (error) self.result = 4;
                self.stopped = YES;
                [self finishIfDrained];
            });
        }];
    } else { self.stopped = YES; [self finishIfDrained]; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), self.queue, ^{
        if (!self.finished) {
            self.result = 5;
            self.stopped = YES;
            [self finishIfDrained];
        }
    });
}

- (void)finishIfDrained {
    if (self.finished || !self.stopping || !self.stopped || (self.inFlight && self.result != 5)) return;
    if (self.validationPending && self.result != 5) return;
    self.finished = YES;
    if (self.encoder) {
        VTCompressionSessionInvalidate(self.encoder);
        CFRelease(self.encoder);
        self.encoder = NULL;
    }
    if (!self.encoded || self.encoded != self.submitted || self.overflow || self.dropped) self.result = 4;
    if (self.pattern) {
        BOOL chartPassed = self.sourceColorPassed && !self.validationPending && self.validationPassed;
        printf("chart_color_gate=%d source_matches_declared_matrix=%d decoded_matches_expected_output=%d\n",
            chartPassed, self.sourceColorPassed, self.validationPassed);
        if (!chartPassed) self.result = 6;
        dispatch_sync(self.validationQueue, ^{ [self.validator invalidate]; });
    }
    printf("capture_encode submitted=%lu encoded=%lu idle=%lu overflow=%lu dropped=%lu peak_inflight=%lu bytes=%lu wall_s=%.3f result=%d\n",
        (unsigned long)self.submitted, (unsigned long)self.encoded, (unsigned long)self.idle,
        (unsigned long)self.overflow, (unsigned long)self.dropped, (unsigned long)self.peakInFlight,
        (unsigned long)self.outputBytes, hostSeconds() - self.started, self.result);
    double ptsSpan = CMTimeGetSeconds(CMTimeSubtract(self.lastInputPTS, self.firstInputPTS));
    printf("complete_frame_rate=%.3f pts_span_s=%.3f moving_chart=%d\n",
        ptsSpan > 0 ? (self.submitted - 1) / ptsSpan : 0, ptsSpan, self.pattern);
    NSArray *series = @[self.encodeTimes ?: @[], self.captureAges ?: @[]];
    for (unsigned int index = 0; index < 2; index++) {
        NSArray<NSNumber *> *sorted = [series[index] sortedArrayUsingSelector:@selector(compare:)];
        double sum = 0;
        for (NSNumber *value in sorted) sum += value.doubleValue;
        printf("%s count=%lu mean_ms=%.3f p95_ms=%.3f max_ms=%.3f\n",
            index ? "display_time_to_submit" : "encode_submit_to_callback",
            (unsigned long)sorted.count, sorted.count ? sum / sorted.count : 0,
            sorted.count ? sorted[(sorted.count * 95 - 1) / 100].doubleValue : 0, sorted.lastObject.doubleValue);
    }
    printf("unavailable_display_times=%lu color_and_decoded_precision_qualified=0 internal_framework_copies_unmeasured=1\n",
        (unsigned long)self.unavailableDisplayTimes);
    if (self.handoffQualification) {
        for (NSUInteger second = 0; second < 181; second++) {
            PLANKTimingBucket value = _timing[second];
            if (!value.complete && !value.callbacks) continue;
            printf("media_timing second=%lu complete=%lu overflow=%lu callbacks=%lu submit_max_ms=%.3f callback_max_ms=%.3f callback_dispatch_max_ms=%.3f\n",
                (unsigned long)second, (unsigned long)value.complete, (unsigned long)value.overflow,
                (unsigned long)value.callbacks, value.submitMax, value.callbackMax, value.callbackDispatchMax);
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{ CFRunLoopStop(CFRunLoopGetMain()); });
}
@end

static int runCaptureEncodeOnDisplay(BOOL hevc, BOOL pattern, CGDirectDisplayID target, PLANKDisplayOwnerProbe *owner,
                                    BOOL crashOwner, PLANKGraphicalSession session, BOOL injectBoundary) {
    NSWindow *chart = pattern ? PLANKCreatePatternWindow(target, chartMixedCadence) : nil;
    if (pattern && !chart) return 2;
    PLANKCaptureEncodeProbe *probe = [[PLANKCaptureEncodeProbe alloc] init];
    probe.hevc = hevc;
    probe.pattern = pattern;
    probe.sessionGuarded = session.phase != PLANKSessionUnavailable;
    probe.handoffQualification = owner.handoffQualification;
    probe.injectSessionBoundary = injectBoundary;
    probe.displayID = target;
    if (owner) {
        probe.expectedWidth = CGDisplayPixelsWide(target);
        probe.expectedHeight = CGDisplayPixelsHigh(target);
        if (!probe.expectedWidth || !probe.expectedHeight) { [chart close]; return 2; }
    }
    probe.ownerToCrash = crashOwner ? owner : nil;
    probe.queue = dispatch_queue_create("la.instinctual.PLANK.capture-encode-probe", DISPATCH_QUEUE_SERIAL);
    probe.validationQueue = dispatch_queue_create("la.instinctual.PLANK.chart-validator", DISPATCH_QUEUE_SERIAL);
    dispatch_source_t sessionWatch = nil;
    dispatch_source_t retireSignal = nil;
    int consoleToken = -1, userToken = -1;
    if (probe.sessionGuarded) {
        // Fail closed after a session notification, even if a rapid round trip
        // already restored the same UID. Never resume an old media authority.
        void (^revoke)(const char *) = ^(const char *reason) {
            if (!probe.sessionRevoked && !probe.finished) {
                probe.sessionRevoked = YES;
                printf("session_boundary_revoked reason=%s previous=%s\n", reason, PLANKSessionName(session.phase));
                [probe stop:probe.result ? probe.result : 10];
            }
        };
        uint32_t a = notify_register_dispatch(kCGNotifyGUIConsoleSessionChanged, &consoleToken,
            probe.queue, ^(int token) { (void)token; revoke("console-session-notification"); });
        uint32_t b = notify_register_dispatch(kCGNotifyGUISessionUserChanged, &userToken,
            probe.queue, ^(int token) { (void)token; revoke("session-user-notification"); });
        if (a || b) {
            if (!a) notify_cancel(consoleToken);
            if (!b) notify_cancel(userToken);
            [chart close];
            return 2;
        }
        sessionWatch = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, probe.queue);
        dispatch_source_set_timer(sessionWatch, DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(sessionWatch, ^{
            if (!PLANKSessionMatches(session, PLANKReadGraphicalSession())) revoke("session-identity-changed");
        });
        dispatch_resume(sessionWatch);
        if (probe.handoffQualification) {
            // Controller uses launchctl kill against its exact owned job label,
            // never a caller-provided PID or a public control endpoint.
            signal(SIGUSR1, SIG_IGN);
            retireSignal = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGUSR1, 0, probe.queue);
            dispatch_source_set_event_handler(retireSignal, ^{ revoke("controller-retire"); });
            dispatch_resume(retireSignal);
        }
    }
    dispatch_source_t ownerWatch = nil;
    if (owner) {
        ownerWatch = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(ownerWatch, DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(ownerWatch, ^{
            if (!owner.running) dispatch_async(probe.queue, ^{ [probe stop:8]; });
        });
        dispatch_resume(ownerWatch);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, pattern ? 2 * NSEC_PER_SEC : 0), probe.queue, ^{
        if (!probe.stopping) [probe begin];
    });
    CFRunLoopRun();
    if (sessionWatch) {
        dispatch_source_cancel(sessionWatch);
        notify_cancel(consoleToken);
        notify_cancel(userToken);
    }
    if (retireSignal) dispatch_source_cancel(retireSignal);
    if (ownerWatch) dispatch_source_cancel(ownerWatch);
    [chart orderOut:nil];
    [chart close];
    dispatch_sync(probe.queue, ^{
        printf("media_teardown capture_stopped=%d encoder_released=%d finished=%d\n",
            probe.stopped, probe.encoder == NULL, probe.finished);
        probe.stream = nil;
    });
    return probe.result;
}

static int runMediaGuarded(BOOL hevc, BOOL pattern, unsigned int ownedWidth, BOOL crashOwner,
                           PLANKGraphicalSession session, BOOL injectBoundary, BOOL handoff) {
    // The chart is desktop-only and must never cover the real login UI.
    if (pattern && geteuid() == 0) return 2;
    if (ownedWidth && !CGPreflightScreenCaptureAccess()) return 2;
    CGDirectDisplayID target = CGMainDisplayID();
    PLANKDisplayOwnerProbe *owner = nil;
    if (ownedWidth) {
        owner = [[PLANKDisplayOwnerProbe alloc] init];
        owner.handoffQualification = handoff;
        if (![owner startWidth:ownedWidth height:ownedWidth >= 3840 ? 2160 : 1080]) return 3;
        target = owner.displayID;
    }
    int result;
    @autoreleasepool {
        result = runCaptureEncodeOnDisplay(hevc, pattern, target, owner, crashOwner, session, injectBoundary);
    }
    // Stop SCK, drain/invalidate VT and release capture references before EOF.
    if (owner && ![owner stop]) return 7;
    return result;
}

static int runMedia(BOOL hevc, BOOL pattern, unsigned int ownedWidth, BOOL crashOwner) {
    return runMediaGuarded(hevc, pattern, ownedWidth, crashOwner,
        (PLANKGraphicalSession){PLANKSessionUnavailable, 0, 0}, NO, NO);
}

int PLANKRunSessionBoundaryQualification(BOOL injectBoundary, BOOL handoff) {
    if (handoff) signal(SIGUSR1, SIG_IGN); // Safe even during display startup.
    PLANKGraphicalSession session = PLANKReadGraphicalSession();
    if (handoff && session.phase == PLANKSessionUnavailable) {
        // A console announcement and launchd domain can precede Quartz/security
        // session readiness. Wait on the unchanged predicates in this agent;
        // never relaunch into another domain or treat the announcement as authority.
        printf("session_boundary_waiting_for_graphical_identity=1\n");
        __block PLANKGraphicalSession ready = session;
        double started = NSProcessInfo.processInfo.systemUptime;
        dispatch_source_t readiness = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(readiness, DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC, 5 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(readiness, ^{
            ready = PLANKReadGraphicalSession();
            if (ready.phase != PLANKSessionUnavailable || NSProcessInfo.processInfo.systemUptime - started >= 5)
                CFRunLoopStop(CFRunLoopGetMain());
        });
        dispatch_resume(readiness);
        CFRunLoopRun();
        dispatch_source_cancel(readiness);
        session = ready;
        printf("session_boundary_identity_wait_ms=%.3f ready=%d\n",
            (NSProcessInfo.processInfo.systemUptime - started) * 1000, session.phase != PLANKSessionUnavailable);
    }
    if (session.phase == PLANKSessionUnavailable) {
        fprintf(stderr, "session_boundary_initial_identity_unavailable\n");
        return 2;
    }
    unsigned int width = session.phase == PLANKSessionLoginWindow ? 1920 : 3840;
    printf("session_boundary_start phase=%s uid=%u security_session=%u requested_width=%u synthetic=%d\n",
        PLANKSessionName(session.phase), session.user, session.securitySession, width, injectBoundary);
    int result = runMediaGuarded(YES, NO, width, NO, session, injectBoundary, handoff);
    BOOL passed = (injectBoundary || handoff) ? result == 10 : result == 0;
    printf("session_boundary_gate=%d stream_result=%d synthetic=%d\n", passed, result, injectBoundary);
    return passed ? 0 : result;
}

int PLANKRunSessionTimingQualification(const char *mode) {
    if (strcmp(mode, "--retain-sample") == 0) timingRetainSample = YES;
    else if (strcmp(mode, "--synthetic-pts") == 0) timingSyntheticPTS = YES;
    else if (strcmp(mode, "--relative-pts") == 0) timingRelativePTS = YES;
    else if (strcmp(mode, "--low-latency") == 0) timingLowLatency = YES;
    else if (strcmp(mode, "--encoding-speed") == 0) timingEncodingSpeed = YES;
    else return 2;
    return PLANKRunSessionBoundaryQualification(NO, YES);
}

int PLANKRunCaptureEncodeProbe(BOOL hevc, BOOL pattern, BOOL owned4K) {
    return runMedia(hevc, pattern, owned4K ? 3840 : 0, NO);
}

int PLANKRunFullRangeQualification(BOOL capture444, BOOL pattern) {
    // Capability probe only: no chart or claim of color qualification. Reject
    // SCK substituting a different pixel format. Existing product stays intact.
    qualifyFullRange = YES;
    qualifyFullRange444 = capture444;
    return runMedia(YES, pattern, 0, NO);
}

int PLANKRunMain44410Qualification(unsigned int width) {
    PLANKGraphicalSession session = PLANKReadGraphicalSession();
    if (session.phase != PLANKSessionDesktop || (width != 3840 && width != 5120)) return 2;
    qualifyMain44410 = YES;
    qualifyFullRange = YES;
    qualifyFullRange444 = YES;
    timingEncodingSpeed = YES;
    printf("main44410_qualification=1 requested_width=%u full_range=1 native_cadence=1\n", width);
    return runMediaGuarded(YES, YES, width, NO, session, NO, NO);
}

int PLANKRunSpeedChartQualification(void) {
    PLANKGraphicalSession session = PLANKReadGraphicalSession();
    if (session.phase != PLANKSessionDesktop) return 2;
    timingEncodingSpeed = YES;
    printf("speed_chart_comparison=1 real_pts=1\n");
    return runMediaGuarded(YES, YES, 3840, NO, session, NO, NO);
}

int PLANKRunMixedChartQualification(BOOL speed) {
    PLANKGraphicalSession session = PLANKReadGraphicalSession();
    if (session.phase != PLANKSessionDesktop) return 2;
    chartMixedCadence = YES;
    timingEncodingSpeed = speed;
    printf("mixed_chart_comparison=1 speed_priority=%d real_pts=1 maximum_seconds=180\n", speed);
    // Reuse the bounded long-run owner lifetime and post-stop timing buckets.
    // Session revocation still stops capture; this runner never logs users in/out.
    return runMediaGuarded(YES, YES, 3840, NO, session, NO, YES);
}

int PLANKRunMediaOwnerQualification(BOOL crashOwner) {
    if (crashOwner) {
        int result = runMedia(YES, NO, 3840, YES);
        // A failed stream is expected; owner cleanup must still pass (not 7).
        BOOL passed = result == 8;
        printf("media_owner_crash_gate=%d stream_result=%d\n", passed, result);
        return passed ? 0 : 9;
    }
    // Same parent, two fresh owners: previous stream/encoder/display must have
    // passed teardown before starting the replacement. No credential/session change.
    int result = runMedia(NO, NO, 1920, NO);
    if (!result) result = runMedia(YES, NO, 3840, NO);
    printf("media_owner_replacement_gate=%d parent_survived=1\n", result == 0);
    return result;
}
