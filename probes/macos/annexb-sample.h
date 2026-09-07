// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

/** Write Annex B generated synthetic data for independent bitstream inspection. */
static BOOL PLANKWriteAnnexBSample(FILE *output, CMSampleBufferRef sample, BOOL hevc, BOOL first) {
    CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sample);
    int headerLength = 0;
    size_t count = 0, size = 0;
    const uint8_t *bytes = NULL;
    OSStatus status = hevc ? CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
        format, 0, &bytes, &size, &count, &headerLength) :
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
        format, 0, &bytes, &size, &count, &headerLength);
    if (status || headerLength != 4 || count > 8) return NO;
    const uint8_t start[] = {0, 0, 0, 1};
    if (first) {
        for (size_t i = 0; i < count; i++) {
            status = hevc ? CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                format, i, &bytes, &size, NULL, NULL) :
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                format, i, &bytes, &size, NULL, NULL);
            if (status || fwrite(start, 1, 4, output) != 4 ||
                fwrite(bytes, 1, size, output) != size) return NO;
        }
    }
    CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
    if (!block) return NO;
    size_t length = CMBlockBufferGetDataLength(block);
    if (length == 0 || length > 64 * 1024 * 1024) return NO;
    NSMutableData *data = [NSMutableData dataWithLength:length];
    if (CMBlockBufferCopyDataBytes(block, 0, length, data.mutableBytes)) return NO;
    const uint8_t *p = data.bytes;
    for (size_t offset = 0; offset < length;) {
        if (length - offset < 4) return NO;
        uint32_t nalLength = ((uint32_t)p[offset] << 24) | ((uint32_t)p[offset+1] << 16) |
            ((uint32_t)p[offset+2] << 8) | p[offset+3];
        offset += 4;
        if (!nalLength || nalLength > length - offset ||
            fwrite(start, 1, 4, output) != 4 ||
            fwrite(p + offset, 1, nalLength, output) != nalLength) return NO;
        offset += nalLength;
    }
    return YES;
}
