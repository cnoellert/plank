// SPDX-License-Identifier: GPL-3.0-or-later
#import "native-video.h"

static const size_t maximumFrameBytes = 64 * 1024 * 1024; // native transport ceiling

NSData *PLANKMacHEVCAnnexB(CMSampleBufferRef sample, int width, int height,
                         BOOL *keyFrame, uint64_t *ptsMicroseconds) {
    if (keyFrame) *keyFrame = NO;
    if (ptsMicroseconds) *ptsMicroseconds = 0;
    if (!sample || !keyFrame || !ptsMicroseconds || width <= 0 || height <= 0 ||
            width > 8192 || height > 8192 || (width & 1) || (height & 1) ||
            !CMSampleBufferIsValid(sample) || !CMSampleBufferDataIsReady(sample) ||
            CMSampleBufferGetNumSamples(sample) != 1) return nil;
    CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sample);
    if (!format || CMFormatDescriptionGetMediaType(format) != kCMMediaType_Video ||
            CMFormatDescriptionGetMediaSubType(format) != kCMVideoCodecType_HEVC) return nil;
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format);
    if (dimensions.width != width || dimensions.height != height) return nil;
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sample);
    if (!CMTIME_IS_NUMERIC(pts) || pts.epoch != 0 || pts.value < 0) return nil;
    pts = CMTimeConvertScale(pts, 1000000, kCMTimeRoundingMethod_RoundTowardZero);
    if (!CMTIME_IS_NUMERIC(pts) || pts.value < 0) return nil;

    NSArray *attachments = (__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample, false);
    if (attachments && attachments.count != 1) return nil;
    id notSync = attachments.firstObject[(__bridge NSString *)kCMSampleAttachmentKey_NotSync];
    if (notSync && CFGetTypeID((__bridge CFTypeRef)notSync) != CFBooleanGetTypeID()) return nil;
    BOOL key = ![notSync boolValue];
    int headerLength = 0;
    size_t count = 0, size = 0;
    const uint8_t *bytes = NULL;
    if (CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, 0, &bytes, &size,
            &count, &headerLength) || headerLength != 4 || count < 3 || count > 8) return nil;
    NSMutableData *output = [NSMutableData data];
    static const uint8_t start[] = {0, 0, 0, 1};
    if (key) {
        unsigned parameterTypes = 0;
        for (size_t i = 0; i < count; ++i) {
            if (CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, i, &bytes, &size,
                    NULL, NULL) || !bytes || size < 2 || size > maximumFrameBytes - 4 ||
                    output.length > maximumFrameBytes - 4 - size) return nil;
            unsigned type = (bytes[0] >> 1) & 63;
            if ((bytes[0] & 0x80) || !(bytes[1] & 7) || type < 32 || type > 34) return nil;
            parameterTypes |= 1U << (type - 32);
            [output appendBytes:start length:4];
            [output appendBytes:bytes length:size];
        }
        if (parameterTypes != 7) return nil; // VPS, SPS and PPS are all required
    }
    CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
    size_t length = block ? CMBlockBufferGetDataLength(block) : 0;
    if (!length || length > maximumFrameBytes - output.length) return nil;
    size_t prefix = output.length;
    [output increaseLengthBy:length];
    uint8_t *data = (uint8_t *)output.mutableBytes + prefix;
    if (CMBlockBufferCopyDataBytes(block, 0, length, data)) return nil;
    BOOL hasPicture = NO, hasRandomAccessPicture = NO;
    for (size_t offset = 0; offset < length;) {
        if (length - offset < 4) return nil;
        uint32_t nal = ((uint32_t)data[offset] << 24) | ((uint32_t)data[offset + 1] << 16) |
            ((uint32_t)data[offset + 2] << 8) | data[offset + 3];
        if (nal < 2 || nal > length - offset - 4) return nil;
        uint8_t *header = data + offset + 4;
        if ((header[0] & 0x80) || !(header[1] & 7)) return nil;
        unsigned type = (header[0] >> 1) & 63;
        if (type < 32) hasPicture = YES;
        if (type >= 16 && type <= 21) hasRandomAccessPicture = YES;
        memcpy(data + offset, start, 4); // replace lengths in the one compressed copy
        offset += 4 + nal;
    }
    if (!hasPicture || key != hasRandomAccessPicture) return nil;
    *keyFrame = key;
    *ptsMicroseconds = (uint64_t)pts.value;
    return output;
}

