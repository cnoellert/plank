// SPDX-License-Identifier: GPL-3.0-or-later
// Loopback-only, 60-second qualification executable; not an installed service.
#import "https-auth-server.h"
#import "desktop-authority.h"
#include <sys/resource.h>
#include <unistd.h>

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
            PLANKMacDesktopIdentity before = [authority snapshot];
            [authority revoke];
            PLANKMacDesktopIdentity after = [authority snapshot];
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
        PLANKMacDesktopSnapshot snapshot = ^{ return (PLANKMacDesktopIdentity){true, 1, {123, {1}}}; };
#else
        PLANKMacDesktopSnapshot snapshot = ^{ return [authority snapshot]; };
#endif
        PLANKMacAuthenticationSession *sessions = [[PLANKMacAuthenticationSession alloc] initWithDesktopSnapshot:snapshot];
        PLANKMacHTTPSAuthServer *server = [[PLANKMacHTTPSAuthServer alloc] initWithIdentity:identity sessions:sessions];
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
