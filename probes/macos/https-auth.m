// SPDX-License-Identifier: GPL-3.0-or-later
// Loopback-only, 60-second qualification executable; not an installed service.
#import "https-auth-server.h"
#import "graphical-authority.h"
#import "fixed-capture.h"
#include <sys/resource.h>
#include <unistd.h>
#ifdef PLANK_MAC_PREVIEW_TEST
#import "host-runtime.h"
#import "screen-capture.h"
#endif

#if defined(PLANK_MAC_PREVIEW_TEST) && defined(PLANK_SYNTHETIC_AUTH_TEST)
#import "macos-fake-input.h"
static BOOL testScreenAllowed = YES, testInputAllowed = YES;
@interface PLANKNoPixelCapture : NSObject <PLANKMacPreviewCapture>
@end
@implementation PLANKNoPixelCapture
- (BOOL)available { return testScreenAllowed; }
- (void)startWithTopology:(NSDictionary *)topology bitrate:(uint32_t)bitrate video:(PLANKMacNativeVideo *)video
                   audio:(PLANKMacNativeAudio *)audio
    queue:(dispatch_queue_t)queue started:(void (^)(uint32_t))started failed:(void (^)(void))failed {
    (void)topology; (void)video; (void)audio; (void)queue; (void)failed; started(bitrate * 2);
}
- (void)setBitrate:(uint32_t)bitrate completion:(void (^)(uint32_t))completion { completion(bitrate * 2); }
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
        PLANKMacGraphicalAuthority *authority = [[PLANKMacGraphicalAuthority alloc] initWithPhase:PLANKMacScopeDesktop];
        if (argc == 1) {
            PLANKMacGraphicalIdentity before = [authority snapshot];
            [authority revoke];
            PLANKMacGraphicalIdentity after = [authority snapshot];
            printf("macos_desktop_authority active=%d revocation_pass=%d\n", before.active, !after.active);
            return after.active ? 1 : 0;
        }
#if defined(PLANK_MAC_PREVIEW_TEST) && defined(PLANK_SYNTHETIC_AUTH_TEST)
        if (argc == 3) {
            testScreenAllowed = strcmp(argv[2], "screen-denied") != 0;
            testInputAllowed = strcmp(argv[2], "input-denied") != 0;
            if (testScreenAllowed && testInputAllowed) return 2;
        } else
#endif
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
#ifdef PLANK_SYNTHETIC_AUTH_TEST
        __block unsigned desktopWidth = 3840, desktopHeight = 2160;
        __block NSString *encodingMode = @"hevc-10-420-videotoolbox";
        NSDictionary *(^topology)(void) = ^{
            return PLANKMacFixedCaptureDescription(@"98454815-80ab-4a88-b187-92f59353afca", @"cgdisplay:42",
                desktopWidth, desktopHeight, CGRectMake(-1920, 0, 1920, 1080), encodingMode);
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
#ifdef PLANK_MAC_PREVIEW_TEST
        // Qualification uses the actual Host assembly, with an explicit
        // loopback address and synthetic devices only in the synthetic build.
        PLANKMacHostRuntime *runtime = [[PLANKMacHostRuntime alloc] initWithIdentity:identity
            information:information snapshot:snapshot topology:topology address:@"127.0.0.1"
            certificate:[directory stringByAppendingPathComponent:@"cert.pem"]
            privateKey:[directory stringByAppendingPathComponent:@"key.pem"]
            capture:^id<PLANKMacPreviewCapture> {
#ifdef PLANK_SYNTHETIC_AUTH_TEST
                return [PLANKNoPixelCapture new];
#else
                return [PLANKMacScreenCapture new];
#endif
            } input:^id<PLANKMacInputDevice> {
#ifdef PLANK_SYNTHETIC_AUTH_TEST
                PLANKFakeInput *input = [PLANKFakeInput new];
                input.availableFlag = testInputAllowed;
                return input;
#else
                return [PLANKMacQuartzInput new];
#endif
            }];
#ifdef PLANK_SYNTHETIC_AUTH_TEST
        runtime.prepareDisplay = ^BOOL(unsigned width, unsigned height, NSString *mode, BOOL (^valid)(void)) {
            if (!valid() || !((width == 1920 && height == 1080) || (width == 3840 && height == 2160))) return NO;
            desktopWidth = width; desktopHeight = height;
            encodingMode = mode;
            return valid();
        };
#endif
#else
        PLANKMacAuthenticationSession *sessions = [[PLANKMacAuthenticationSession alloc] initWithGraphicalSnapshot:snapshot];
        PLANKMacHTTPSAuthServer *server = [[PLANKMacHTTPSAuthServer alloc] initWithIdentity:identity
            sessions:sessions information:information topology:topology launch:nil];
#endif
        CFRelease(identity);
        void (^ready)(uint16_t) = ^(uint16_t port) {
            printf("macos_https_auth_ready port=%u desktop_active=%d\n", port, snapshot().active);
            fflush(stdout);
        };
#ifdef PLANK_MAC_PREVIEW_TEST
        if (![runtime startOnPort:0 ready:ready failed:^{ exit(2); }]) return 2;
#else
        if (![server startOnAddress:@"127.0.0.1" port:0 ready:ready]) return 2;
#endif
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
#ifdef PLANK_MAC_PREVIEW_TEST
            [runtime stopWithCompletion:^{ puts("macos_host_runtime_drained=1"); exit(0); }];
#else
            [server stopWithCompletion:^{ exit(0); }];
#endif
        });
        // Aqua notifications and the authority watcher require the main run loop.
        [[NSRunLoop mainRunLoop] run];
    }
}