@implementation PLANKMacNativeVideo {
    PlankTransportNativeEndpoint *_endpoint;
    PLANKMacAuthenticationSession *_sessions;
    PLANKMacStreamLease *_lease;
    int _width, _height;
    BOOL _needsKeyFrame, _hasTimestamp;
    uint64_t _lastPTS, _frameNumber;
    BOOL (^_validity)(void);
}
- (instancetype)init { return nil; }
- (instancetype)initWithEndpoint:(PlankTransportNativeEndpoint *)endpoint
                        sessions:(PLANKMacAuthenticationSession *)sessions
                           lease:(PLANKMacStreamLease *)lease width:(int)width height:(int)height
                        validity:(BOOL (^)(void))validity {
    if (!endpoint || !sessions || !lease || !validity || width <= 0 || height <= 0 ||
            width > 8192 || height > 8192 || (width & 1) || (height & 1)) return nil;
    self = [super init];
    if (self) {
        _endpoint = endpoint; _sessions = sessions; _lease = lease;
        _width = width; _height = height; _needsKeyFrame = YES;
        _validity = [validity copy];
    }
    return self;
}
- (BOOL)needsKeyFrame { return _needsKeyFrame; }
- (void)requestKeyFrame { _needsKeyFrame = YES; }
- (int32_t)sendSample:(CMSampleBufferRef)sample processingLatency:(uint16_t)latency {
    PLANKMacAccountIdentity identity = {0};
    if (![_sessions authorizeStreamLease:_lease identity:&identity] ||
            !_validity() ||
            plank_transport_native_endpoint_state(_endpoint) != PLANK_TRANSPORT_STATE_READY)
        return PLANK_TRANSPORT_ERROR_INVALID_STATE;
    BOOL key = NO;
    uint64_t pts = 0;
    NSData *payload = PLANKMacHEVCAnnexB(sample, _width, _height, &key, &pts);
    if (!payload || (_hasTimestamp && pts <= _lastPTS) || _frameNumber == UINT64_MAX)
        return PLANK_TRANSPORT_ERROR_INVALID_ARGUMENT;
    // Count deliberately skipped encoded frames too: the receiver must see the
    // discontinuity instead of interpreting the next frame as contiguous.
    if (_needsKeyFrame && !key) {
        _lastPTS = pts; _hasTimestamp = YES; ++_frameNumber;
        return PLANK_TRANSPORT_DROPPED;
    }
    PlankTransportNativeVideoFrameInfo info = {0};
    info.struct_size = sizeof(info);
    info.codec = PLANK_TRANSPORT_NATIVE_VIDEO_CODEC_HEVC;
    info.flags = key ? PLANK_TRANSPORT_NATIVE_VIDEO_FLAG_KEY : 0;
    info.frame_number = _frameNumber + 1;
    info.pts = pts;
    info.host_processing_latency = latency;
    __block int32_t result = PLANK_TRANSPORT_ERROR_INVALID_STATE;
    // Enqueue and revocation have one ordering boundary. Conversion is outside
    // that lock; no frame can be enqueued after a completed lease revocation.
    if (![_sessions performWithStreamLease:_lease action:^{
        if (self->_validity())
            result = plank_transport_native_video_send(self->_endpoint, &info, payload.bytes, payload.length);
    }]) return PLANK_TRANSPORT_ERROR_INVALID_STATE;
    _lastPTS = pts; _hasTimestamp = YES; ++_frameNumber;
    _needsKeyFrame = result != PLANK_TRANSPORT_OK;
    return result;
}
@end
