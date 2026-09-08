// SPDX-License-Identifier: GPL-3.0-or-later
// Loopback-only, 60-second qualification executable; not an installed service.
#import "https-auth-server.h"
#import "desktop-authority.h"
#import "fixed-capture.h"
#include <sys/resource.h>
#include <unistd.h>
#ifdef PLANK_MAC_PREVIEW_TEST
#import "preview-session.h"
#import "screen-capture.h"
#endif

#if defined(PLANK_MAC_PREVIEW_TEST) && defined(PLANK_SYNTHETIC_AUTH_TEST)
#import "macos-fake-input.h"
@interface PLANKNoPixelCapture : NSObject <PLANKMacPreviewCapture>
@end
@implementation PLANKNoPixelCapture
- (void)startWithTopology:(NSDictionary *)topology bitrate:(uint32_t)bitrate video:(PLANKMacNativeVideo *)video
                   audio:(PLANKMacNativeAudio *)audio
    queue:(dispatch_queue_t)queue started:(void (^)(uint32_t))started failed:(void (^)(void))failed {
    (void)topology; (void)video; (void)audio; (void)queue; (void)failed; started(bitrate * 2);
}
- (BOOL)setBitrate:(uint32_t)bitrate peak:(uint32_t *)peak { *peak = bitrate * 2; return YES; }
- (void)stopWithCompletion:(void (^)(void))completion { completion(); }
@end
#endif

#ifdef PLANK_SYNTHETIC_AUTH_TEST
// Linked ONLY into the synthetic test executable, never the real verifier.
PLANKMacAuthenticationResult PLANKMacVerifyAccountIsolated(
        NSString *name, NSMutableData *password, PLANKMacAccountIdentity *identity) {
    memset(identity, 0, sizeof(*identity));
    BOOL accepted = [name isEqual:@"synthetic"] && password.length == 4 && !memcmp(password.bytes, "test", 4);
    [password resetBytesInRange:NSMakeRange(0, password.length)];
    if (!accepted) return PLANKMacAuthenticationDenied;
    *identity = (PLANKMacAccountIdentity){123, {1}};
    return PLANKMacAuthenticationVerified;
}
#endif

int main(int argc, const char *argv[]) {
#ifndef PLANK_SYNTHETIC_AUTH_TEST
    if (argc == 2 && !strcmp(argv[1], PLANK_MAC_ACCOUNT_WORKER_ARGUMENT)) return PLANKMacAccountWorkerMain();
#endif
    struct rlimit noCore = {0, 0};
    if (setrlimit(RLIMIT_CORE, &noCore)) return 2;
    alarm(65);
    @autoreleasepool {
        PLANKMacDesktopAuthority *authority = [PLANKMacDesktopAuthority new];
        if (argc == 1) {
            PLANKMacGraphicalIdentity before = [authority snapshot];
            [authority revoke];
            PLANKMacGraphicalIdentity after = [authority snapshot];
            printf("macos_desktop_authority active=%d revocation_pass=%d\n", before.active, !after.active);
            return after.active ? 1 : 0;
        }
        if (argc != 2) return 2;
        // Create an in-memory identity directly with Apple's supported API.
        // No PKCS#12 importer, keychain insertion or trust-store modification.
        NSString *directory = [NSString stringWithUTF8String:argv[1]];
        NSData *certificateBytes = [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"cert.der"]];
        NSMutableData *keyBytes = [[NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"key.der"]] mutableCopy];
        if (!certificateBytes || !keyBytes) return 2;
        SecCertificateRef certificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateBytes);
        NSDictionary *attributes = @{(__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
            (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate};
        SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)keyBytes, (__bridge CFDictionaryRef)attributes, NULL);
        [keyBytes resetBytesInRange:NSMakeRange(0, keyBytes.length)];
        SecIdentityRef identity = certificate && key ? SecIdentityCreate(NULL, certificate, key) : NULL;
        if (key) CFRelease(key);
        if (certificate) CFRelease(certificate);
        if (!identity) { puts("macos_https_identity_create=failed"); return 2; }
#ifdef PLANK_SYNTHETIC_AUTH_TEST
        PLANKMacGraphicalSnapshot snapshot = ^{ return (PLANKMacGraphicalIdentity){true, 1, {123, {1}}, PLANKMacScopeDesktop}; };
