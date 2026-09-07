// SPDX-License-Identifier: GPL-3.0-or-later
// Local qualification only. No network listener, privilege or desktop grant.
#import "account-verifier.h"
#import "account-channel.h"
#include <pwd.h>
#include <readpassphrase.h>
#include <sys/resource.h>
#include <unistd.h>

static BOOL emptyIdentity(PLANKMacAccountIdentity identity) {
    const PLANKMacAccountIdentity empty = {0};
    return memcmp(&identity, &empty, sizeof(empty)) == 0;
}

static BOOL wiped(NSData *data) {
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; ++i) if (bytes[i]) return NO;
    return YES;
}

static int selfTest(void) {
    NSArray *names = @[@"", @"ordinary", @"ordinary", @"ordinary",
        [@"x" stringByPaddingToLength:256 withString:@"x" startingAtIndex:0], @"root"];
    const uint8_t invalidUTF8[] = {0xff};
    const uint8_t nul[] = {'x', 0, 'y'};
    NSArray *inputs = @[[NSMutableData dataWithBytes:"x" length:1],
        [NSMutableData data], [NSMutableData dataWithBytes:invalidUTF8 length:1],
        [NSMutableData dataWithBytes:nul length:3],
        [NSMutableData dataWithBytes:"x" length:1],
        [NSMutableData dataWithBytes:"not-a-credential" length:16]];
    for (NSUInteger i = 0; i < names.count; ++i) {
        PLANKMacAccountIdentity identity = {123, {1}};
        if (PLANKMacVerifyAccount(names[i], inputs[i], &identity) != PLANKMacAuthenticationDenied ||
            !emptyIdentity(identity) || !wiped(inputs[i])) return 1;
    }
    NSMutableData *oversized = [NSMutableData dataWithLength:4097];
    memset(oversized.mutableBytes, 'x', oversized.length);
    PLANKMacAccountIdentity identity = {123, {1}};
    if (PLANKMacVerifyAccount(@"ordinary", oversized, &identity) != PLANKMacAuthenticationDenied ||
        !emptyIdentity(identity) || !wiped(oversized)) return 1;
    puts("macos_account_verifier_negative=pass cases=7 password_buffers_wiped=1");
    return 0;
}

int main(int argc, const char *argv[]) {
    if (argc == 2 && !strcmp(argv[1], PLANK_MAC_ACCOUNT_WORKER_ARGUMENT))
        return PLANKMacAccountWorkerMain();
    struct rlimit noCore = {0, 0};
    if (setrlimit(RLIMIT_CORE, &noCore)) return 2;
    alarm(20); // Local probe bounds; a product helper needs parent supervision.
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--self-test") == 0) return selfTest();
        BOOL isolated = argc == 2 && !strcmp(argv[1], "--verify-isolated-current-account");
        if (argc != 2 || (!isolated && strcmp(argv[1], "--verify-current-account")) || geteuid() == 0) return 2;
        struct passwd *account = getpwuid(geteuid());
        if (!account || !account->pw_name) return 2;
        NSString *name = [NSString stringWithUTF8String:account->pw_name];
        char secret[4097] = {0};
        if (!readpassphrase("Development account password: ", secret, sizeof(secret), RPP_REQUIRE_TTY)) return 2;
        NSMutableData *password = [NSMutableData dataWithBytes:secret length:strlen(secret)];
        volatile char *erase = secret;
        for (size_t i = 0; i < sizeof(secret); ++i) erase[i] = 0;
        PLANKMacAccountIdentity identity = {0};
        PLANKMacAuthenticationResult result = isolated ?
            PLANKMacVerifyAccountIsolated(name, password, &identity) :
            PLANKMacVerifyAccount(name, password, &identity);
        BOOL passed = result == PLANKMacAuthenticationVerified && identity.uid == geteuid() && wiped(password);
        printf("macos_account_verified=%d matches_process_account=%d password_buffer_wiped=%d desktop_authorized=0\n",
            result == PLANKMacAuthenticationVerified, identity.uid == geteuid(), wiped(password));
        return passed ? 0 : 1;
    }
}
