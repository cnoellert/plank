// SPDX-License-Identifier: GPL-3.0-or-later
#import "native-audio.h"

@implementation PLANKMacNativeAudio {
    PlankTransportNativeEndpoint *_endpoint;
    PLANKMacAuthenticationSession *_sessions;
    PLANKMacStreamLease *_lease;
    BOOL (^_validity)(void);
    BOOL _hasPTS;
    CMTime _nextPTS;
}
- (instancetype)init { return nil; }
- (instancetype)initWithEndpoint:(PlankTransportNativeEndpoint *)endpoint
                        sessions:(PLANKMacAuthenticationSession *)sessions
                           lease:(PLANKMacStreamLease *)lease
                        validity:(BOOL (^)(void))validity {
    if (!endpoint || !sessions || !lease || !validity) return nil;
    self = [super init];
    if (self) {
        _endpoint = endpoint; _sessions = sessions; _lease = lease;
        _validity = [validity copy];
    }
    return self;
}
- (int32_t)sendOpusPacket:(NSData *)packet presentationTime:(CMTime)pts {
    PLANKMacAccountIdentity identity = {0};
    if (![_sessions authorizeStreamLease:_lease identity:&identity] || !_validity() ||
        plank_transport_native_endpoint_state(_endpoint) != PLANK_TRANSPORT_STATE_READY)
        return PLANK_TRANSPORT_ERROR_INVALID_STATE;
    if (!packet.length || packet.length > 65536 || !CMTIME_IS_NUMERIC(pts) ||
        pts.epoch != 0 || pts.value < 0 || (_hasPTS && CMTimeCompare(pts, _nextPTS)))
        return PLANK_TRANSPORT_ERROR_INVALID_ARGUMENT;
    CMTime next = CMTimeAdd(pts, CMTimeMake(240, 48000));
    CMTime milliseconds = CMTimeConvertScale(pts, 1000, kCMTimeRoundingMethod_RoundTowardZero);
    if (!CMTIME_IS_NUMERIC(next) || CMTimeCompare(next, pts) <= 0 ||
        !CMTIME_IS_NUMERIC(milliseconds) || milliseconds.value < 0 ||
        (uint64_t)milliseconds.value >= (UINT64_C(1) << 61))
        return PLANK_TRANSPORT_ERROR_INVALID_ARGUMENT;
    PlankTransportNativeAudioPacketInfo info = {0};
    info.struct_size = sizeof(info); info.frame_samples = 240;
    info.pts = (uint64_t)milliseconds.value;
    __block int32_t result = PLANK_TRANSPORT_ERROR_INVALID_STATE;
    // Only the bounded enqueue runs under the existing revocation boundary.
    // Opus bytes are already complete; transport owns its own bounded copy.
    if (![_sessions performWithStreamLease:_lease action:^{
        if (self->_validity()) result = plank_transport_native_audio_send(
            self->_endpoint, &info, packet.bytes, packet.length);
    }]) return PLANK_TRANSPORT_ERROR_INVALID_STATE;
    if (result == PLANK_TRANSPORT_OK || result == PLANK_TRANSPORT_DROPPED) {
        // DROPPED evicts an older queued packet, but accepts the current one.
        _hasPTS = YES; _nextPTS = next;
    }
    return result;
}
@end