#else
        PLANKMacGraphicalSnapshot snapshot = ^{ return [authority snapshot]; };
#endif
        PLANKMacAuthenticationSession *sessions = [[PLANKMacAuthenticationSession alloc] initWithGraphicalSnapshot:snapshot];
#ifdef PLANK_SYNTHETIC_AUTH_TEST
        NSDictionary *(^topology)(void) = ^{
            return PLANKMacFixedCaptureDescription(@"98454815-80ab-4a88-b187-92f59353afca", @"cgdisplay:42",
                3840, 2160, CGRectMake(-1920, 0, 1920, 1080));
        };
#else
        PLANKMacFixedCapture *capture = [PLANKMacFixedCapture new];
        NSDictionary *(^topology)(void) = ^{ return [capture snapshot]; };
#endif
        // Explicit synthetic workstation metadata, even for the real-account
        // test. Never publish the developer's machine name or hardware UUID.
        PLANKMacServerInformation *information = [[PLANKMacServerInformation alloc]
            initWithName:@"PLANK Mac qualification" workstationUUID:
                [[NSUUID alloc] initWithUUIDString:@"f92140f5-8740-4b3b-82f7-74db5353de27"]
            version:@"macos-host-qualification"];
        PLANKMacLaunchHandler launch = nil;
#ifdef PLANK_MAC_PREVIEW_TEST
        // Qualification-only orchestration: no public capability advertisement,
        // no wildcard bind, no installable service and no unauthenticated capture.
        __block PLANKMacPreviewSession *active = nil;
        launch = ^NSDictionary *(NSDictionary *request, NSString *token, NSData *peer, uint16_t port, unsigned *status) {
            if (!PLANKMacPreviewRequestMatchesTopology(request, topology())) { *status = 400; return nil; }
            if (active && active.state != PLANKMacPreviewStopped) { *status = 409; return nil; }
            PlankTransportConfig config = {0};
            config.struct_size = sizeof(config); config.abi_version = PLANK_TRANSPORT_ABI_VERSION;
            config.mode = PLANK_TRANSPORT_MODE_SERVER;
            config.bind_address = [NSString stringWithFormat:@"127.0.0.1:%u", port].UTF8String;
            config.certificate_path = [directory stringByAppendingPathComponent:@"cert.pem"].UTF8String;
            config.private_key_path = [directory stringByAppendingPathComponent:@"key.pem"].UTF8String;
            config.idle_timeout_ms = 10000; config.keep_alive_interval_ms = 1000;
#ifdef PLANK_SYNTHETIC_AUTH_TEST
            id<PLANKMacPreviewCapture> source = [PLANKNoPixelCapture new];
            id<PLANKMacInputDevice> input = [PLANKFakeInput new];
#else
            id<PLANKMacPreviewCapture> source = [PLANKMacScreenCapture new];
            id<PLANKMacInputDevice> input = [PLANKMacQuartzInput new];
#endif
            active = [[PLANKMacPreviewSession alloc] initWithSessions:sessions token:token peer:peer request:request
                topology:topology config:&config capture:source input:input];
            if (!active) { *status = 503; return nil; }
            NSDictionary *reply = @{@"schema_version": @1, @"state": @"connecting", @"transport_token": active.transportToken,
                @"udp_port": @(port), @"max_udp_payload_size": request[@"max_udp_payload_size"],
                @"capture": topology()[@"capture"], @"services": @{@"audio": @YES, @"input": @YES, @"cursor": @"embedded"}};
            [active start];
            *status = 200;
            return reply;
        };
#endif
        PLANKMacHTTPSAuthServer *server = [[PLANKMacHTTPSAuthServer alloc] initWithIdentity:identity
            sessions:sessions information:information topology:topology launch:launch];
        CFRelease(identity);
        if (![server startOnAddress:@"127.0.0.1" port:0 ready:^(uint16_t port) {
            printf("macos_https_auth_ready port=%u desktop_active=%d\n", port, snapshot().active);
            fflush(stdout);
        }]) return 2;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [server stop];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ exit(0); });
        });
        // Aqua notifications and the authority watcher require the main run loop.
        [[NSRunLoop mainRunLoop] run];
    }
}
