// SPDX-License-Identifier: GPL-3.0-or-later
#import "screen-capture.h"
#import "opus-encoder.h"
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <VideoToolbox/VideoToolbox.h>
#include <time.h>
#include <math.h>

@interface PLANKMacScreenCapture () <SCStreamOutput, SCStreamDelegate>
@end

@implementation PLANKMacScreenCapture {
    dispatch_queue_t _queue;
    PLANKMacNativeVideo *_video;
    PLANKMacNativeAudio *_audio;
    PLANKMacOpusEncoder *_audioEncoder;
    SCStream *_stream;
    VTCompressionSessionRef _encoder;
    void (^_failed)(void);
    void (^_drained)(void);
    BOOL _stopping, _captureStopped, _starting;
    unsigned _inFlight;
    BOOL _changingEncoder, _buildingEncoder;
    uint32_t _replacementBitrate;
    void (^_replacementCompletion)(uint32_t);
    size_t _width, _height;
    CMTime _lastPTS;
    uint64_t _completeFrames, _preEncodeDrops, _encoderDrops, _sendDrops;
    uint64_t _maxEncodeNs, _maxCallbackQueueNs;
}

+ (VTCompressionSessionRef)createEncoder:(uint32_t)bitrate width:(size_t)width height:(size_t)height {
    VTCompressionSessionRef encoder = NULL;
    NSDictionary *spec = @{(__bridge NSString *)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: @YES};
    NSDictionary *surface = @{
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr10BiPlanarFullRange),
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    if (VTCompressionSessionCreate(NULL, (int32_t)width, (int32_t)height, kCMVideoCodecType_HEVC,
        (__bridge CFDictionaryRef)spec, (__bridge CFDictionaryRef)surface, NULL, NULL, NULL, &encoder)) return NULL;
    NSDictionary *properties = @{
        (__bridge NSString *)kVTCompressionPropertyKey_RealTime: @YES,
        (__bridge NSString *)kVTCompressionPropertyKey_AllowFrameReordering: @NO,
        // Qualified mixed idle/motion behavior: preserve actual SCK timestamps.
        (__bridge NSString *)kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality: @YES,
        (__bridge NSString *)kVTCompressionPropertyKey_ExpectedFrameRate: @60,
        (__bridge NSString *)kVTCompressionPropertyKey_MaxKeyFrameInterval: @120,
        (__bridge NSString *)kVTCompressionPropertyKey_AverageBitRate: @((uint64_t)bitrate * 1000),
        // Two times target over one second, in bytes; not an added frame queue.
        (__bridge NSString *)kVTCompressionPropertyKey_DataRateLimits: @[@((uint64_t)bitrate * 250), @1],
        (__bridge NSString *)kVTCompressionPropertyKey_ProfileLevel: (__bridge NSString *)kVTProfileLevel_HEVC_Main10_AutoLevel,
        (__bridge NSString *)kVTCompressionPropertyKey_ColorPrimaries: (__bridge NSString *)kCVImageBufferColorPrimaries_ITU_R_709_2,
        (__bridge NSString *)kVTCompressionPropertyKey_TransferFunction: (__bridge NSString *)kCVImageBufferTransferFunction_sRGB,
        (__bridge NSString *)kVTCompressionPropertyKey_YCbCrMatrix: (__bridge NSString *)kCVImageBufferYCbCrMatrix_ITU_R_709_2
    };
    BOOL valid = !VTSessionSetProperties(encoder, (__bridge CFDictionaryRef)properties) &&
        !VTCompressionSessionPrepareToEncodeFrames(encoder);
    CFTypeRef hardware = NULL;
    OSStatus result = VTSessionCopyProperty(encoder, kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder, NULL, &hardware);
    valid = valid && !result && hardware && CFEqual(hardware, kCFBooleanTrue);
    if (hardware) CFRelease(hardware);
    if (!valid) { VTCompressionSessionInvalidate(encoder); CFRelease(encoder); return NULL; }
    return encoder;
}
- (void)setBitrate:(uint32_t)bitrate completion:(void (^)(uint32_t))completion {
    if (!_encoder || !completion || _stopping || _changingEncoder || bitrate < 10000 || bitrate > 150000) {
        if (completion) completion(0); return;
    }
    _changingEncoder = YES; _replacementBitrate = bitrate;
    _replacementCompletion = [completion copy];
    [self replaceEncoderWhenDrained];
}
- (void)replaceEncoderWhenDrained {
    if (!_changingEncoder || _buildingEncoder || _inFlight || _stopping) return;
    _buildingEncoder = YES;
    size_t width = _width, height = _height;
    uint32_t bitrate = _replacementBitrate;
    // No old frame can cross the switch. Framework setup is off the session
    // queue so input, audio, network control and cancellation stay responsive.
    VTCompressionSessionInvalidate(_encoder); CFRelease(_encoder); _encoder = NULL;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        VTCompressionSessionRef replacement = [PLANKMacScreenCapture createEncoder:bitrate width:width height:height];
        dispatch_async(self->_queue, ^{
            self->_buildingEncoder = NO; self->_changingEncoder = NO;
            if (self->_stopping) {
                if (replacement) { VTCompressionSessionInvalidate(replacement); CFRelease(replacement); }
                [self finishStop]; return;
            }
            self->_encoder = replacement;
            [self->_video requestKeyFrame];
            void (^completion)(uint32_t) = self->_replacementCompletion;
            self->_replacementCompletion = nil;
            NSLog(@"PLANK encoder replacement: target=%u Kbps peak=%u Kbps ready=%d", bitrate, bitrate * 2, replacement != NULL);
            if (completion) completion(replacement ? bitrate * 2 : 0);
        });
    });
}
- (void)startWithTopology:(NSDictionary *)topology bitrate:(uint32_t)bitrate video:(PLANKMacNativeVideo *)video
                   audio:(PLANKMacNativeAudio *)audio
                   queue:(dispatch_queue_t)queue started:(void (^)(uint32_t))started failed:(void (^)(void))failed {
    if (_queue || !queue || !video || !audio || !started || !failed) { if (failed) failed(); return; }
    _queue = queue; _video = video; _audio = audio; _failed = [failed copy];
    __weak typeof(self) weakSelf = self;
    _audioEncoder = [[PLANKMacOpusEncoder alloc] initWithOutput:^BOOL(NSData *packet, CMTime pts) {
        typeof(self) capture = weakSelf;
        if (!capture || capture->_stopping) return NO;
        int32_t sent = [capture->_audio sendOpusPacket:packet presentationTime:pts];
        return sent == PLANK_TRANSPORT_OK || sent == PLANK_TRANSPORT_DROPPED;
    }];
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
            uint32_t peak = bitrate * 2;
            self->_encoder = [PLANKMacScreenCapture createEncoder:bitrate width:self->_width height:self->_height];
            if (!self->_encoder) { self->_failed(); return; }
            SCStreamConfiguration *config = [SCStreamConfiguration new];
            config.width = self->_width; config.height = self->_height;
            config.minimumFrameInterval = CMTimeMake(1, 60); config.queueDepth = 3;
            config.pixelFormat = kCVPixelFormatType_420YpCbCr10BiPlanarFullRange;
            config.captureDynamicRange = SCCaptureDynamicRangeSDR; config.colorSpaceName = kCGColorSpaceSRGB;
            // macOS uses ScreenCaptureKit's embedded system/application cursor.
            // This is the Mac contract, not a Linux separate-cursor fallback.
            config.showsCursor = YES; config.capturesAudio = YES;
            config.captureMicrophone = NO; config.sampleRate = 48000; config.channelCount = 2;
            config.excludesCurrentProcessAudio = YES;
            self->_stream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:self];
            if (![self->_stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:self->_queue error:NULL] ||
                ![self->_stream addStreamOutput:self type:SCStreamOutputTypeAudio sampleHandlerQueue:self->_queue error:NULL]) {
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
    if (_stopping) return;
    if (type == SCStreamOutputTypeAudio) {
        PLANKMacOpusEncoder *encoder = _audioEncoder;
        if (![encoder encodeSample:sample]) {
            fprintf(stderr, "macos_capture_failure stage=audio\n");
            _failed();
        }
        return;
    }
    if (type != SCStreamOutputTypeScreen || !CMSampleBufferIsValid(sample)) return;
    NSArray *attachments = (__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample, false);
    NSNumber *status = attachments.firstObject[SCStreamFrameInfoStatus];
    if (![status isKindOfClass:NSNumber.class] || status.integerValue != SCFrameStatusComplete) return;
    CVPixelBufferRef pixel = CMSampleBufferGetImageBuffer(sample);
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sample);
    if (!pixel || !CVPixelBufferGetIOSurface(pixel) || CVPixelBufferGetWidth(pixel) != _width ||
        CVPixelBufferGetHeight(pixel) != _height ||
        CVPixelBufferGetPixelFormatType(pixel) != kCVPixelFormatType_420YpCbCr10BiPlanarFullRange ||
        !CMTIME_IS_NUMERIC(pts) || pts.value < 0 ||
        (CMTIME_IS_VALID(_lastPTS) && CMTimeCompare(pts, _lastPTS) <= 0)) {
        fprintf(stderr, "macos_capture_failure stage=video-sample\n"); _failed(); return;
    }
    _lastPTS = pts;
    ++_completeFrames;
    if (_changingEncoder || _inFlight >= 3) {
        ++_preEncodeDrops; return; // no encoded reference-frame dependency
    }
    // Explicit qualified SDK-27 xf20 full-range interpretation, distinct from the
    // BT.709 encoded output. Revalidate on final OS; no CPU color conversion.
    CVBufferSetAttachment(pixel, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixel, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixel, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_601_4, kCVAttachmentMode_ShouldPropagate);
    NSDictionary *options = _video.needsKeyFrame ? @{(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES} : nil;
    uint64_t submitted = clock_gettime_nsec_np(CLOCK_MONOTONIC);
    ++_inFlight;
    OSStatus result = VTCompressionSessionEncodeFrameWithOutputHandler(_encoder, pixel, pts, kCMTimeInvalid,
        (__bridge CFDictionaryRef)options, NULL, ^(OSStatus status, VTEncodeInfoFlags flags, CMSampleBufferRef output) {
        uint64_t completed = clock_gettime_nsec_np(CLOCK_MONOTONIC);
        if (output) CFRetain(output);
        dispatch_async(self->_queue, ^{
            --self->_inFlight;
            self->_maxEncodeNs = MAX(self->_maxEncodeNs, completed - submitted);
            self->_maxCallbackQueueNs = MAX(self->_maxCallbackQueueNs,
                clock_gettime_nsec_np(CLOCK_MONOTONIC) - completed);
            if (!self->_stopping) {
                if (status || !output || (flags & kVTEncodeInfo_FrameDropped)) {
                    ++self->_encoderDrops; [self->_video requestKeyFrame];
                }
                else {
                    uint64_t latency = (clock_gettime_nsec_np(CLOCK_MONOTONIC) - submitted) / 100000;
                    int32_t sent = [self->_video sendSample:output processingLatency:(uint16_t)MIN(latency, UINT16_MAX)];
                    if (sent == PLANK_TRANSPORT_DROPPED) ++self->_sendDrops;
                    if (sent != PLANK_TRANSPORT_OK && sent != PLANK_TRANSPORT_DROPPED) self->_failed();
                }
            }
            if (output) CFRelease(output);
            [self replaceEncoderWhenDrained];
            [self finishStop];
        });
    });
    if (result) { --_inFlight; _failed(); }
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
    (void)stream;
    fprintf(stderr, "macos_capture_failure stage=stream code=%ld\n", (long)error.code);
    dispatch_async(_queue, ^{ if (!self->_stopping) self->_failed(); });
}
- (void)stopWithCompletion:(void (^)(void))completion {
    if (_stopping) return; // owner calls once and fans out its own completions
    _stopping = YES; _failed = nil; _drained = [completion copy];
    _replacementCompletion = nil;
    [_audioEncoder stop]; _audioEncoder = nil;
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
    if (!_stopping || !_captureStopped || _inFlight || _buildingEncoder) return;
    if (_drained) NSLog(@"PLANK capture summary: complete=%llu pre-encode-drops=%llu encoder-drops=%llu recovery-or-send-drops=%llu encode-max-ms=%.3f callback-queue-max-ms=%.3f",
        (unsigned long long)_completeFrames, (unsigned long long)_preEncodeDrops,
        (unsigned long long)_encoderDrops, (unsigned long long)_sendDrops,
        _maxEncodeNs / 1e6, _maxCallbackQueueNs / 1e6);
    if (_encoder) { VTCompressionSessionInvalidate(_encoder); CFRelease(_encoder); _encoder = NULL; }
    _stream = nil; _video = nil; _audio = nil;
    void (^completion)(void) = _drained; _drained = nil;
    if (completion) completion();
}
@end
