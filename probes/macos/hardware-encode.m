// SPDX-License-Identifier: GPL-3.0-or-later
// Synthetic serial encode probe: not capture, motion, or end-to-end latency.
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreVideo/CoreVideo.h>
#include <mach/mach_time.h>
#include <sys/stat.h>
#import "annexb-sample.h"

typedef struct {
    dispatch_semaphore_t completion;
    CMSampleBufferRef sample;
    OSStatus status;
} EncodeResult;

static void encoded(void *context, void *frame, OSStatus status,
                    VTEncodeInfoFlags flags, CMSampleBufferRef sample) {
    (void)frame;
    EncodeResult *result = context;
    result->status = status;
    if ((flags & kVTEncodeInfo_FrameDropped) || !sample) result->status = -1;
    if (sample) result->sample = (CMSampleBufferRef)CFRetain(sample);
    dispatch_semaphore_signal(result->completion);
}


/** Allocate an immutable, IOSurface-backed video-range grayscale test ramp. */
static CVPixelBufferRef createRamp(int width, int height, BOOL tenBit) {
    CVPixelBufferRef pixel = NULL;
    NSDictionary *attributes = @{(__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}};
    CVReturn status = CVPixelBufferCreate(NULL, width, height,
        tenBit ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange :
                 kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        (__bridge CFDictionaryRef)attributes, &pixel);
    if (status || !pixel) return NULL;
    if (CVPixelBufferLockBaseAddress(pixel, 0)) { CFRelease(pixel); return NULL; }
    for (int plane = 0; plane < 2; plane++) {
        size_t rows = CVPixelBufferGetHeightOfPlane(pixel, plane);
        size_t stride = CVPixelBufferGetBytesPerRowOfPlane(pixel, plane);
        uint8_t *base = CVPixelBufferGetBaseAddressOfPlane(pixel, plane);
        for (size_t y = 0; y < rows; y++) {
            memset(base + y * stride, 0, stride);
            for (int x = 0; x < width; x++) {
                if (tenBit) {
                    uint16_t value = plane ? 512 : 64 + 876 * x / (width - 1);
                    ((uint16_t *)(base + y * stride))[x] = value << 6;
                } else {
                    base[y * stride + x] = plane ? 128 : 16 + 219 * x / (width - 1);
                }
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(pixel, 0);
    CVBufferSetAttachment(pixel, kCVImageBufferColorPrimariesKey,
        kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixel, kCVImageBufferTransferFunctionKey,
        kCVImageBufferTransferFunction_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixel, kCVImageBufferYCbCrMatrixKey,
        kCVImageBufferYCbCrMatrix_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    return pixel;
}

/** Fail on rejected properties, software substitution, drops, or bad output. */
static BOOL runCase(NSString *directory, int width, int height, BOOL hevc, int colorCase, BOOL cadence) {
    NSString *name = colorCase < 0 ?
        [NSString stringWithFormat:@"%dx%d.%@", width, height, hevc ? @"hevc" : @"h264"] :
        [NSString stringWithFormat:@"%dx%d-color-%d.hevc", width, height, colorCase];
    FILE *output = fopen([[directory stringByAppendingPathComponent:name] fileSystemRepresentation], "wx");
    if (!output) { perror("create synthetic output (must not exist)"); return NO; }
    EncodeResult result = {.completion = dispatch_semaphore_create(0)};
    VTCompressionSessionRef session = NULL;
    CVPixelBufferRef pixel = createRamp(width, height, hevc);
    // Controlled synthetic comparison only: same ramp, bitrate and geometry.
    // Case 0: BT.709; 1: sRGB transfer; 2: sRGB plus 601->709 matrix conversion
    // matching the current SCK x420 path. Never change live capture metadata.
    if (pixel && colorCase > 0) {
        CVBufferSetAttachment(pixel, kCVImageBufferTransferFunctionKey,
            kCVImageBufferTransferFunction_sRGB, kCVAttachmentMode_ShouldPropagate);
        if (colorCase == 2)
            CVBufferSetAttachment(pixel, kCVImageBufferYCbCrMatrixKey,
                kCVImageBufferYCbCrMatrix_ITU_R_601_4, kCVAttachmentMode_ShouldPropagate);
    }
    NSDictionary *spec = @{(__bridge NSString *)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: @YES};
    OSStatus status = pixel ? VTCompressionSessionCreate(NULL, width, height,
        hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264,
        (__bridge CFDictionaryRef)spec, NULL, NULL, encoded, &result, &session) : -1;
    BOOL passed = NO;
    NSMutableArray<NSNumber *> *times = [NSMutableArray array];
    do {
        if (status) break;
        NSDictionary *properties = @{
            (__bridge NSString *)kVTCompressionPropertyKey_RealTime: @YES,
            (__bridge NSString *)kVTCompressionPropertyKey_AllowFrameReordering: @NO,
            (__bridge NSString *)kVTCompressionPropertyKey_ExpectedFrameRate: @60,
            (__bridge NSString *)kVTCompressionPropertyKey_MaxKeyFrameInterval: @120,
            (__bridge NSString *)kVTCompressionPropertyKey_AverageBitRate: @(colorCase >= 0 ? 20000000 : (width > 1920 ? 40000000 : 20000000)),
            (__bridge NSString *)kVTCompressionPropertyKey_ProfileLevel: (__bridge NSString *)(hevc ?
                kVTProfileLevel_HEVC_Main10_AutoLevel : kVTProfileLevel_H264_High_AutoLevel),
            (__bridge NSString *)kVTCompressionPropertyKey_ColorPrimaries: (__bridge NSString *)kCVImageBufferColorPrimaries_ITU_R_709_2,
            (__bridge NSString *)kVTCompressionPropertyKey_TransferFunction: (__bridge NSString *)(colorCase > 0 ?
                kCVImageBufferTransferFunction_sRGB : kCVImageBufferTransferFunction_ITU_R_709_2),
            (__bridge NSString *)kVTCompressionPropertyKey_YCbCrMatrix: (__bridge NSString *)kCVImageBufferYCbCrMatrix_ITU_R_709_2
        };
        status = VTSessionSetProperties(session, (__bridge CFDictionaryRef)properties);
        if (status) break;
        status = VTCompressionSessionPrepareToEncodeFrames(session);
        if (status) break;
        CFTypeRef hardware = NULL;
        status = VTSessionCopyProperty(session, kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder,
                                      NULL, &hardware);
        BOOL usesHardware = hardware && CFEqual(hardware, kCFBooleanTrue);
        if (hardware) CFRelease(hardware);
        if (status || !usesHardware) { status = -1; break; }
        mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);
        for (int i = 0; i < 40; i++) {
            // Deliberately serial: compare idle-wakeup latency with continuous
            // submissions, not sustained throughput or live frame-queue behavior.
            if (cadence) usleep(i >= 10 && i < 20 ? 1000000 : 16667);
            uint64_t start = mach_absolute_time();
            result.status = 0;
            status = VTCompressionSessionEncodeFrame(session, pixel,
                CMTimeMake(i, 60), CMTimeMake(1, 60), NULL, NULL, NULL);
            if (status) break;
            if (dispatch_semaphore_wait(result.completion,
                dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) != 0) { status = -1; break; }
            double milliseconds = (mach_absolute_time() - start) *
                (double)timebase.numer / timebase.denom / 1e6;
            if (cadence) printf("cadence_frame=%d spacing=%s callback_ms=%.3f\n", i,
                i >= 10 && i < 20 ? "idle" : "active", milliseconds);
            if (i >= 10) [times addObject:@(milliseconds)];
            BOOL valid = !result.status && result.sample &&
                CMSampleBufferDataIsReady(result.sample) && PLANKWriteAnnexBSample(output, result.sample, hevc, i == 0);
            if (result.sample) { CFRelease(result.sample); result.sample = NULL; }
            if (!valid) { status = -1; break; }
        }
        passed = status == 0 && times.count == 30;
    } while (0);
    if (session) { VTCompressionSessionInvalidate(session); CFRelease(session); }
    if (result.sample) CFRelease(result.sample);
    if (pixel) CFRelease(pixel);
    if (fclose(output)) passed = NO;
    [times sortUsingSelector:@selector(compare:)];
    double sum = 0;
    for (NSNumber *value in times) sum += value.doubleValue;
    printf("case=%s hardware_required=1 passed=%d status=%d measured_frames=%lu mean_ms=%.3f p95_ms=%.3f max_ms=%.3f\n",
        name.UTF8String, passed, status, (unsigned long)times.count,
        times.count ? sum / times.count : 0,
        times.count ? times[(times.count * 95 - 1) / 100].doubleValue : 0,
        times.lastObject.doubleValue);
    return passed;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        struct stat info;
        BOOL colorComparison = argc == 3 && strcmp(argv[2], "--color-timing") == 0;
        BOOL cadence = argc == 3 && strcmp(argv[2], "--cadence-timing") == 0;
        if ((argc != 2 && !colorComparison && !cadence) || stat(argv[1], &info) || !S_ISDIR(info.st_mode)) {
            fprintf(stderr, "Usage: hardware-encode existing-empty-output-directory [--color-timing|--cadence-timing]\n");
            return 2;
        }
        setbuf(stdout, NULL);
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        BOOL passed = YES;
        if (cadence) return runCase(directory, 3840, 2160, YES, 2, YES) ? 0 : 1;
        if (colorComparison) {
            for (int color = 0; color < 3; color++)
                passed &= runCase(directory, 3840, 2160, YES, color, NO);
            return passed ? 0 : 1;
        }
        for (int scale = 1; scale <= 2; scale++) {
            passed &= runCase(directory, 1920 * scale, 1080 * scale, NO, -1, NO);
            passed &= runCase(directory, 1920 * scale, 1080 * scale, YES, -1, NO);
        }
        return passed ? 0 : 1;
    }
}
