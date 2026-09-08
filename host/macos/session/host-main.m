// SPDX-License-Identifier: GPL-3.0-or-later
// Experimental native Host entry point. No fixture verifier, expiry alarm or
// loopback-only replacement server. Installation/signing remains a release gate.
#import "host-runtime.h"
#import "agent-connection.h"
#import "graphical-authority.h"
#import "fixed-capture.h"
#import "desktop-display.h"
#import "screen-capture.h"
#import <AppKit/AppKit.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <unistd.h>
#include <stdatomic.h>

#ifndef PLANK_MACOS_HOST_VERSION
#error Build must supply an explicit branch-qualified Host version
#endif

static int startupFailure(const char *stage) {
    fprintf(stderr, "PLANK Host startup rejected: %s\n", stage);
    return 2;
}

// Read only a bounded regular file inside the already-open role-private
// directory. No symlink-following, shared machine key, framework keychain
// import, password argument or network-selected file path.
static NSMutableData *readPrivate(int directory, const char *name) {
    int fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
    struct stat st;
    if (fd < 0) return nil;
    if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_uid != geteuid() ||
        (st.st_mode & 0777) != 0600 || st.st_size <= 0 || st.st_size > 32768) {
        close(fd); return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)st.st_size];
    size_t offset = 0;
    while (offset < data.length) {
        ssize_t count = read(fd, (char *)data.mutableBytes + offset, data.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        offset += (size_t)count;
    }
    char extra;
    BOOL exact = offset == data.length && read(fd, &extra, 1) == 0;
    close(fd);
    if (!exact) { [data resetBytesInRange:NSMakeRange(0, data.length)]; return nil; }
    return data;
}

