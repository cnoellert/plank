// SPDX-License-Identifier: GPL-3.0-or-later
// Synthetic pixels/account only. Real hardware VideoToolbox and native QUIC.
#import "native-video.h"
#import <VideoToolbox/VideoToolbox.h>
#include <unistd.h>
#include <sys/resource.h>

static unsigned checks;
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "check failed line %d: %s\n", __LINE__, #x); exit(1); } ++checks; } while (0)

PLANKMacAuthenticationResult PLANKMacVerifyAccountIsolated(
        NSString *name, NSMutableData *password, PLANKMacAccountIdentity *identity) {
    BOOL valid = [name isEqual:@"synthetic"] && password.length == 4 && !memcmp(password.bytes, "test", 4);
    [password resetBytesInRange:NSMakeRange(0, password.length)];
    *identity = (PLANKMacAccountIdentity){123, {1}};
    return valid ? PLANKMacAuthenticationVerified : PLANKMacAuthenticationDenied;
}

static PlankTransportConfig config(uint32_t mode, NSString *token) {
    PlankTransportConfig value = {0};
    value.struct_size = sizeof(value); value.abi_version = PLANK_TRANSPORT_ABI_VERSION;
    value.mode = mode; value.session_token = token.UTF8String;
    value.handshake_timeout_ms = 5000; value.idle_timeout_ms = 10000;
    value.keep_alive_interval_ms = 1000; value.max_udp_payload_size = 1200;
    value.initial_video_bitrate_kbps = 50000;
    return value;
}

