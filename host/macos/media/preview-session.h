// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import "native-video.h"
#import "native-audio.h"
#import "quartz-input.h"

BOOL PLANKMacPreviewRequestMatchesTopology(NSDictionary *request, NSDictionary *topology);

// All methods/callbacks run on the supplied serial session queue. stop must
// complete only after capture and encoder callbacks have drained. No UI waits.
@protocol PLANKMacPreviewCapture <NSObject>
- (void)startWithTopology:(NSDictionary *)topology bitrate:(uint32_t)bitrate
                   video:(PLANKMacNativeVideo *)video audio:(PLANKMacNativeAudio *)audio
                   queue:(dispatch_queue_t)queue
                 started:(void (^)(uint32_t peakBitrate))started
                  failed:(void (^)(void))failed;
// At most one replacement outstanding. Completion returns zero on failure;
// stop cancels delivery and must wait for any replacement work to drain.
- (void)setBitrate:(uint32_t)bitrate completion:(void (^)(uint32_t peakBitrate))completion;
- (void)stopWithCompletion:(void (^)(void))completion;
@end

typedef NS_ENUM(unsigned, PLANKMacPreviewState) {
    PLANKMacPreviewPrepared, PLANKMacPreviewConnecting, PLANKMacPreviewStreaming,
    PLANKMacPreviewStopping, PLANKMacPreviewStopped
};

// One-shot authenticated stream owner. Construct only from the bounded auth
// lane, after HTTPS authentication. The administrator, never request JSON,
// supplies bind/certificate configuration. All request-controlled fields are
// validated, and the token is consumed before any endpoint is opened.
// The caller must retain the owner and call stop; no implicit session takeover.
@interface PLANKMacPreviewSession : NSObject
- (instancetype)initWithSessions:(PLANKMacAuthenticationSession *)sessions
                           token:(NSString *)token peer:(NSData *)peer
                         request:(NSDictionary *)request
                        topology:(NSDictionary *(^)(void))topology
                          config:(const PlankTransportConfig *)config
                         capture:(id<PLANKMacPreviewCapture>)capture
                           input:(id<PLANKMacInputDevice>)input;
@property(atomic, readonly) PLANKMacPreviewState state;
// Secret for the authenticated HTTPS launch reply only; never log/persist.
@property(atomic, readonly, copy) NSString *transportToken;
- (void)start;
- (void)stopWithCompletion:(void (^)(void))completion;
@end
