// SPDX-License-Identifier: GPL-3.0-or-later
// Pure scheduling/OS-record tests. Never starts an agent or changes a user.
#import "desktop-start.h"
#include <assert.h>
static NSDictionary *console(unsigned uid, unsigned audit) {
    return @{@"Name": @"example", @"UID": @(uid), @"SessionInfo": @[
        @{@"kCGSSessionOnConsoleKey": @YES, @"kCGSessionLoginDoneKey": @YES,
          @"kCGSSessionUserIDKey": @(uid), @"kCGSSessionAuditIDKey": @(audit)}]};
}
int main(void) {
    @autoreleasepool {
        PLANKMacDesktopStartState state = {0};
        assert(!PLANKMacDesktopStartObserve(&state, nil));
        assert(!PLANKMacDesktopStartNext(&state));
        assert(PLANKMacDesktopStartObserve(&state, console(901, 100009)));
        assert(PLANKMacDesktopStartNext(&state));
        // Unchanged notifications neither relaunch success nor replenish retries.
        assert(!PLANKMacDesktopStartObserve(&state, console(901, 100009)));
        assert(state.attempts == 1);
        state.finished = YES;
        assert(!PLANKMacDesktopStartNext(&state));
        // Same account's next login must be a distinct scheduling opportunity.
        assert(PLANKMacDesktopStartObserve(&state, console(901, 100010)));
        for (int i = 0; i < 10; ++i) assert(PLANKMacDesktopStartNext(&state));
        assert(!PLANKMacDesktopStartNext(&state));
        assert(!PLANKMacDesktopStartObserve(&state, console(901, 100010)));
        assert(!PLANKMacDesktopStartNext(&state));
        assert(PLANKMacDesktopStartObserve(&state, console(902, 100011)));
        assert(state.attempts == 0 && !state.finished);
        for (NSDictionary *bad in @[@{}, console(0, 100011), console(UINT32_MAX, 100011),
                                     console(902, 0), console(902, UINT32_MAX)]) {
            PLANKMacDesktopStartObserve(&state, bad);
            assert(!PLANKMacDesktopStartNext(&state));
        }
        NSDictionary *valid = console(901, 100009);
        for (NSString *key in valid) {
            NSMutableDictionary *bad = valid.mutableCopy;
            bad[key] = NSNull.null;
            PLANKMacDesktopStartObserve(&state, bad);
            assert(!PLANKMacDesktopStartNext(&state));
        }
        NSDictionary *record = [valid[@"SessionInfo"] firstObject];
        for (NSString *key in record) {
            NSMutableDictionary *badRecord = record.mutableCopy;
            badRecord[key] = NSNull.null;
            NSMutableDictionary *bad = valid.mutableCopy;
            bad[@"SessionInfo"] = @[badRecord];
            PLANKMacDesktopStartObserve(&state, bad);
            assert(!PLANKMacDesktopStartNext(&state));
        }
        NSMutableDictionary *bad = valid.mutableCopy;
        bad[@"SessionInfo"] = @[record, record];
        PLANKMacDesktopStartObserve(&state, bad);
        assert(!PLANKMacDesktopStartNext(&state));
        bad[@"SessionInfo"] = @[record]; bad[@"UID"] = @902;
        PLANKMacDesktopStartObserve(&state, bad);
        assert(!PLANKMacDesktopStartNext(&state));
        puts("macos_desktop_start=pass (no launchd or permission changes)");
    }
    return 0;
}