static BOOL samePEM(NSData *pem, NSData *der, NSString *label) {
    NSString *text = [[NSString alloc] initWithData:pem encoding:NSASCIIStringEncoding];
    NSArray *lines = [[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    if (lines.count < 3 || ![lines.firstObject isEqual:[NSString stringWithFormat:@"-----BEGIN %@-----", label]] ||
        ![lines.lastObject isEqual:[NSString stringWithFormat:@"-----END %@-----", label]]) return NO;
    NSString *body = [[lines subarrayWithRange:NSMakeRange(1, lines.count - 2)] componentsJoinedByString:@""];
    NSMutableData *decoded = [[[NSData alloc] initWithBase64EncodedString:body options:0] mutableCopy];
    BOOL equal = decoded && [decoded isEqual:der];
    [decoded resetBytesInRange:NSMakeRange(0, decoded.length)];
    return equal;
}

static void signals(void (^stop)(void)) {
    // Retained for the lifetime of this executable; never synchronous cleanup
    // from a POSIX signal handler.
    static NSMutableArray *sources;
    sources = [NSMutableArray array];
    for (NSNumber *value in @[@(SIGTERM), @(SIGINT)]) {
        signal(value.intValue, SIG_IGN);
        dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,
            value.unsignedIntValue, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(source, stop);
        [sources addObject:source]; dispatch_resume(source);
    }
}

static int machine(const char *service) {
    if (getuid() != 0) return 2;
    NSString *requirement = PLANKMacOwnSigningRequirement();
    __block __weak PLANKMacAgentRegistry *weakRegistry;
    __block dispatch_source_t exitWatch = nil;
    PLANKMacAgentRegistry *registry = [[PLANKMacAgentRegistry alloc]
        initWithQueue:dispatch_get_main_queue() requirement:requirement
        scope:^PLANKMacAgentPhase(PLANKMacAgentPeer peer) { return PLANKMacObserveAgentScope(peer); }
        event:^(PLANKMacAgentLease *lease, PLANKMacAgentEvent event) {
            if (event != PLANKMacAgentAttached) return;
            // This initial runtime creates NO virtual displays or media child
            // processes. Process exit independently proves its local media/input
            // resources are gone. An XPC retirement ACK alone does not suffice.
            // Display-owner integration must extend this proof before enabling it.
            exitWatch = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, lease.peer.pid,
                DISPATCH_PROC_EXIT, dispatch_get_main_queue());
            if (!exitWatch) { [weakRegistry revoke]; return; }
            dispatch_source_set_event_handler(exitWatch, ^{
                [weakRegistry revoke];
                BOOL removed = [weakRegistry completeRetirement:lease];
                dispatch_source_cancel(exitWatch); exitWatch = nil;
                NSLog(@"PLANK Host graphical process exited; ownership released=%d", removed);
            });
            dispatch_resume(exitWatch);
        }];
    if (!registry) return 2;
    weakRegistry = registry;
    xpc_connection_t listener = xpc_connection_create_mach_service(service, dispatch_get_main_queue(),
        XPC_CONNECTION_MACH_SERVICE_LISTENER);
    if (!listener) return 2;
    xpc_connection_set_event_handler(listener, ^(xpc_object_t peer) {
        if (xpc_get_type(peer) == XPC_TYPE_CONNECTION) [registry accept:peer];
    });
    xpc_connection_activate(listener);
    signals(^{ [registry stop]; xpc_connection_cancel(listener); exit(0); });
    NSLog(@"PLANK Host machine coordinator started");
    [[NSRunLoop mainRunLoop] run]; return 0;
}

static int graphical(const char *service, NSString *role, NSString *directory) {
    NSApplication *application = NSApplication.sharedApplication;
    [application setActivationPolicy:NSApplicationActivationPolicyProhibited];
    PLANKMacGraphicalPhase phase = [role isEqual:@"desktop"] ? PLANKMacScopeDesktop :
        [role isEqual:@"sign-in"] ? PLANKMacScopeSignIn : PLANKMacScopeUnavailable;
    PLANKMacGraphicalAuthority *authority = [[PLANKMacGraphicalAuthority alloc] initWithPhase:phase];
    PLANKMacGraphicalIdentity initial = [authority snapshot];
    if (!plank_macos_graphical_identity_valid(initial)) return startupFailure("graphical-scope");
    if (!directory.isAbsolutePath) return startupFailure("configuration-path");
    int fd = open(directory.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    struct stat st;
    if (fd < 0) return startupFailure("configuration-directory");
    if (fstat(fd, &st) || st.st_uid != geteuid() || (st.st_mode & 0777) != 0700) {
        close(fd); return startupFailure("configuration-permissions");
    }
    NSMutableData *configBytes = readPrivate(fd, "host.plist");
    NSMutableData *certificateBytes = readPrivate(fd, "cert.der"), *keyBytes = readPrivate(fd, "key.der");
    NSMutableData *certificatePEM = readPrivate(fd, "cert.pem"), *keyPEM = readPrivate(fd, "key.pem");
    close(fd);
    NSDictionary *config = configBytes ? [NSPropertyListSerialization propertyListWithData:configBytes
        options:NSPropertyListImmutable format:NULL error:NULL] : nil;
    if (![config isKindOfClass:NSDictionary.class] || config.count != 4 ||
        ![config[@"Address"] isKindOfClass:NSString.class] || ![config[@"Name"] isKindOfClass:NSString.class] ||
        ![config[@"UUID"] isKindOfClass:NSString.class] || ![config[@"Port"] isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)config[@"Port"]) == CFBooleanGetTypeID() ||
        [config[@"Port"] doubleValue] != [config[@"Port"] unsignedShortValue] ||
        [config[@"Port"] unsignedShortValue] == 0) return startupFailure("configuration-values");
    if (!samePEM(certificatePEM, certificateBytes, @"CERTIFICATE")) return startupFailure("certificate-files");
    if (!samePEM(keyPEM, keyBytes, @"RSA PRIVATE KEY")) return startupFailure("private-key-files");
    SecCertificateRef certificate = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)certificateBytes);
    NSDictionary *attributes = @{(__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate};
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)keyBytes, (__bridge CFDictionaryRef)attributes, NULL);
    [keyBytes resetBytesInRange:NSMakeRange(0, keyBytes.length)];
    [keyPEM resetBytesInRange:NSMakeRange(0, keyPEM.length)];
    SecIdentityRef identity = certificate && key ? SecIdentityCreate(NULL, certificate, key) : NULL;
    if (certificate) CFRelease(certificate);
    if (key) CFRelease(key);
    if (!identity) return startupFailure("tls-identity");
    PLANKMacServerInformation *information = [[PLANKMacServerInformation alloc] initWithName:config[@"Name"]
        workstationUUID:[[NSUUID alloc] initWithUUIDString:config[@"UUID"]] version:@PLANK_MACOS_HOST_VERSION streaming:YES];
    PLANKMacFixedCapture *capture = [PLANKMacFixedCapture new];
    PLANKMacDesktopDisplay *desktopDisplay = [PLANKMacDesktopDisplay new];
    __block PLANKMacHostRuntime *runtime;
    __block __weak PLANKMacAgentConnection *weakAgent;
    __block BOOL stopping = NO;
    void (^stop)(void) = ^{
        if (stopping) return;
        stopping = YES;
        [runtime stopWithCompletion:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakAgent retire];
                // Retirement acknowledgement can be unavailable if the machine
                // service died. Drained process exit is still the cleanup proof.
                NSLog(@"PLANK Host control, video, audio and input drained");
                exit(0);
            });
        }];
    };
    xpc_connection_t peer = xpc_connection_create_mach_service(service, dispatch_get_main_queue(),
        XPC_CONNECTION_MACH_SERVICE_PRIVILEGED);
    PLANKMacAgentConnection *agent = [[PLANKMacAgentConnection alloc] initWithPeer:peer
        queue:dispatch_get_main_queue() requirement:PLANKMacOwnSigningRequirement() serverUID:0
        phase:phase == PLANKMacScopeDesktop ? PLANKMacAgentDesktop : PLANKMacAgentLoginWindow
        valid:^BOOL { return plank_macos_same_graphical_scope(initial, [authority snapshot]); }
        event:^(PLANKMacAgentConnectionState state, uint64_t generation) {
            (void)generation;
            if (state == PLANKMacAgentReady && !stopping) {
                if (![runtime startOnPort:[config[@"Port"] unsignedShortValue] ready:^(uint16_t port) {
                    NSLog(@"PLANK Host listening on %@:%u (TLS control/native QUIC)", config[@"Address"], port);
                } failed:^{ dispatch_async(dispatch_get_main_queue(), stop); }]) stop();
            } else if (state == PLANKMacAgentRetiring || state == PLANKMacAgentDisconnected || state == PLANKMacAgentFinished) stop();
        }];
    weakAgent = agent;
    runtime = [[PLANKMacHostRuntime alloc] initWithIdentity:identity information:information
        snapshot:^{ return [weakAgent bindGraphicalScope:[authority snapshot]]; }
        topology:^{ return [capture snapshot]; } address:config[@"Address"]
        certificate:[directory stringByAppendingPathComponent:@"cert.pem"]
        privateKey:[directory stringByAppendingPathComponent:@"key.pem"]
        capture:^id<PLANKMacPreviewCapture> { return [PLANKMacScreenCapture new]; }
        input:^id<PLANKMacInputDevice> { return [PLANKMacQuartzInput new]; }];
    if (phase == PLANKMacScopeDesktop) runtime.prepareDisplay = ^BOOL(unsigned width, unsigned height, BOOL (^valid)(void)) {
        if (!PLANKMacDesktopModeSupported(width, height)) return NO;
        dispatch_semaphore_t finished = dispatch_semaphore_create(0);
        __block atomic_bool cancelled = false, ready = false;
        dispatch_async(dispatch_get_main_queue(), ^{
            [desktopDisplay prepareWidth:width height:height
                valid:^BOOL { return !atomic_load(&cancelled) && valid(); }
                completion:^(BOOL success) {
                    if (success && !atomic_load(&cancelled) && valid()) {
                        capture.selectedDisplay = desktopDisplay.displayID;
                        atomic_store(&ready, true);
                    }
                    dispatch_semaphore_signal(finished);
                }];
        });
        // Only the bounded authentication lane waits, never the graphical or
        // network event loops. A timeout revokes pending mutation, not authority.
        BOOL completed = dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 7*NSEC_PER_SEC)) == 0;
        atomic_store(&cancelled, true);
        return completed && atomic_load(&ready);
    };
    CFRelease(identity);
    if (!agent || !runtime || ![agent start]) return startupFailure("runtime-admission");
    signals(stop);
    // Quartz display reconfiguration also needs AppKit's event processing.
    // A bare Foundation run loop services our timers but leaves an observed
    // virtual display offline. Keep the graphical agent headless, not eventless.
    [application run]; return 0;
}

