// SPDX-License-Identifier: GPL-3.0-or-later
#import "account-channel.h"
#import <Security/Security.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <spawn.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

// Private one-transaction wire format, not a Client protocol: network-order
// uint32 words followed by exact byte counts. Never send native struct padding.
// The existing Client gives an HTTPS auth request five seconds. Reserve time
// for the response instead of leaving an orphan verification after that wait.
enum { ChannelFD = 3, Magic = 0x50414331, Version = 2, DeadlineSeconds = 4 };
static pthread_mutex_t attemptLock = PTHREAD_MUTEX_INITIALIZER;
static uint64_t nextAttempt;

static uint64_t nowNS(void) { return clock_gettime_nsec_np(CLOCK_MONOTONIC); }

static void reportFailure(const char *stage, PLANKMacAuthenticationResult result,
        uint64_t started) {
    // Reconnect loops must not flood the product log. All text is from fixed
    // internal stages, never from Open Directory, credentials or peer metadata.
    static pthread_mutex_t logLock = PTHREAD_MUTEX_INITIALIZER;
    static const char *lastStage;
    static PLANKMacAuthenticationResult lastResult;
    static uint64_t lastTime;
    uint64_t now = nowNS();
    pthread_mutex_lock(&logLock);
    if (!lastStage || strcmp(lastStage, stage) || lastResult != result ||
            now - lastTime >= 5000000000ULL) {
        fprintf(stderr, "macos_auth_verification result=%s stage=%s elapsed_ms=%llu\n",
            result == PLANKMacAuthenticationDenied ? "denied" : "unavailable",
            stage, (unsigned long long)((now - started) / 1000000));
        lastStage = stage; lastResult = result; lastTime = now;
    }
    pthread_mutex_unlock(&logLock);
}

static void erase(void *bytes, size_t length) {
    volatile unsigned char *p = bytes;
    while (length--) *p++ = 0;
}

static bool prepareSocket(int fd) {
    int one = 1;
    int flags = fcntl(fd, F_GETFL);
    return flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 &&
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one)) == 0;
}

static bool ready(int fd, short events, uint64_t deadline) {
    for (;;) {
        uint64_t now = nowNS();
        if (now >= deadline) return false;
        struct pollfd p = {fd, events, 0};
        int ms = (int)((deadline - now + 999999) / 1000000);
        int result = poll(&p, 1, ms);
        if (result < 0 && errno == EINTR) continue;
        return result > 0 && (p.revents & (events | POLLHUP)) != 0;
    }
}

