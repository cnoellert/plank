// SPDX-License-Identifier: GPL-3.0-or-later
#import "preview-session.h"
#import "fixed-capture.h"
#import "native-input.h"
#include "plank_transport_control.h"
#include "plank_transport_input.h"
#include <math.h>
#include <time.h>

static BOOL integerInRange(id value, uint32_t minimum, uint32_t maximum) {
    if (![value isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
    double number = [value doubleValue];
    return isfinite(number) && number >= minimum && number <= maximum && number == floor(number);
}

BOOL PLANKMacPreviewRequestMatchesTopology(NSDictionary *request, NSDictionary *topology) {
    if (![request isKindOfClass:NSDictionary.class] || request.count != 9 ||
        ![topology isKindOfClass:NSDictionary.class] ||
        !integerInRange(request[@"schema_version"], 1, 1) ||
        ![request[@"encoding_mode"] isEqual:@"hevc-10-420-videotoolbox"] ||
        !integerInRange(request[@"frame_rate"], 60, 60) ||
        !integerInRange(request[@"bitrate_kbps"], 10000, 150000) ||
        !integerInRange(request[@"max_udp_payload_size"], 1200, 65527) ||
        !integerInRange(request[@"width"], 2, 8192) ||
        !integerInRange(request[@"height"], 2, 8192)) return NO;
    NSDictionary *capture = topology[@"capture"];
    if (![capture isKindOfClass:NSDictionary.class] ||
        ![request[@"capture_generation"] isKindOfClass:NSString.class] ||
        ![request[@"capture_id"] isKindOfClass:NSString.class] ||
        ![request[@"capture_generation"] isEqual:topology[@"generation"]] ||
        ![request[@"capture_id"] isEqual:capture[@"id"]] ||
        ![request[@"width"] isEqual:capture[@"width"]] ||
        ![request[@"height"] isEqual:capture[@"height"]]) return NO;
    // Compare the whole trusted contract; never negotiate away precision or
    // accept a provider advertising capabilities this preview cannot implement.
    NSDictionary *bounds = capture[@"logical_bounds"];
    if (![bounds isKindOfClass:NSDictionary.class]) return NO;
    for (NSString *key in @[@"x", @"y", @"width", @"height"])
        if (![bounds[key] isKindOfClass:NSNumber.class]) return NO;
    NSDictionary *expected = PLANKMacFixedCaptureDescription(topology[@"generation"], capture[@"id"],
        [request[@"width"] unsignedIntegerValue], [request[@"height"] unsignedIntegerValue],
        CGRectMake([bounds[@"x"] doubleValue], [bounds[@"y"] doubleValue],
                   [bounds[@"width"] doubleValue], [bounds[@"height"] doubleValue]));
    return expected && [expected isEqual:topology];
}

@interface PLANKMacPreviewSession ()
@property(atomic, readwrite) PLANKMacPreviewState state;
@end

@implementation PLANKMacPreviewSession {
    PLANKMacAuthenticationSession *_sessions;
    PLANKMacStreamLease *_lease;
    NSDictionary *(^_topology)(void);
    NSDictionary *_selected;
    id<PLANKMacPreviewCapture> _capture;
    PLANKMacNativeVideo *_video;
    PLANKMacNativeAudio *_audio;
    id<PLANKMacInputDevice> _inputDevice;
    PLANKMacNativeInput *_input;
    dispatch_group_t _inputGroup;
    BOOL _captureDrained;
    PlankTransportNativeEndpoint *_endpoint;
    dispatch_queue_t _queue;
    dispatch_source_t _watch;
    uint32_t _bitrate;
    BOOL _captureStarted;
    uint64_t _captureDeadline;
    NSMutableArray *_stopCallbacks;
}
- (instancetype)init { return nil; }
- (instancetype)initWithSessions:(PLANKMacAuthenticationSession *)sessions
                           token:(NSString *)token peer:(NSData *)peer
                         request:(NSDictionary *)request topology:(NSDictionary *(^)(void))topology
                          config:(const PlankTransportConfig *)config
                         capture:(id<PLANKMacPreviewCapture>)capture
                           input:(id<PLANKMacInputDevice>)input {
    if (!sessions || !topology || !capture || !input || !config ||
        config->struct_size != sizeof(*config) || config->abi_version != PLANK_TRANSPORT_ABI_VERSION ||
        config->mode != PLANK_TRANSPORT_MODE_SERVER || config->session_mode != PLANK_TRANSPORT_SESSION_ACTIVE)
        return nil;
    PLANKMacAccountIdentity account = {0};
    if (![sessions authorizeToken:token peer:peer identity:&account]) return nil;
    NSDictionary *selected = topology();
    if (!PLANKMacPreviewRequestMatchesTopology(request, selected)) return nil;
    self = [super init];
    if (!self) return nil;
    _state = PLANKMacPreviewPrepared;
    _sessions = sessions;
    _selected = [selected copy]; _topology = [topology copy]; _capture = capture;
    _bitrate = [request[@"bitrate_kbps"] unsignedIntValue];
    _queue = dispatch_queue_create("la.instinctual.PLANK.Host.preview", DISPATCH_QUEUE_SERIAL);
    _stopCallbacks = [NSMutableArray array];
    _inputDevice = input; _inputGroup = dispatch_group_create();
    _lease = [sessions claimToken:token peer:peer];
    if (!_lease) return nil;
    PlankTransportConfig configuration = *config;
    configuration.session_token = _lease.transportToken.UTF8String;
    configuration.max_udp_payload_size = [request[@"max_udp_payload_size"] unsignedIntValue];
    configuration.initial_video_bitrate_kbps = _bitrate;
    // Bound incomplete connection setup; no user-controlled timeout override.
    configuration.handshake_timeout_ms = 10000;
    if (plank_transport_native_endpoint_create(&configuration, &_endpoint) != PLANK_TRANSPORT_OK ||
        ![_selected isEqual:_topology()]) return nil;
    return self;
}
- (NSString *)transportToken { return _lease.transportToken; }

- (void)start {
    dispatch_async(_queue, ^{
        if (self.state != PLANKMacPreviewPrepared) return;
        self.state = PLANKMacPreviewConnecting;
        if (plank_transport_native_endpoint_start(self->_endpoint) != PLANK_TRANSPORT_OK) {
            [self stopOnQueue]; return;
        }
        __weak typeof(self) weakSelf = self;
        self->_watch = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self->_queue);
        // One bounded lifecycle/control source, no blocking receive worker or
        // per-frame timer. The encoder itself remains capture-driven.
        dispatch_source_set_timer(self->_watch, DISPATCH_TIME_NOW, 20 * NSEC_PER_MSEC, 2 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(self->_watch, ^{ [weakSelf tick]; });
        dispatch_resume(self->_watch);
    });
}

- (void)tick {
    @autoreleasepool {
        if (self.state != PLANKMacPreviewConnecting && self.state != PLANKMacPreviewStreaming) return;
        PLANKMacAccountIdentity identity = {0};
        // Also prunes an expired pending lease before QUIC has authenticated.
        BOOL active = [_sessions authorizeStreamLease:_lease identity:&identity];
        if (!_lease.transportToken || ![_selected isEqual:_topology()]) { [self stopOnQueue]; return; }
        uint32_t state = plank_transport_native_endpoint_state(_endpoint);
        if (state == PLANK_TRANSPORT_STATE_FAILED || state == PLANK_TRANSPORT_STATE_STOPPING ||
            state == PLANK_TRANSPORT_STATE_STOPPED || state == PLANK_TRANSPORT_STATE_INVALID) {
            [self stopOnQueue]; return;
        }
        if (self.state == PLANKMacPreviewConnecting && !_captureStarted && state == PLANK_TRANSPORT_STATE_READY) {
            if (![_sessions activateStreamLease:_lease]) { [self stopOnQueue]; return; }
            __weak typeof(self) weakSelf = self;
            _video = [[PLANKMacNativeVideo alloc] initWithEndpoint:_endpoint sessions:_sessions lease:_lease
                width:[_selected[@"capture"][@"width"] intValue] height:[_selected[@"capture"][@"height"] intValue]
                validity:^BOOL {
                    typeof(self) owner = weakSelf;
                    return owner && [owner->_selected isEqual:owner->_topology()];
                }];
            _audio = [[PLANKMacNativeAudio alloc] initWithEndpoint:_endpoint sessions:_sessions lease:_lease
                validity:^BOOL {
                    typeof(self) owner = weakSelf;
                    return owner && [owner->_selected isEqual:owner->_topology()];
                }];
            PLANKMacInputEvents *events = [_inputDevice eventsForTopology:_selected];
            id<PLANKMacInputDevice> device = _inputDevice;
            _input = [[PLANKMacNativeInput alloc] initWithEndpoint:_endpoint sessions:_sessions lease:_lease
                events:events validity:^BOOL {
                    typeof(self) owner = weakSelf;
                    return owner && [owner->_selected isEqual:owner->_topology()] && [device available];
                } deliver:^(CGEventRef event) { [device postEvent:event]; }];
            if (!_video || !_audio || !_input) { [self stopOnQueue]; return; }
            _captureStarted = YES;
            _captureDeadline = clock_gettime_nsec_np(CLOCK_MONOTONIC) + 5 * NSEC_PER_SEC;
            [_capture startWithTopology:_selected bitrate:_bitrate video:_video audio:_audio queue:_queue
                started:^(uint32_t peak) {
                    typeof(self) owner = weakSelf;
                    if (!owner || owner.state != PLANKMacPreviewConnecting) return;
                    if (peak < owner->_bitrate ||
                        plank_transport_native_set_video_bitrate(owner->_endpoint, owner->_bitrate, peak) != PLANK_TRANSPORT_OK) {
                        [owner stopOnQueue]; return;
                    }
                    owner.state = PLANKMacPreviewStreaming;
                    [owner startInputReceiver];
                }
                failed:^{ [weakSelf stopOnQueue]; }];
        } else if (_captureStarted && !active) {
            [self stopOnQueue]; return;
        }
        if (_captureStarted && ![_inputDevice available]) { [self stopOnQueue]; return; }
        if (_captureStarted && self.state == PLANKMacPreviewConnecting &&
            clock_gettime_nsec_np(CLOCK_MONOTONIC) >= _captureDeadline) { [self stopOnQueue]; return; }
        if (self.state == PLANKMacPreviewStreaming) [self receiveControls];
    }
}

- (void)startInputReceiver {
    // Native receive sleeps on the transport's condition variable, not on a
    // polling timer. At most one received packet awaits the serial owner queue;
    // no extra input backlog and no input latency from the 20-ms watchdog.
    __weak typeof(self) weakSelf = self;
    PlankTransportNativeEndpoint *endpoint = _endpoint;
    dispatch_queue_t ownerQueue = _queue;
    dispatch_group_async(_inputGroup, dispatch_queue_create("la.instinctual.PLANK.Host.input", DISPATCH_QUEUE_SERIAL), ^{
        BOOL running = YES;
        while (running) @autoreleasepool {
            uint8_t bytes[PLANK_TRANSPORT_INPUT_MAX_PAYLOAD_SIZE], type = 0; size_t size = 0;
            int32_t result = plank_transport_native_input_receive(endpoint, &type, bytes, sizeof(bytes), &size, 1000);
            const uint8_t *payload = bytes;
            // The synchronous handoff bounds outstanding work to one packet.
            // It also prevents input from racing capture/control teardown.
            __block BOOL keepGoing = NO;
            dispatch_sync(ownerQueue, ^{
                typeof(self) owner = weakSelf;
                if (!owner || owner.state != PLANKMacPreviewStreaming) return;
                if (result == PLANK_TRANSPORT_TIMEOUT) { keepGoing = YES; return; }
                if (result != PLANK_TRANSPORT_OK) { [owner stopOnQueue]; return; }
                PLANKMacInputResult delivered = [owner->_input consumeType:type
                    payload:[NSData dataWithBytes:payload length:size] time:clock_gettime_nsec_np(CLOCK_UPTIME_RAW)];
                if (delivered == PLANKMacInputMalformed || delivered == PLANKMacInputDenied || delivered == PLANKMacInputStopped) {
                    [owner stopOnQueue]; return;
                }
                keepGoing = YES; // Unsupported platform-specific keys do not become unrelated keys.
            });
            running = keepGoing;
        }
    });
    dispatch_group_notify(_inputGroup, _queue, ^{ [weakSelf finishStop]; });
}

- (void)receiveControls {
    // Bound each iteration so a client cannot starve teardown/encoder callbacks.
    for (unsigned index = 0; index < 8; ++index) {
        uint8_t bytes[PLANK_TRANSPORT_CONTROL_MAX_PACKET_SIZE]; size_t size = 0;
        int32_t result = plank_transport_native_data_receive(_endpoint, bytes, sizeof(bytes), &size, 0);
        if (result == PLANK_TRANSPORT_TIMEOUT) return;
        PlankTransportControlPacket packet;
        if (result != PLANK_TRANSPORT_OK || plank_transport_control_decode(bytes, size, &packet)) {
            [self stopOnQueue]; return;
        }
        if (packet.type == PLANK_TRANSPORT_CONTROL_CLIENT_DISCONNECT && !packet.payload_size) {
            [self stopOnQueue]; return;
        } else if (packet.type == PLANK_TRANSPORT_CONTROL_REQUEST_IDR && !packet.payload_size) {
            [_video requestKeyFrame];
        } else if (packet.type == PLANK_TRANSPORT_CONTROL_INVALIDATE_REFERENCE_FRAMES && packet.payload_size == 8 &&
                   plank_transport_control_read_u32(packet.payload) <= plank_transport_control_read_u32(packet.payload + 4)) {
            // VideoToolbox recovery is a fresh keyframe, not selective invalidation.
            [_video requestKeyFrame];
        } else if (packet.type == PLANK_TRANSPORT_CONTROL_SET_VIDEO_BITRATE && packet.payload_size == 4) {
            uint32_t bitrate = plank_transport_control_read_u32(packet.payload);
            uint32_t peak = 0;
            if (bitrate < 10000 || bitrate > 150000 || ![_capture setBitrate:bitrate peak:&peak] || peak < bitrate ||
                plank_transport_native_set_video_bitrate(_endpoint, bitrate, peak) != PLANK_TRANSPORT_OK) {
                [self stopOnQueue]; return;
            }
            _bitrate = bitrate;
            uint32_t values[] = {bitrate, bitrate, peak}; // requested/applied/peak: existing PLD1 contract
            uint8_t reply[20]; size_t replySize = 0;
            if (plank_transport_control_encode(PLANK_TRANSPORT_CONTROL_VIDEO_BITRATE_APPLIED, values, 3,
                reply, sizeof(reply), &replySize) ||
                plank_transport_native_data_send(_endpoint, reply, replySize) != PLANK_TRANSPORT_OK) {
                [self stopOnQueue]; return;
            }
        } else { [self stopOnQueue]; return; }
    }
}

- (void)stopWithCompletion:(void (^)(void))completion {
    dispatch_async(_queue, ^{
        if (self.state == PLANKMacPreviewStopped) { if (completion) completion(); return; }
        if (completion) [self->_stopCallbacks addObject:[completion copy]];
        [self stopOnQueue];
    });
}
- (void)stopOnQueue {
    if (self.state == PLANKMacPreviewStopping || self.state == PLANKMacPreviewStopped) return;
    self.state = PLANKMacPreviewStopping;
    [_input stop]; // authorized releases first; never release into a replacement desktop
    [_sessions endStreamLease:_lease]; // revoke before any asynchronous drain
    if (_watch) { dispatch_source_cancel(_watch); _watch = nil; }
    // Close the network even if a framework stop callback stalls. Keep the
    // allocated endpoint until drain so no borrowed callback sees freed memory.
    if (_endpoint) plank_transport_native_endpoint_stop(_endpoint);
    if (_captureStarted) [_capture stopWithCompletion:^{ self->_captureDrained = YES; [self finishStop]; }];
    else { _captureDrained = YES; [self finishStop]; }
}
- (void)finishStop {
    if (self.state != PLANKMacPreviewStopping || !_captureDrained ||
        dispatch_group_wait(_inputGroup, DISPATCH_TIME_NOW) != 0) return;
    _video = nil;
    _audio = nil;
    _input = nil; _inputDevice = nil;
    if (_endpoint) { plank_transport_native_endpoint_destroy(_endpoint); _endpoint = NULL; }
    _capture = nil;
    self.state = PLANKMacPreviewStopped;
    NSArray *callbacks = [_stopCallbacks copy]; [_stopCallbacks removeAllObjects];
    for (void (^callback)(void) in callbacks) callback();
}
- (void)dealloc {
    [_sessions endStreamLease:_lease];
    if (_watch) dispatch_source_cancel(_watch);
    // Fail closed even if a caller abandons the owner: retain the borrowed
    // endpoint/video until asynchronous capture drain, without capturing self.
    PlankTransportNativeEndpoint *endpoint = _endpoint;
    // Wake the condition-variable receiver before waiting for its bounded
    // handoff. Never block the serial owner queue waiting for that handoff.
    if (endpoint) plank_transport_native_endpoint_stop(endpoint);
    if (_captureStarted && _capture && _queue) {
        id<PLANKMacPreviewCapture> capture = _capture;
        PLANKMacNativeVideo *video = _video;
        PLANKMacNativeAudio *audio = _audio;
        PLANKMacNativeInput *input = _input;
        dispatch_group_notify(_inputGroup, _queue, ^{
            [capture stopWithCompletion:^{
                (void)video;
                (void)audio;
                (void)input;
                if (endpoint) plank_transport_native_endpoint_destroy(endpoint);
            }];
        });
    } else if (endpoint) plank_transport_native_endpoint_destroy(endpoint);
}
@end