int main(int argc, const char **argv) {
    struct rlimit noCore = {0, 0};
    if (setrlimit(RLIMIT_CORE, &noCore) || getuid() != geteuid()) return 2;
    @autoreleasepool {
        if (argc == 2 && !strcmp(argv[1], PLANK_MAC_ACCOUNT_WORKER_ARGUMENT)) return PLANKMacAccountWorkerMain();
        if (argc == 2 && !strcmp(argv[1], "--version")) {
            puts("PLANK Host " PLANK_MACOS_HOST_VERSION); return 0;
        }
        if (argc == 1 || (argc == 2 && !strcmp(argv[1], "--request-permissions"))) {
            NSApplication *app = NSApplication.sharedApplication;
            [app setActivationPolicy:NSApplicationActivationPolicyRegular];
            dispatch_async(dispatch_get_main_queue(), ^{
                BOOL screen = CGPreflightScreenCaptureAccess();
                BOOL input = AXIsProcessTrusted();
                if (screen && input) {
                    puts("PLANK Host permissions ready");
                    [app terminate:nil];
                    return;
                }
                if (!screen) screen = CGRequestScreenCaptureAccess();
                if (!input) {
                    NSDictionary *options = @{(__bridge id)kAXTrustedCheckOptionPrompt: @YES};
                    input = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
                }
                // A permission request may complete before returning. Do not
                // show stale setup instructions after permission was granted.
                screen = CGPreflightScreenCaptureAccess();
                input = AXIsProcessTrusted();
                if (screen && input) {
                    puts("PLANK Host permissions ready");
                    [app terminate:nil];
                    return;
                }
                NSAlert *alert = [NSAlert new];
                alert.messageText = @"PLANK Host permission required";
                alert.informativeText = [NSString stringWithFormat:
                    @"Version %s\n\nScreen & System Audio Recording: %@\nAccessibility: %@\n\n"
                     "Enable PLANK Host in System Settings → Privacy & Security. These permissions belong to "
                     "PLANK Host, separately from PLANK Host Probe. Reopen this app after enabling them. "
                     "This permission window does not start a remote session.",
                    PLANK_MACOS_HOST_VERSION, screen ? @"Allowed" : @"Required", input ? @"Allowed" : @"Required"];
                [alert addButtonWithTitle:@"Close"];
                [app activate]; [alert runModal]; [app terminate:nil];
            });
            [app run]; return 0;
        }
        if (argc == 3 && !strcmp(argv[1], "--machine")) return machine(argv[2]);
        if (argc == 5 && !strcmp(argv[1], "--graphical"))
            return graphical(argv[2], [NSString stringWithUTF8String:argv[3]], [NSString stringWithUTF8String:argv[4]]);
        fprintf(stderr, "Usage: plank-host --machine MACH_SERVICE | --graphical MACH_SERVICE desktop|sign-in PRIVATE_DIRECTORY\n");
        return 2;
    }
}
