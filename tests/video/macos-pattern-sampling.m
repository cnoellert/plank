// SPDX-License-Identifier: GPL-3.0-or-later
// Synthetic sampling check only: no capture, display, consent or OS input.
#import "pattern-validation.h"

static unsigned value(unsigned x, unsigned y, unsigned component, BOOL tenBit) {
    return (x * 3 + y * 7 + component * 53) % (tenBit ? 1024 : 256);
}
static BOOL run(OSType format, BOOL tenBit, BOOL fullChroma) {
    CVPixelBufferRef pixel = NULL;
    if (CVPixelBufferCreate(NULL, 640, 400, format, NULL, &pixel)) return NO;
    if (CVPixelBufferLockBaseAddress(pixel, 0)) { CFRelease(pixel); return NO; }
    for (size_t plane = 0; plane < 2; ++plane) {
        size_t width = CVPixelBufferGetWidthOfPlane(pixel, plane);
        size_t height = CVPixelBufferGetHeightOfPlane(pixel, plane);
        size_t stride = CVPixelBufferGetBytesPerRowOfPlane(pixel, plane);
        uint8_t *base = CVPixelBufferGetBaseAddressOfPlane(pixel, plane);
        for (size_t y = 0; y < height; ++y) {
            memset(base + y * stride, 0, stride);
            for (size_t x = 0; x < width; ++x) {
                for (unsigned c = 0; c < (plane ? 2U : 1U); ++c) {
                    size_t offset = plane ? x * 2 + c : x;
                    unsigned sample = value((unsigned)x, (unsigned)y, plane ? c + 1 : 0, tenBit);
                    if (tenBit) ((uint16_t *)(base + y * stride))[offset] = sample << 6;
                    else base[y * stride + offset] = (uint8_t)sample;
                }
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(pixel, 0);
    NSArray<NSNumber *> *samples = PLANKReadPatternSamples(pixel);
    BOOL valid = samples.count == 120;
    for (unsigned i = 0; valid && i < 40; ++i) {
        unsigned x = (unsigned)((i < 8 ? (i + 0.5) / 8 : (i - 8 + 0.5) / 32) * 640);
        unsigned y = (unsigned)((i < 8 ? 0.25 : 0.8125) * 400);
        for (unsigned c = 0; c < 3; ++c) {
            unsigned sx = c && !fullChroma ? x / 2 : x;
            unsigned sy = c && !fullChroma ? y / 2 : y;
            valid &= samples[i * 3 + c].unsignedIntValue == value(sx, sy, c, tenBit);
        }
    }
    CFRelease(pixel);
    printf("pattern_sampling format=%08x full_chroma=%d passed=%d\n", (unsigned)format, fullChroma, valid);
    return valid;
}
int main(void) {
    @autoreleasepool {
        BOOL passed = run(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, NO, NO);
        passed &= run(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, YES, NO);
        passed &= run(kCVPixelFormatType_420YpCbCr10BiPlanarFullRange, YES, NO);
        passed &= run(kCVPixelFormatType_444YpCbCr10BiPlanarFullRange, YES, YES);
        return passed ? 0 : 1;
    }
}
