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
    if (plank_transport_native_endpoint_state(_endpoint) != PLANK_TRANSPORT_STATE_READY)
        return PLANK_TRANSPORT_ERROR_INVALID_STATE;
    __block int32_t result = PLANK_TRANSPORT_ERROR_INVALID_STATE;
    // One fresh authorization/topology check at the actual send boundary.
    // Keep revocation serialized with validation and enqueue; do not perform
    // the same WindowServer/account RPCs twice for every 5 ms audio packet.
    [_sessions performWithStreamLease:_lease action:^{
        if (!self->_validity()) return;
        result = PLANK_TRANSPORT_ERROR_INVALID_ARGUMENT;
        if (!packet.length || packet.length > 65536 || !CMTIME_IS_NUMERIC(pts) ||
            pts.epoch != 0 || pts.value < 0 || (self->_hasPTS && CMTimeCompare(pts, self->_nextPTS)))
            return;
        CMTime next = CMTimeAdd(pts, CMTimeMake(240, 48000));
        CMTime milliseconds = CMTimeConvertScale(pts, 1000, kCMTimeRoundingMethod_RoundTowardZero);
        if (!CMTIME_IS_NUMERIC(next) || CMTimeCompare(next, pts) <= 0 ||
            !CMTIME_IS_NUMERIC(milliseconds) || milliseconds.value < 0 ||
            (uint64_t)milliseconds.value >= (UINT64_C(1) << 61))
            return;
        PlankTransportNativeAudioPacketInfo info = {0};
        info.struct_size = sizeof(info); info.frame_samples = 240;
        info.pts = (uint64_t)milliseconds.value;
        result = plank_transport_native_audio_send(self->_endpoint, &info, packet.bytes, packet.length);
        if (result == PLANK_TRANSPORT_OK || result == PLANK_TRANSPORT_DROPPED) {
            // DROPPED evicts an older queued packet, but accepts the current one.
            self->_hasPTS = YES; self->_nextPTS = next;
        }
    }];
    return result;
}
@end
