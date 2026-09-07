// SPDX-License-Identifier: GPL-3.0-or-later
#import "screen-capture.h"
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <VideoToolbox/VideoToolbox.h>
#include <time.h>
#include <math.h>

@interface PLANKMacScreenCapture () <SCStreamOutput, SCStreamDelegate>
@end

@implementation PLANKMacScreenCapture {
    dispatch_queue_t _queue;
    PLANKMacNativeVideo *_video;
    SCStream *_stream;
    VTCompressionSessionRef _encoder;
    void (^_failed)(void);
    void (^_drained)(void);
    BOOL _stopping, _captureStopped, _starting;
    unsigned _inFlight;
    size_t _width, _height;
    CMTime _lastPTS;
}

- (BOOL)setBitrate:(uint32_t)bitrate peak:(uint32_t *)peak {
    if (peak) *peak = 0;
    if (!_encoder || !peak || _stopping || bitrate < 10000 || bitrate > 150000) return NO;
    // A one-second hard rate limit of 2x target supplies the transport's peak
    // budget. It is not an extra buffering stage or a constant-bitrate promise.
    NSDictionary *values = @{
        (__bridge NSString *)kVTCompressionPropertyKey_AverageBitRate: @((uint64_t)bitrate * 1000),
        (__bridge NSString *)kVTCompressionPropertyKey_DataRateLimits: @[@((uint64_t)bitrate * 250), @1]
    };
    if (VTSessionSetProperties(_encoder, (__bridge CFDictionaryRef)values)) return NO;
    *peak = bitrate * 2;
    return YES;
}
- (BOOL)prepareEncoder:(uint32_t)bitrate peak:(uint32_t *)peak {
    NSDictionary *spec = @{(__bridge NSString *)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: @YES};
    NSDictionary *surface = @{
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange),
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    if (VTCompressionSessionCreate(NULL, (int32_t)_width, (int32_t)_height, kCMVideoCodecType_HEVC,
        (__bridge CFDictionaryRef)spec, (__bridge CFDictionaryRef)surface, NULL, NULL, NULL, &_encoder)) return NO;
    NSDictionary *properties = @{
        (__bridge NSString *)kVTCompressionPropertyKey_RealTime: @YES,
        (__bridge NSString *)kVTCompressionPropertyKey_AllowFrameReordering: @NO,
        // Qualified mixed idle/motion behavior: preserve actual SCK timestamps.
        (__bridge NSString *)kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality: @YES,
        (__bridge NSString *)kVTCompressionPropertyKey_ExpectedFrameRate: @60,
        (__bridge NSString *)kVTCompressionPropertyKey_MaxKeyFrameInterval: @120,
        (__bridge NSString *)kVTCompressionPropertyKey_ProfileLevel: (__bridge NSString *)kVTProfileLevel_HEVC_Main10_AutoLevel,
        (__bridge NSString *)kVTCompressionPropertyKey_ColorPrimaries: (__bridge NSString *)kCVImageBufferColorPrimaries_ITU_R_709_2,
        (__bridge NSString *)kVTCompressionPropertyKey_TransferFunction: (__bridge NSString *)kCVImageBufferTransferFunction_sRGB,
        (__bridge NSString *)kVTCompressionPropertyKey_YCbCrMatrix: (__bridge NSString *)kCVImageBufferYCbCrMatrix_ITU_R_709_2
    };
    if (VTSessionSetProperties(_encoder, (__bridge CFDictionaryRef)properties) ||
        ![self setBitrate:bitrate peak:peak] || VTCompressionSessionPrepareToEncodeFrames(_encoder)) return NO;
    CFTypeRef hardware = NULL;
    OSStatus result = VTSessionCopyProperty(_encoder, kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder, NULL, &hardware);
    BOOL valid = !result && hardware && CFEqual(hardware, kCFBooleanTrue);
    if (hardware) CFRelease(hardware);
    return valid;
}
- (void)startWithTopology:(NSDictionary *)topology bitrate:(uint32_t)bitrate video:(PLANKMacNativeVideo *)video
                   queue:(dispatch_queue_t)queue started:(void (^)(uint32_t))started failed:(void (^)(void))failed {
    if (_queue || !queue || !video || !started || !failed) { if (failed) failed(); return; }
    _queue = queue; _video = video; _failed = [failed copy];
    _lastPTS = kCMTimeInvalid;
    _width = [topology[@"capture"][@"width"] unsignedIntegerValue];
    _height = [topology[@"capture"][@"height"] unsignedIntegerValue];
    NSString *identifier = topology[@"capture"][@"id"];
    if (!CGPreflightScreenCaptureAccess() || !_width || !_height || _width > 8192 || _height > 8192 ||
        (_width & 1) || (_height & 1)) { failed(); return; }
    _starting = YES;
    [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:YES
        completionHandler:^(SCShareableContent *content, NSError *error) {
        dispatch_async(self->_queue, ^{
            self->_starting = NO;
            if (self->_stopping) { self->_captureStopped = YES; [self finishStop]; return; }
            SCDisplay *selected = nil;
            for (SCDisplay *display in content.displays)
                if ([[NSString stringWithFormat:@"cgdisplay:%u", display.displayID] isEqual:identifier]) selected = display;
            if (error || !selected) { self->_failed(); return; }
            SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:selected excludingWindows:@[]];
            double w = filter.contentRect.size.width * filter.pointPixelScale;
            double h = filter.contentRect.size.height * filter.pointPixelScale;
            if (!isfinite(w) || !isfinite(h) || w != self->_width || h != self->_height) { self->_failed(); return; }
            uint32_t peak = 0;
            if (![self prepareEncoder:bitrate peak:&peak]) { self->_failed(); return; }
            SCStreamConfiguration *config = [SCStreamConfiguration new];
            config.width = self->_width; config.height = self->_height;
            config.minimumFrameInterval = CMTimeMake(1, 60); config.queueDepth = 3;
            config.pixelFormat = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange;
            config.captureDynamicRange = SCCaptureDynamicRangeSDR; config.colorSpaceName = kCGColorSpaceSRGB;
            // Initial video-only preview carries the visible host cursor in
            // pixels. It must not claim the Linux separate-cursor capability.
            config.showsCursor = YES; config.capturesAudio = NO;
            self->_stream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:self];
            if (![self->_stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:self->_queue error:NULL]) {
                self->_failed(); return;
            }
            self->_starting = YES;
            [self->_stream startCaptureWithCompletionHandler:^(NSError *startError) {
                dispatch_async(self->_queue, ^{
                    self->_starting = NO;
                    if (self->_stopping) { [self stopCapture]; return; }
                    if (startError) self->_failed();
                    else started(peak);
                });
            }];
        });
    }];
}
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    (void)stream;
    if (_stopping || type != SCStreamOutputTypeScreen || !CMSampleBufferIsValid(sample)) return;
    NSArray *attachments = (__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample, false);
    NSNumber *status = attachments.firstObject[SCStreamFrameInfoStatus];
    if (![status isKindOfClass:NSNumber.class] || status.integerValue != SCFrameStatusComplete) return;
    CVPixelBufferRef pixel = CMSampleBufferGetImageBuffer(sample);
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sample);
    if (!pixel || !CVPixelBufferGetIOSurface(pixel) || CVPixelBufferGetWidth(pixel) != _width ||
        CVPixelBufferGetHeight(pixel) != _height ||
        CVPixelBufferGetPixelFormatType(pixel) != kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ||
        !CMTIME_IS_NUMERIC(pts) || pts.value < 0 ||
        (CMTIME_IS_VALID(_lastPTS) && CMTimeCompare(pts, _lastPTS) <= 0)) { _failed(); return; }
    _lastPTS = pts;
    if (_inFlight >= 3) return; // drop before encoding; no reference-frame dependency
    // Explicit qualified SDK-27 x420 input interpretation, distinct from the
    // BT.709 encoded output. Revalidate on final OS; no CPU color conversion.
    CVBufferSetAttachment(pixel, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixel, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixel, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_601_4, kCVAttachmentMode_ShouldPropagate);
    NSDictionary *options = _video.needsKeyFrame ? @{(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES} : nil;
    uint64_t submitted = clock_gettime_nsec_np(CLOCK_MONOTONIC);
    ++_inFlight;
    OSStatus result = VTCompressionSessionEncodeFrameWithOutputHandler(_encoder, pixel, pts, kCMTimeInvalid,
        (__bridge CFDictionaryRef)options, NULL, ^(OSStatus status, VTEncodeInfoFlags flags, CMSampleBufferRef output) {
        if (output) CFRetain(output);
        dispatch_async(self->_queue, ^{
            --self->_inFlight;
            if (!self->_stopping) {
                if (status || !output || (flags & kVTEncodeInfo_FrameDropped)) [self->_video requestKeyFrame];
                else {
                    uint64_t latency = (clock_gettime_nsec_np(CLOCK_MONOTONIC) - submitted) / 100000;
                    int32_t sent = [self->_video sendSample:output processingLatency:(uint16_t)MIN(latency, UINT16_MAX)];
                    if (sent != PLANK_TRANSPORT_OK && sent != PLANK_TRANSPORT_DROPPED) self->_failed();
                }
            }
            if (output) CFRelease(output);
            [self finishStop];
        });
    });
    if (result) { --_inFlight; _failed(); }
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    (void)stream; (void)error;
    dispatch_async(_queue, ^{ if (!self->_stopping) self->_failed(); });
}
- (void)stopWithCompletion:(void (^)(void))completion {
    if (_stopping) return; // owner calls once and fans out its own completions
    _stopping = YES; _failed = nil; _drained = [completion copy];
    if (!_starting) [self stopCapture];
}
- (void)stopCapture {
    if (!_stream) { _captureStopped = YES; [self finishStop]; return; }
    [_stream stopCaptureWithCompletionHandler:^(NSError *error) {
        (void)error;
        dispatch_async(self->_queue, ^{ self->_captureStopped = YES; [self finishStop]; });
    }];
}
- (void)finishStop {
    if (!_stopping || !_captureStopped || _inFlight) return;
    if (_encoder) { VTCompressionSessionInvalidate(_encoder); CFRelease(_encoder); _encoder = NULL; }
    _stream = nil; _video = nil;
    void (^completion)(void) = _drained; _drained = nil;
    if (completion) completion();
}
@end
