// Owned synthetic 5K fixture; no capture, permissions, display or input changes.
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import "annexb-sample.h"

typedef struct { CMSampleBufferRef sample; OSStatus status; } Result;
static void encoded(void *opaque, void *source, OSStatus status,
                    VTEncodeInfoFlags flags, CMSampleBufferRef sample) {
    (void)source;
    Result *result = opaque;
    result->status = status;
    if (flags & kVTEncodeInfo_FrameDropped) result->status = -1;
    if (sample) result->sample = (CMSampleBufferRef)CFRetain(sample);
}
int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        FILE *file = fopen(argv[1], "wx");
        if (!file) return 3;
        const int width = 5120, height = 2160;
        CVPixelBufferRef pixel = NULL;
        NSDictionary *attributes = @{(__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}};
        if (CVPixelBufferCreate(NULL, width, height, kCVPixelFormatType_444YpCbCr10BiPlanarFullRange,
                                (__bridge CFDictionaryRef)attributes, &pixel)) return 4;
        if (CVPixelBufferLockBaseAddress(pixel, 0)) return 5;
        for (int plane = 0; plane < 2; ++plane) {
            uint8_t *base = CVPixelBufferGetBaseAddressOfPlane(pixel, plane);
            const size_t stride = CVPixelBufferGetBytesPerRowOfPlane(pixel, plane);
            for (int y = 0; y < height; ++y) {
                uint16_t *row = (uint16_t *)(base + y * stride);
                for (int x = 0; x < width; ++x) {
                    if (!plane) row[x] = (uint16_t)((x * 1023 / (width - 1)) << 6);
                    else {
                        row[2*x] = (uint16_t)((384 + y * 256 / (height - 1)) << 6);
                        row[2*x+1] = (uint16_t)((640 - y * 256 / (height - 1)) << 6);
                    }
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixel, 0);
        Result result = {0};
        VTCompressionSessionRef session = NULL;
        NSDictionary *spec = @{(__bridge NSString *)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: @YES};
        if (VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_HEVC,
                (__bridge CFDictionaryRef)spec, NULL, NULL, encoded, &result, &session)) return 6;
        NSDictionary *properties = @{
            (__bridge NSString *)kVTCompressionPropertyKey_ProfileLevel: @"HEVC_Main44410_AutoLevel",
            (__bridge NSString *)kVTCompressionPropertyKey_RealTime: @YES,
            (__bridge NSString *)kVTCompressionPropertyKey_AllowFrameReordering: @NO,
            (__bridge NSString *)kVTCompressionPropertyKey_ColorPrimaries: (__bridge NSString *)kCVImageBufferColorPrimaries_ITU_R_709_2,
            (__bridge NSString *)kVTCompressionPropertyKey_TransferFunction: (__bridge NSString *)kCVImageBufferTransferFunction_sRGB,
            (__bridge NSString *)kVTCompressionPropertyKey_YCbCrMatrix: (__bridge NSString *)kCVImageBufferYCbCrMatrix_ITU_R_709_2,
            (__bridge NSString *)kVTCompressionPropertyKey_AverageBitRate: @80000000
        };
        if (VTSessionSetProperties(session, (__bridge CFDictionaryRef)properties)) return 7;
        if (VTCompressionSessionPrepareToEncodeFrames(session)) return 8;
        if (VTCompressionSessionEncodeFrame(session, pixel, kCMTimeZero, CMTimeMake(1,60), NULL, NULL, NULL)) return 9;
        if (VTCompressionSessionCompleteFrames(session, kCMTimeInvalid) || result.status || !result.sample) return 10;
        const BOOL success = PLANKWriteAnnexBSample(file, result.sample, YES, YES);
        CFRelease(result.sample); VTCompressionSessionInvalidate(session);
        CFRelease(session); CFRelease(pixel);
        return fclose(file) || !success ? 11 : 0;
    }
}
