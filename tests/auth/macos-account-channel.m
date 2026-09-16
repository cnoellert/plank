// SPDX-License-Identifier: GPL-3.0-or-later
// Mac-only private IPC qualification. Synthetic verifier, NEVER Open Directory.
// Include the implementation to exercise framing failure paths without adding
// test hooks or failure-injection switches to the product component.
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <stdlib.h>
#include "account-channel.m"

PLANKMacAuthenticationResult PLANKMacVerifyAccount(
        NSString *name, NSMutableData *password, PLANKMacAccountIdentity *output,
        PLANKMacAuthenticationStage *stage) {
    *stage = PLANKMacAuthPassword;
    memset(output, 0, sizeof(*output));
    @try {
        struct rlimit core;
        assert(!getrlimit(RLIMIT_CORE, &core) && core.rlim_cur == 0);
        assert(fcntl(77, F_GETFD) == -1 && errno == EBADF);
        assert(getenv("PLANK_AUTH_SYNTHETIC_SECRET") == NULL);
        if ([name isEqualToString:@"hang"]) { for (;;) pause(); }
        if ([name isEqualToString:@"crash"]) _exit(8);
        if ([name isEqualToString:@"unavailable"]) {
            *stage = PLANKMacAuthDirectory;
            return PLANKMacAuthenticationUnavailable;
        }
        if ([name isEqualToString:@"bad-stage"]) *stage = (PLANKMacAuthenticationStage)999;
        if ([name isEqualToString:@"synthetic"] && password.length == 4 &&
            memcmp(password.bytes, "test", 4) == 0) {
            output->uid = 123;
            output->uuid[0] = 1;
            *stage = PLANKMacAuthComplete;
            return PLANKMacAuthenticationVerified;
        }
        return PLANKMacAuthenticationDenied;
    } @finally {
        [password resetBytesInRange:NSMakeRange(0, password.length)];
    }
}

static bool wiped(NSData *data) {
    const uint8_t *p = data.bytes;
    for (NSUInteger i = 0; i < data.length; ++i) if (p[i]) return false;
    return true;
}

static void isolated(NSString *name, PLANKMacAuthenticationResult expected) {
    NSMutableData *password = [NSMutableData dataWithBytes:"test" length:4];
    PLANKMacAccountIdentity identity = {999, {9}};
    PLANKMacAuthenticationResult result = PLANKMacVerifyAccountIsolated(name, password, &identity);
    if (result != expected) fprintf(stderr, "isolated result=%u expected=%u\n", result, expected);
    assert(result == expected && wiped(password));
    if (expected == PLANKMacAuthenticationVerified) assert(identity.uid == 123 && identity.uuid[0] == 1);
    else { PLANKMacAccountIdentity empty = {0}; assert(!memcmp(&identity, &empty, sizeof(empty))); }
}

static void malformed(uint32_t magic, uint32_t version, uint32_t nameLength,
        uint32_t passwordLength, const char *body, size_t bodyLength) {
    int sockets[2];
    assert(!socketpair(AF_UNIX, SOCK_STREAM, 0, sockets));
    assert(prepareSocket(sockets[0]));
    pid_t child = launchWorker(sockets[1]);
    assert(child > 0);
    close(sockets[1]);
    assert(sameProductProcess(child));
    uint64_t deadline = nowNS() + 2000000000ULL;
    uint32_t header[] = {htonl(magic), htonl(version), htonl(nameLength), htonl(passwordLength)};
    // A malformed header may make the helper exit before the body is written.
    (void)transfer(sockets[0], header, sizeof(header), true, deadline);
    if (bodyLength) (void)transfer(sockets[0], (void *)body, bodyLength, true, deadline);
    shutdown(sockets[0], SHUT_WR);
    uint32_t response[3];
    assert(!transfer(sockets[0], response, sizeof(response), false, deadline));
    assert(!reap(child, deadline));
    close(sockets[0]);
}

int main(int argc, const char *argv[]) {
    if (argc == 2 && !strcmp(argv[1], PLANK_MAC_ACCOUNT_WORKER_ARGUMENT))
        return PLANKMacAccountWorkerMain();
    assert(argc == 1);
    struct rlimit noCore = {0, 0};
    assert(!setrlimit(RLIMIT_CORE, &noCore));
    alarm(40);
    @autoreleasepool {
        assert(!privateParent()); // No inherited socket: direct invocation fails.
        assert(!sameProductProcess(getppid())); // Shell/SSH is not our executable.
        int unrelated = open("/dev/null", O_RDWR);
        assert(unrelated >= 0 && dup2(unrelated, 77) == 77);
        close(unrelated);
        assert(!setenv("PLANK_AUTH_SYNTHETIC_SECRET", "not-a-real-secret", 1));
        isolated(@"synthetic", PLANKMacAuthenticationVerified);
        isolated(@"synthetic", PLANKMacAuthenticationVerified); // Success never consumes retry backoff.
        assert(!pthread_mutex_lock(&attemptLock));
        isolated(@"synthetic", PLANKMacAuthenticationUnavailable); // Concurrent attempt.
        pthread_mutex_unlock(&attemptLock);
        nextAttempt = 0; // Tests access internals, not a product bypass switch.
        isolated(@"denied", PLANKMacAuthenticationDenied);
        isolated(@"synthetic", PLANKMacAuthenticationUnavailable); // Failed verification retains backoff.
        nextAttempt = 0;
        isolated(@"unavailable", PLANKMacAuthenticationUnavailable);
        nextAttempt = 0;
        isolated(@"bad-stage", PLANKMacAuthenticationUnavailable);
        nextAttempt = 0;
        isolated(@"crash", PLANKMacAuthenticationUnavailable);
        nextAttempt = 0;
        uint64_t start = nowNS();
        isolated(@"hang", PLANKMacAuthenticationUnavailable);
        assert(nowNS() - start < 6000000000ULL);
        malformed(0, Version, 1, 1, "ab", 2);
        malformed(Magic, 9, 1, 1, "ab", 2);
        malformed(Magic, Version, 256, 1, NULL, 0);
        malformed(Magic, Version, 1, 4097, NULL, 0);
        malformed(Magic, Version, 0, 1, "a", 1);
        malformed(Magic, Version, 1, 0, "a", 1);
        malformed(Magic, Version, 1, 1, "a", 1); // Truncated secret.
        malformed(Magic, Version, 1, 1, "abc", 3); // Trailing request bytes.
        int status;
        assert(waitpid(-1, &status, WNOHANG) == -1 && errno == ECHILD);
        close(77);
        puts("macos_account_channel=pass cases=19 synthetic_only=1 children_reaped=1");
    }
    return 0;
}