static bool transfer(int fd, void *buffer, size_t size, bool writing, uint64_t deadline) {
    unsigned char *bytes = buffer;
    while (size) {
        if (!ready(fd, writing ? POLLOUT : POLLIN, deadline)) return false;
        ssize_t count = writing ? send(fd, bytes, size, 0) : recv(fd, bytes, size, 0);
        if (count < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        if (count <= 0) return false;
        bytes += count;
        size -= (size_t)count;
    }
    return true;
}

static bool exactEnd(int fd, uint64_t deadline) {
    for (;;) {
        if (!ready(fd, POLLIN, deadline)) return false;
        unsigned char extra;
        ssize_t count = recv(fd, &extra, 1, 0);
        erase(&extra, sizeof(extra));
        if (count < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) continue;
        return count == 0;
    }
}

// Authenticate the running peer, not merely a pathname checked before exec.
// The designated requirement comes from our own signed code. With development
// ad-hoc signatures it pins this exact image; shipping Developer ID signing
// must preserve a product-specific designated requirement and protected install.
static bool sameProductProcess(pid_t pid) {
    SecCodeRef own = NULL, peer = NULL;
    SecRequirementRef requirement = NULL;
    bool ok = SecCodeCopySelf(kSecCSDefaultFlags, &own) == errSecSuccess &&
        SecCodeCopyDesignatedRequirement(own, kSecCSDefaultFlags, &requirement) == errSecSuccess;
    if (ok) {
        NSDictionary *attributes = @{(__bridge NSString *)kSecGuestAttributePid: @(pid)};
        ok = SecCodeCopyGuestWithAttributes(NULL, (__bridge CFDictionaryRef)attributes,
            kSecCSDefaultFlags, &peer) == errSecSuccess &&
            SecCodeCheckValidity(peer, kSecCSStrictValidate, requirement) == errSecSuccess;
    }
    if (peer) CFRelease(peer);
    if (requirement) CFRelease(requirement);
    if (own) CFRelease(own);
    return ok;
}

static bool privateParent(void) {
    int type = 0;
    socklen_t length = sizeof(type);
    struct sockaddr_un address = {0};
    socklen_t addressLength = sizeof(address);
    uid_t uid;
    gid_t gid;
    pid_t peer = 0;
    socklen_t peerLength = sizeof(peer);
    return getuid() == geteuid() && getgid() == getegid() &&
        getsockopt(ChannelFD, SOL_SOCKET, SO_TYPE, &type, &length) == 0 && type == SOCK_STREAM &&
        getsockname(ChannelFD, (struct sockaddr *)&address, &addressLength) == 0 &&
        address.sun_family == AF_UNIX &&
        getpeereid(ChannelFD, &uid, &gid) == 0 && uid == geteuid() &&
        getsockopt(ChannelFD, SOL_LOCAL, LOCAL_PEERPID, &peer, &peerLength) == 0 &&
        peer == getppid() && peer > 1 && sameProductProcess(peer);
}

int PLANKMacAccountWorkerMain(void) {
    struct rlimit noCore = {0, 0};
    if (setrlimit(RLIMIT_CORE, &noCore)) return 2;
    signal(SIGALRM, SIG_DFL);
    alarm(DeadlineSeconds);
    @autoreleasepool {
        if (!privateParent() || !prepareSocket(ChannelFD)) return 2;
        uint64_t deadline = nowNS() + DeadlineSeconds * 1000000000ULL;
        uint32_t header[4] = {0};
        if (!transfer(ChannelFD, header, sizeof(header), false, deadline) ||
            ntohl(header[0]) != Magic || ntohl(header[1]) != Version) return 2;
        uint32_t nameLength = ntohl(header[2]), passwordLength = ntohl(header[3]);
        if (!nameLength || nameLength > 255 || !passwordLength || passwordLength > 4096) return 2;
        NSMutableData *nameBytes = [NSMutableData dataWithLength:nameLength];
        NSMutableData *password = [NSMutableData dataWithLength:passwordLength];
        @try {
            if (!transfer(ChannelFD, nameBytes.mutableBytes, nameLength, false, deadline) ||
                !transfer(ChannelFD, password.mutableBytes, passwordLength, false, deadline) ||
                !exactEnd(ChannelFD, deadline)) return 2;
            NSString *name = [[NSString alloc] initWithData:nameBytes encoding:NSUTF8StringEncoding];
            PLANKMacAccountIdentity identity = {0};
            PLANKMacAuthenticationStage stage = PLANKMacAuthInput;
            PLANKMacAuthenticationResult result = PLANKMacVerifyAccount(name, password, &identity, &stage);
            uint32_t response[4] = {htonl(Magic), htonl(result), htonl(identity.uid), htonl(stage)};
            bool sent = transfer(ChannelFD, response, sizeof(response), true, deadline) &&
                transfer(ChannelFD, identity.uuid, sizeof(identity.uuid), true, deadline);
            shutdown(ChannelFD, SHUT_WR);
            return sent ? 0 : 2;
        } @finally {
            [password resetBytesInRange:NSMakeRange(0, password.length)];
            close(ChannelFD);
        }
    }
}

static bool reap(pid_t pid, uint64_t deadline) {
    for (;;) {
        int status = 0;
        pid_t result = waitpid(pid, &status, WNOHANG);
        if (result == pid) return WIFEXITED(status) && WEXITSTATUS(status) == 0;
        if (result < 0 && errno != EINTR) return false;
        if (nowNS() >= deadline) {
            kill(pid, SIGKILL);
            while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
            return false;
        }
        struct timespec tick = {0, 1000000};
        nanosleep(&tick, NULL);
    }
}

static pid_t launchWorker(int socketFD) {
    char executable[PATH_MAX];
    uint32_t size = sizeof(executable);
    if (_NSGetExecutablePath(executable, &size)) return -1;
    posix_spawn_file_actions_t actions;
    posix_spawnattr_t attributes;
    if (posix_spawn_file_actions_init(&actions)) return -1;
    if (posix_spawnattr_init(&attributes)) {
        posix_spawn_file_actions_destroy(&actions);
        return -1;
    }
    // Explicitly keep only the private socket; stdout/stderr cannot leak an OD
    // diagnostic to product logs. No inherited network sockets or environment.
    sigset_t signals;
    sigemptyset(&signals);
    int error = posix_spawnattr_setsigmask(&attributes, &signals);
    sigaddset(&signals, SIGALRM);
    sigaddset(&signals, SIGTERM);
    sigaddset(&signals, SIGPIPE);
    error |= posix_spawnattr_setsigdefault(&attributes, &signals);
    error |= posix_spawnattr_setflags(&attributes,
        POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF);
    error |= posix_spawn_file_actions_adddup2(&actions, socketFD, ChannelFD);
    for (int fd = 0; fd < 3; ++fd)
        error |= posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", O_RDWR, 0);
    char *argv[] = {executable, PLANK_MAC_ACCOUNT_WORKER_ARGUMENT, NULL};
    char *environment[] = {NULL};
    pid_t child = -1;
    if (!error && posix_spawn(&child, executable, &actions, &attributes, argv, environment)) child = -1;
    posix_spawnattr_destroy(&attributes);
    posix_spawn_file_actions_destroy(&actions);
    return child;
}

PLANKMacAuthenticationResult PLANKMacVerifyAccountIsolated(
        NSString *name, NSMutableData *password, PLANKMacAccountIdentity *output) {
    if (output) memset(output, 0, sizeof(*output));
    bool locked = false;
    uint64_t started = nowNS();
    const char *stage = "input";
    PLANKMacAuthenticationResult outcome = PLANKMacAuthenticationUnavailable;
    int sockets[2] = {-1, -1};
    pid_t child = -1;
    @try {
        NSData *nameBytes = [name dataUsingEncoding:NSUTF8StringEncoding];
        if (!output || !nameBytes.length || nameBytes.length > 255 ||
            memchr(nameBytes.bytes, 0, nameBytes.length) ||
            !password.length || password.length > 4096 || memchr(password.bytes, 0, password.length))
            return (outcome = PLANKMacAuthenticationDenied);
        stage = "process-identity";
        if (getuid() != geteuid() || getgid() != getegid()) return PLANKMacAuthenticationUnavailable;
        // Caller must disable core dumps at service startup before receiving
        // credentials; fail closed rather than silently weaken that contract.
        struct rlimit core;
        stage = "core-policy";
        if (getrlimit(RLIMIT_CORE, &core) || core.rlim_cur != 0) return PLANKMacAuthenticationUnavailable;
        stage = "concurrent-verification";
        if (pthread_mutex_trylock(&attemptLock)) return PLANKMacAuthenticationUnavailable;
        locked = true;
        uint64_t now = nowNS();
        stage = "retry-cooldown";
        if (now < nextAttempt) return PLANKMacAuthenticationUnavailable;
        nextAttempt = now + 2000000000ULL;
        uint64_t deadline = now + DeadlineSeconds * 1000000000ULL;
        stage = "socket";
        if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets)) return PLANKMacAuthenticationUnavailable;
        // Serialize spawning in this component and mark both descriptors closed
        // on exec; CLOEXEC_DEFAULT independently closes all unrelated FDs.
        if (fcntl(sockets[0], F_SETFD, FD_CLOEXEC) || fcntl(sockets[1], F_SETFD, FD_CLOEXEC) ||
            !prepareSocket(sockets[0])) return PLANKMacAuthenticationUnavailable;
        stage = "helper-launch";
        child = launchWorker(sockets[1]);
        close(sockets[1]); sockets[1] = -1;
        if (child <= 0) return PLANKMacAuthenticationUnavailable;
        stage = "helper-signature";
        if (!sameProductProcess(child)) return PLANKMacAuthenticationUnavailable;
        uint32_t header[4] = {htonl(Magic), htonl(Version),
            htonl((uint32_t)nameBytes.length), htonl((uint32_t)password.length)};
        stage = "helper-request";
        if (!transfer(sockets[0], header, sizeof(header), true, deadline) ||
            !transfer(sockets[0], (void *)nameBytes.bytes, nameBytes.length, true, deadline) ||
            !transfer(sockets[0], password.mutableBytes, password.length, true, deadline) ||
            shutdown(sockets[0], SHUT_WR)) return PLANKMacAuthenticationUnavailable;
        [password resetBytesInRange:NSMakeRange(0, password.length)];
        stage = "helper-response";
        uint32_t response[4] = {0};
        PLANKMacAccountIdentity identity = {0};
        if (!transfer(sockets[0], response, sizeof(response), false, deadline) ||
            !transfer(sockets[0], identity.uuid, sizeof(identity.uuid), false, deadline) ||
            !exactEnd(sockets[0], deadline)) return PLANKMacAuthenticationUnavailable;
        stage = "helper-exit";
        bool cleanExit = reap(child, deadline);
        child = -1;
        if (!cleanExit) return PLANKMacAuthenticationUnavailable;
        stage = "helper-framing";
        if (ntohl(response[0]) != Magic || ntohl(response[1]) > PLANKMacAuthenticationUnavailable ||
                ntohl(response[3]) > PLANKMacAuthException)
            return PLANKMacAuthenticationUnavailable;
        PLANKMacAuthenticationResult result = ntohl(response[1]);
        identity.uid = ntohl(response[2]);
        if (result == PLANKMacAuthenticationVerified) {
            if (!plank_macos_account_identity_valid(identity) ||
                    ntohl(response[3]) != PLANKMacAuthComplete) return PLANKMacAuthenticationUnavailable;
            *output = identity;
        } else {
            PLANKMacAccountIdentity empty = {0};
            if (memcmp(&identity, &empty, sizeof(empty))) return PLANKMacAuthenticationUnavailable;
        }
        static const char *directoryStages[] = {"directory-input", "directory-node",
            "directory-record", "directory-identity", "directory-password-policy",
            "directory-identity-recheck", "directory-complete", "directory-exception"};
        stage = directoryStages[ntohl(response[3])];
        return (outcome = result);
    } @catch (NSException *exception) {
        (void)exception;
        stage = "parent-exception";
        if (output) memset(output, 0, sizeof(*output));
        return PLANKMacAuthenticationUnavailable;
    } @finally {
        [password resetBytesInRange:NSMakeRange(0, password.length)];
        if (sockets[0] >= 0) close(sockets[0]);
        if (sockets[1] >= 0) close(sockets[1]);
        if (child > 0) { kill(child, SIGKILL); reap(child, nowNS()); }
        if (locked) pthread_mutex_unlock(&attemptLock);
        if (outcome != PLANKMacAuthenticationVerified) reportFailure(stage, outcome, started);
    }
}
