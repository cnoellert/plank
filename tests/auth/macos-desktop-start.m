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
        assert(!PLANKMacDesktopStartExited(&state, 901, 100009));
        assert(PLANKMacDesktopStartRetrySeconds(&state) == 0);
        assert(PLANKMacDesktopStartObserve(&state, console(901, 100009)));
        assert(PLANKMacDesktopStartNext(&state));
        // Unchanged notifications neither relaunch success nor replenish retries.
        assert(!PLANKMacDesktopStartObserve(&state, console(901, 100009)));
        assert(state.attempts == 1);
        PLANKMacDesktopStartComplete(&state, 901, 100009, YES);
        assert(!PLANKMacDesktopStartNext(&state));
        assert(PLANKMacDesktopStartRetrySeconds(&state) == 0);
        // Regression: launchctl returned success, but the admitted worker
        // subsequently failed to bind. A deferred KeepAlive must not strand it.
        assert(PLANKMacDesktopStartExited(&state, 901, 100009));
        assert(!state.finished && state.workerExited && state.attempts == 1);
        assert(PLANKMacDesktopStartRetrySeconds(&state) == 1);
        // A late launchctl success must not erase that observed worker exit.
        PLANKMacDesktopStartComplete(&state, 901, 100009, YES);
        assert(!state.finished);
        assert(PLANKMacDesktopStartNext(&state));
        assert(state.attempts == 2 && !state.workerExited);
        PLANKMacDesktopStartComplete(&state, 901, 100009, YES);
        assert(state.finished);
        // Neither a different user nor an old audit session may re-arm it.
        assert(!PLANKMacDesktopStartExited(&state, 902, 100009));
        assert(!PLANKMacDesktopStartExited(&state, 901, 100008));
        assert(!PLANKMacDesktopStartExited(&state, 0, 100009));
        PLANKMacDesktopStartComplete(&state, 902, 100009, NO);
        PLANKMacDesktopStartComplete(&state, 901, 100008, NO);
        assert(state.finished && state.attempts == 2);
        // Same account's next login must be a distinct scheduling opportunity.
        assert(PLANKMacDesktopStartObserve(&state, console(901, 100010)));
        const unsigned delays[] = {1, 2, 4, 8, 16, 16, 16, 16, 16, 0};
        unsigned totalDelay = 0;
        for (unsigned i = 0; i < 10; ++i) {
            assert(PLANKMacDesktopStartNext(&state));
            PLANKMacDesktopStartComplete(&state, 901, 100010, YES);
            assert(PLANKMacDesktopStartExited(&state, 901, 100010));
            assert(PLANKMacDesktopStartRetrySeconds(&state) == delays[i]);
            totalDelay += delays[i];
            // Duplicate exits/unchanged notifications never replenish budget.
            assert(PLANKMacDesktopStartExited(&state, 901, 100010));
            assert(!PLANKMacDesktopStartObserve(&state, console(901, 100010)));
            assert(state.attempts == i + 1);
        }
        assert(totalDelay == 95);
        assert(!PLANKMacDesktopStartNext(&state));
        assert(!PLANKMacDesktopStartObserve(&state, console(901, 100010)));
        assert(!PLANKMacDesktopStartNext(&state));
        assert(PLANKMacDesktopStartObserve(&state, console(902, 100011)));
        assert(state.attempts == 0 && !state.finished);
        // The old user's process-exit notification may arrive after handoff.
        assert(!PLANKMacDesktopStartExited(&state, 901, 100010));
        PLANKMacDesktopStartComplete(&state, 901, 100010, YES);
        assert(PLANKMacDesktopStartNext(&state));
        PLANKMacDesktopStartComplete(&state, 902, 100011, NO);
        assert(!state.finished && PLANKMacDesktopStartRetrySeconds(&state) == 1);
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
        puts("macos_desktop_start=pass post_exit_recovery=1 bounded_backoff=1 cross_user_denied=1 (no launchd or permission changes)");
    }
    return 0;
}