int main(int argc, const char **argv) {
    // certificate, private-key path, fingerprint, synthetic output path, optional --4k
    if (argc != 5 && !(argc == 6 && !strcmp(argv[5], "--4k"))) return 2;
    const int width = argc == 6 ? 3840 : 1920, height = argc == 6 ? 2160 : 1080;
    alarm(30);
    struct rlimit noCore = {0, 0};
    CHECK(!setrlimit(RLIMIT_CORE, &noCore));
    @autoreleasepool {
        __block PLANKMacDesktopIdentity desktop = {true, 1, {123, {1}}};
        PLANKMacAuthenticationSession *sessions = [[PLANKMacAuthenticationSession alloc]
            initWithDesktopSnapshot:^{ return desktop; }];
        NSData *peer = [NSData dataWithBytes:"test" length:4];
        NSDictionary *challenge = [sessions startForPeer:peer username:@"synthetic"];
        NSString *token = [sessions respondForPeer:peer conversation:challenge[@"conversation_id"]
            password:[NSMutableData dataWithBytes:"test" length:4]][@"session_token"];
        PLANKMacStreamLease *lease = [sessions claimToken:token peer:peer];
        CHECK(lease != nil);
        PlankTransportConfig serverConfig = config(PLANK_TRANSPORT_MODE_SERVER, lease.transportToken);
        serverConfig.bind_address = "127.0.0.1:47491";
        serverConfig.certificate_path = argv[1]; serverConfig.private_key_path = argv[2];
        PlankTransportConfig clientConfig = config(PLANK_TRANSPORT_MODE_CLIENT, lease.transportToken);
        clientConfig.remote_address = "127.0.0.1:47491"; clientConfig.server_name = "localhost";
        clientConfig.certificate_sha256 = argv[3];
        PlankTransportNativeEndpoint *server = NULL, *client = NULL;
        CHECK(plank_transport_native_endpoint_create(&serverConfig, &server) == PLANK_TRANSPORT_OK);
        CHECK(plank_transport_native_endpoint_create(&clientConfig, &client) == PLANK_TRANSPORT_OK);
        CHECK(plank_transport_native_endpoint_start(server) == PLANK_TRANSPORT_OK);
        CHECK(plank_transport_native_endpoint_start(client) == PLANK_TRANSPORT_OK);
        CHECK(plank_transport_native_endpoint_wait_ready(client, 5000) == PLANK_TRANSPORT_OK);
        CHECK(plank_transport_native_endpoint_wait_ready(server, 5000) == PLANK_TRANSPORT_OK);
        PLANKMacNativeVideo *video = [[PLANKMacNativeVideo alloc] initWithEndpoint:server
            sessions:sessions lease:lease width:width height:height validity:^BOOL { return YES; }];
        CHECK(video != nil && video.needsKeyFrame);
        CHECK([video sendSample:NULL processingLatency:0] == PLANK_TRANSPORT_ERROR_INVALID_STATE);
        CHECK([sessions activateStreamLease:lease]);
        CHECK([video sendSample:NULL processingLatency:0] == PLANK_TRANSPORT_ERROR_INVALID_ARGUMENT);

        CVPixelBufferRef pixel = NULL;
        NSDictionary *attributes = @{(__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}};
        CHECK(CVPixelBufferCreate(NULL, width, height, kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            (__bridge CFDictionaryRef)attributes, &pixel) == 0);
        CHECK(CVPixelBufferLockBaseAddress(pixel, 0) == 0);
        for (size_t plane = 0; plane < 2; ++plane) {
            size_t stride = CVPixelBufferGetBytesPerRowOfPlane(pixel, plane);
            size_t rows = CVPixelBufferGetHeightOfPlane(pixel, plane);
            uint8_t *base = CVPixelBufferGetBaseAddressOfPlane(pixel, plane);
            for (size_t y = 0; y < rows; ++y) {
                memset(base + y * stride, 0, stride);
                for (size_t x = 0; x < (size_t)width; ++x)
                    ((uint16_t *)(base + y * stride))[x] = (plane ? 512 : 64 + 876 * x / (width - 1)) << 6;
            }
        }
        CHECK(CVPixelBufferUnlockBaseAddress(pixel, 0) == 0);
        CVBufferSetAttachment(pixel, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
        CVBufferSetAttachment(pixel, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_sRGB, kCVAttachmentMode_ShouldPropagate);
        CVBufferSetAttachment(pixel, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
        VTCompressionSessionRef encoder = NULL;
        NSDictionary *spec = @{(__bridge NSString *)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: @YES};
        CHECK(VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_HEVC,
            (__bridge CFDictionaryRef)spec, NULL, NULL, NULL, NULL, &encoder) == 0);
        NSDictionary *properties = @{
            (__bridge NSString *)kVTCompressionPropertyKey_RealTime: @YES,
            (__bridge NSString *)kVTCompressionPropertyKey_AllowFrameReordering: @NO,
            (__bridge NSString *)kVTCompressionPropertyKey_ProfileLevel: (__bridge NSString *)kVTProfileLevel_HEVC_Main10_AutoLevel,
            (__bridge NSString *)kVTCompressionPropertyKey_AverageBitRate: @20000000,
            (__bridge NSString *)kVTCompressionPropertyKey_ExpectedFrameRate: @60,
            (__bridge NSString *)kVTCompressionPropertyKey_ColorPrimaries: (__bridge NSString *)kCVImageBufferColorPrimaries_ITU_R_709_2,
            (__bridge NSString *)kVTCompressionPropertyKey_TransferFunction: (__bridge NSString *)kCVImageBufferTransferFunction_sRGB,
            (__bridge NSString *)kVTCompressionPropertyKey_YCbCrMatrix: (__bridge NSString *)kCVImageBufferYCbCrMatrix_ITU_R_709_2
        };
        CHECK(VTSessionSetProperties(encoder, (__bridge CFDictionaryRef)properties) == 0);
        CHECK(VTCompressionSessionPrepareToEncodeFrames(encoder) == 0);
        CFTypeRef hardware = NULL;
        CHECK(VTSessionCopyProperty(encoder, kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder, NULL, &hardware) == 0);
        CHECK(hardware && CFEqual(hardware, kCFBooleanTrue));
        CFRelease(hardware);
        for (int frame = 0; frame < 12; ++frame) {
            if (frame == 5) [video requestKeyFrame];
            // Skip one dependent frame, then ask VT for a genuine recovery key.
            NSDictionary *options = frame == 6 ?
                @{(__bridge NSString *)kVTEncodeFrameOptionKey_ForceKeyFrame: @YES} : nil;
            dispatch_semaphore_t finished = dispatch_semaphore_create(0);
            __block CMSampleBufferRef sample = NULL;
            __block BOOL valid = NO;
            CHECK(VTCompressionSessionEncodeFrameWithOutputHandler(encoder, pixel, CMTimeMake(frame, 60), CMTimeMake(1, 60), (__bridge CFDictionaryRef)options, NULL,
                ^(OSStatus status, VTEncodeInfoFlags flags, CMSampleBufferRef output) {
                    valid = !status && !(flags & kVTEncodeInfo_FrameDropped) && output != NULL;
                    if (valid) sample = (CMSampleBufferRef)CFRetain(output);
                    dispatch_semaphore_signal(finished);
                }) == 0);
            CHECK(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0);
            CHECK(valid && sample);
            BOOL key = NO;
            uint64_t pts = 0;
            CHECK(PLANKMacHEVCAnnexB(sample, 1280, 720, &key, &pts) == nil && !key && !pts);
            NSData *expected = PLANKMacHEVCAnnexB(sample, width, height, &key, &pts);
            CHECK(expected && (frame != 0 || key));
            if (frame == 5) {
                CHECK(!key);
                CHECK([video sendSample:sample processingLatency:123] == PLANK_TRANSPORT_DROPPED);
                CHECK(video.needsKeyFrame);
                uint8_t byte = 0; size_t count = 0;
                PlankTransportNativeVideoFrameInfo absent = {0}; absent.struct_size = sizeof(absent);
                CHECK(plank_transport_native_video_receive(client, &absent, &byte, 1, &count, 10)
                    == PLANK_TRANSPORT_TIMEOUT);
                CFRelease(sample);
                continue;
            }
            if (frame == 6) CHECK(key);
            if (frame == 0) {
                CHECK([expected writeToFile:[NSString stringWithUTF8String:argv[4]] atomically:NO]);
                size_t badSize = 4;
                uint32_t zero = 0;
                CMBlockBufferRef block = NULL;
                CHECK(CMBlockBufferCreateWithMemoryBlock(NULL, NULL, badSize, NULL, NULL, 0, badSize, 0, &block) == 0);
                CHECK(CMBlockBufferReplaceDataBytes(&zero, block, 0, badSize) == 0);
                CMSampleTimingInfo timing = {CMTimeMake(1, 60), CMTimeMake(0, 60), kCMTimeInvalid};
                CMSampleBufferRef bad = NULL;
                CHECK(CMSampleBufferCreateReady(NULL, block, CMSampleBufferGetFormatDescription(sample),
                    1, 1, &timing, 1, &badSize, &bad) == 0);
                CHECK(PLANKMacHEVCAnnexB(bad, width, height, &key, &pts) == nil && !key && !pts);
                CFRelease(bad); CFRelease(block);
            }
            CHECK([video sendSample:sample processingLatency:123] == PLANK_TRANSPORT_OK);
            CHECK(!video.needsKeyFrame);
            CHECK([video sendSample:sample processingLatency:123] == PLANK_TRANSPORT_ERROR_INVALID_ARGUMENT);
            NSMutableData *received = [NSMutableData dataWithLength:expected.length];
            PlankTransportNativeVideoFrameInfo info = {0}; info.struct_size = sizeof(info);
            size_t receivedSize = 0;
            CHECK(plank_transport_native_video_receive(client, &info, received.mutableBytes,
                received.length, &receivedSize, 5000) == PLANK_TRANSPORT_OK);
            CHECK(receivedSize == expected.length && [received isEqual:expected]);
            CHECK(info.codec == PLANK_TRANSPORT_NATIVE_VIDEO_CODEC_HEVC && info.frame_number == (uint64_t)frame + 1);
            CHECK(info.pts == (uint64_t)CMTimeConvertScale(CMTimeMake(frame, 60), 1000000, kCMTimeRoundingMethod_RoundTowardZero).value);
            CHECK(info.host_processing_latency == 123);
            CFRelease(sample);
        }
        desktop.active = false;
        CHECK([video sendSample:NULL processingLatency:0] == PLANK_TRANSPORT_ERROR_INVALID_STATE);
        CHECK(lease.transportToken == nil);
        [sessions revokeAll];
        VTCompressionSessionInvalidate(encoder); CFRelease(encoder); CFRelease(pixel);
        video = nil;
        plank_transport_native_endpoint_destroy(client);
        plank_transport_native_endpoint_destroy(server);
        printf("macos_native_video=pass checks=%u pixels=%dx%d encoded=12 received=11 hardware_vt=1 exact_quic_payload=1 recovery_key=1 synthetic_only=1\n", checks, width, height);
    }
    return 0;
}
