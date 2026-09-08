// SPDX-License-Identifier: GPL-3.0-or-later
#import "boot-sign-in.h"
#include <stdio.h>
static unsigned checks;
#define CHECK(x) do { ++checks; if (!(x)) { fprintf(stderr, "boot scope failed at %d\n", __LINE__); return 1; } } while (0)
int main(void) {
    @autoreleasepool {
        // Deliberately not the observed UID: resolve the system account, not a
        // hardcoded numeric model of one developer Mac.
        NSDictionary *record = @{@"kCGSSessionOnConsoleKey": @YES, @"kCGSessionLoginDoneKey": @NO,
            @"kCGSSessionUserNameKey": @"unknown", @"kCGSSessionUserIDKey": @987,
            @"kCGSSessionAuditIDKey": @100002, @"kSCSecuritySessionID": @100002};
        NSDictionary *console = @{@"SessionInfo": @[record]};
        CHECK(PLANKMacBootSignInRecord(record, 100002, 987));
        CHECK(PLANKMacBootSignInConsole(console, 100002, 987));
        CHECK(!PLANKMacBootSignInConsole(nil, 100002, 987));
        CHECK(!PLANKMacBootSignInConsole(@{}, 100002, 987));
        CHECK(!PLANKMacBootSignInConsole(@{@"SessionInfo": @[]}, 100002, 987));
        CHECK(!PLANKMacBootSignInConsole(@{@"SessionInfo": @[record, record]}, 100002, 987));
        CHECK(!PLANKMacBootSignInConsole(@{@"SessionInfo": @[@"invalid"]}, 100002, 987));
        CHECK(!PLANKMacBootSignInConsole(@{@"SessionInfo": @[record], @"Name": @"loginwindow"}, 100002, 987));
        CHECK(!PLANKMacBootSignInConsole(@{@"SessionInfo": @[record], @"UID": @502}, 100002, 987));
        for (NSNumber *audit in @[@0, @100003, @(UINT32_MAX)])
            CHECK(!PLANKMacBootSignInConsole(console, audit.unsignedIntValue, 987));
        for (NSNumber *uid in @[@0, @502, @(UINT32_MAX)])
            CHECK(!PLANKMacBootSignInConsole(console, 100002, uid.unsignedIntValue));
        for (NSString *key in record) {
            NSMutableDictionary *changed = [record mutableCopy];
            [changed removeObjectForKey:key];
            CHECK(!PLANKMacBootSignInConsole(@{@"SessionInfo": @[changed]}, 100002, 987));
            changed[key] = NSNull.null;
            CHECK(!PLANKMacBootSignInConsole(@{@"SessionInfo": @[changed]}, 100002, 987));
        }
        for (NSString *key in @[@"kCGSSessionAuditIDKey", @"kSCSecuritySessionID", @"kCGSSessionUserIDKey"])
            for (id value in @[@YES, @(-1), @0.5, @"100002", @(UINT64_MAX), @100003]) {
                NSMutableDictionary *changed = [record mutableCopy]; changed[key] = value;
                CHECK(!PLANKMacBootSignInConsole(@{@"SessionInfo": @[changed]}, 100002, 987));
            }
        for (NSString *key in @[@"kCGSSessionOnConsoleKey", @"kCGSessionLoginDoneKey"]) {
            NSMutableDictionary *changed = [record mutableCopy];
            changed[key] = [key isEqual:@"kCGSessionLoginDoneKey"] ? @YES : @NO;
            CHECK(!PLANKMacBootSignInConsole(@{@"SessionInfo": @[changed]}, 100002, 987));
        }
        NSMutableDictionary *named = [record mutableCopy]; named[@"kCGSSessionUserNameKey"] = @"desktop-user";
        CHECK(!PLANKMacBootSignInConsole(@{@"SessionInfo": @[named]}, 100002, 987));
        printf("macos_boot_sign_in_predicates=pass checks=%u\n", checks);
    }
    return 0;
}
