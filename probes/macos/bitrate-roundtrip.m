// SPDX-License-Identifier: GPL-3.0-or-later
// Dedicated Mac diagnostic: generated pixels only, no capture, input or network.
// Match the installed Main10 encoder properties and measure encoded bytes before
// transport. The identical moving texture repeats at each target rate.
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#include <unistd.h>

#define REQUIRE(x) do { if (!(x)) { fprintf(stderr, "failure line=%d\n", __LINE__); exit(1); } } while (0)

static void report(VTCompressionSessionRef encoder, CFStringRef key) {
    CFTypeRef value = NULL;
    OSStatus status = VTSessionCopyProperty(encoder, key, NULL, &value);
    printf("property=%s status=%d value=%s\n", [(__bridge NSString *)key UTF8String],
        (int)status, value ? [[(__bridge id)value description] UTF8String] : "unavailable");
    if (value) CFRelease(value);
}

int main(int argc, const char **argv) {
    if (argc > 2) return 2;
    BOOL ordered = argc == 2 && !strcmp(argv[1], "--ordered");
    BOOL averageOnly = argc == 2 && !strcmp(argv[1], "--average-only");
    BOOL clearLimit = argc == 2 && !strcmp(argv[1], "--clear-limit");
    BOOL forceKey = argc == 2 && !strcmp(argv[1], "--keyframe");
    BOOL recreate = argc == 2 && !strcmp(argv[1], "--recreate");
    BOOL longer = argc == 2 && !strcmp(argv[1], "--long");
    if (argc == 2 && !ordered && !averageOnly && !clearLimit && !forceKey && !recreate && !longer) return 2;
    alarm(120);
    setbuf(stdout, NULL);
    @autoreleasepool {
        const int width = 1920, height = 1080, framesPerPhase = longer ? 600 : 180;
        OSType format = kCVPixelFormatType_420YpCbCr10BiPlanarFullRange;
        NSDictionary *surface = @{
            (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(format),
            (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
        };
        CVPixelBufferRef pixel = NULL;
        REQUIRE(!CVPixelBufferCreate(NULL, width, height, format, (__bridge CFDictionaryRef)surface, &pixel));
        VTCompressionSessionRef encoder = NULL;
        NSDictionary *spec = @{(__bridge NSString *)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: @YES};
        REQUIRE(!VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_HEVC,
            (__bridge CFDictionaryRef)spec, (__bridge CFDictionaryRef)surface, NULL, NULL, NULL, &encoder));
        NSDictionary *properties = @{
            (__bridge NSString *)kVTCompressionPropertyKey_RealTime: @YES,
            (__bridge NSString *)kVTCompressionPropertyKey_AllowFrameReordering: @NO,
            (__bridge NSString *)kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality: @YES,
            (__bridge NSString *)kVTCompressionPropertyKey_ExpectedFrameRate: @60,
            (__bridge NSString *)kVTCompressionPropertyKey_MaxKeyFrameInterval: @120,
            (__bridge NSString *)kVTCompressionPropertyKey_ProfileLevel: (__bridge NSString *)kVTProfileLevel_HEVC_Main10_AutoLevel,
            (__bridge NSString *)kVTCompressionPropertyKey_ColorPrimaries: (__bridge NSString *)kCVImageBufferColorPrimaries_ITU_R_709_2,
            (__bridge NSString *)kVTCompressionPropertyKey_TransferFunction: (__bridge NSString *)kCVImageBufferTransferFunction_sRGB,
            (__bridge NSString *)kVTCompressionPropertyKey_YCbCrMatrix: (__bridge NSString *)kCVImageBufferYCbCrMatrix_ITU_R_709_2
        };
        REQUIRE(!VTSessionSetProperties(encoder, (__bridge CFDictionaryRef)properties));
        CVBufferSetAttachment(pixel, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
        CVBufferSetAttachment(pixel, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, kCVAttachmentMode_ShouldPropagate);
        CVBufferSetAttachment(pixel, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_601_4, kCVAttachmentMode_ShouldPropagate);
        const unsigned rates[] = {150000, 10000, 150000};
        for (unsigned phase = 0; phase < 3; ++phase) {
            if (recreate && phase) {
                VTCompressionSessionInvalidate(encoder); CFRelease(encoder); encoder = NULL;
                REQUIRE(!VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_HEVC,
                    (__bridge CFDictionaryRef)spec, (__bridge CFDictionaryRef)surface, NULL, NULL, NULL, &encoder));
                REQUIRE(!VTSessionSetProperties(encoder, (__bridge CFDictionaryRef)properties));
            }
            NSNumber *average = @((uint64_t)rates[phase] * 1000);
            NSArray *limits = @[@((uint64_t)rates[phase] * 250), @1];
            if (averageOnly) {
                REQUIRE(!VTSessionSetProperty(encoder, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFNumberRef)average));
            } else if (ordered || clearLimit) {
                if (clearLimit && phase) REQUIRE(!VTSessionSetProperty(encoder,
                    kVTCompressionPropertyKey_DataRateLimits, (__bridge CFArrayRef)@[]));
                REQUIRE(!VTSessionSetProperty(encoder, kVTCompressionPropertyKey_DataRateLimits, (__bridge CFArrayRef)limits));
                REQUIRE(!VTSessionSetProperty(encoder, kVTCompressionPropertyKey_AverageBitRate, (__bridge CFNumberRef)average));
            } else {
                NSDictionary *values = @{
                    (__bridge NSString *)kVTCompressionPropertyKey_AverageBitRate: average,
                    (__bridge NSString *)kVTCompressionPropertyKey_DataRateLimits: limits
                };
                REQUIRE(!VTSessionSetProperties(encoder, (__bridge CFDictionaryRef)values));
            }
            if (!phase || recreate) REQUIRE(!VTCompressionSessionPrepareToEncodeFrames(encoder));
            printf("phase=%u requested_kbps=%u mode=%s\n", phase, rates[phase], argc == 2 ? argv[1] : "baseline");
            report(encoder, kVTCompressionPropertyKey_AverageBitRate);
            report(encoder, kVTCompressionPropertyKey_DataRateLimits);
            report(encoder, kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder);
            uint64_t total = 0, steady = 0;
            unsigned dropped = 0;
            for (int frame = 0; frame < framesPerPhase; ++frame) {
                REQUIRE(!CVPixelBufferLockBaseAddress(pixel, 0));
                for (size_t plane = 0; plane < 2; ++plane) {
                    size_t rows = CVPixelBufferGetHeightOfPlane(pixel, plane);
                    size_t stride = CVPixelBufferGetBytesPerRowOfPlane(pixel, plane);
                    uint8_t *base = CVPixelBufferGetBaseAddressOfPlane(pixel, plane);
                    for (size_t y = 0; y < rows; ++y) {
                        uint16_t *row = (uint16_t *)(base + y * stride);
                        for (int x = 0; x < width; ++x) {
                            uint32_t value = (uint32_t)((x / 4) + (y / 4) * 480 + frame * 1299827);
                            value ^= value >> 16; value *= 0x7feb352d; value ^= value >> 15;
                            row[x] = (plane ? 512 : (value & 1023)) << 6;
                        }
                    }
                }
                REQUIRE(!CVPixelBufferUnlockBaseAddress(pixel, 0));
                dispatch_semaphore_t finished = dispatch_semaphore_create(0);
                __block size_t bytes = 0;
                __block OSStatus callbackStatus = 0;
                __block BOOL wasDropped = NO;
                NSDictionary *options = forceKey && phase && !frame ?
                    @{(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES} : nil;
                REQUIRE(!VTCompressionSessionEncodeFrameWithOutputHandler(encoder, pixel,
                    CMTimeMake(phase * framesPerPhase + frame, 60), kCMTimeInvalid,
                    (__bridge CFDictionaryRef)options, NULL,
                    ^(OSStatus status, VTEncodeInfoFlags flags, CMSampleBufferRef sample) {
                        callbackStatus = status;
                        wasDropped = (flags & kVTEncodeInfo_FrameDropped) != 0;
                        if (!status && sample && !(flags & kVTEncodeInfo_FrameDropped)) bytes = CMSampleBufferGetTotalSampleSize(sample);
                        dispatch_semaphore_signal(finished);
                    }));
                REQUIRE(!dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC)));
                REQUIRE(!callbackStatus && (bytes || wasDropped));
                if (wasDropped) ++dropped;
                total += bytes;
                if (frame >= 60) steady += bytes;
            }
            printf("phase=%u encoded_mbps=%.3f steady_mbps=%.3f frames=%d dropped=%u\n", phase,
                total * 8.0 * 60 / framesPerPhase / 1e6,
                steady * 8.0 * 60 / (framesPerPhase - 60) / 1e6, framesPerPhase, dropped);
        }
        VTCompressionSessionInvalidate(encoder); CFRelease(encoder); CVPixelBufferRelease(pixel);
    }
    return 0;
}
