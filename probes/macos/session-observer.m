// SPDX-License-Identifier: GPL-3.0-or-later
// Bounded passive observer: no login, capture, display creation or input.
#import "session-boundary.h"
#include <notify.h>
#include <string.h>

// Machine-level observation only. Each graphical worker must independently
// verify its own security session before creating a display or capturing.
static PLANKGraphicalSession machineSession(void) {
    PLANKGraphicalSession state = {PLANKSessionUnavailable, 0, 0};
    uid_t uid = (uid_t)-1;
    NSString *name = CFBridgingRelease(SCDynamicStoreCopyConsoleUser(NULL, &uid, NULL));
    if (!name) return state;
    if (uid == 0 && [name isEqualToString:@"loginwindow"]) state.phase = PLANKSessionLoginWindow;
    else if (uid != 0 && uid != (uid_t)-1 && ![name isEqualToString:@"loginwindow"])
        state.phase = PLANKSessionDesktop;
    state.user = uid;
    return state;
}

static int selfTest(void) {
    PLANKGraphicalSession signIn = {PLANKSessionLoginWindow, 0, 1};
    PLANKGraphicalSession desktop = {PLANKSessionDesktop, 501, 1};
    PLANKGraphicalSession otherUser = {PLANKSessionDesktop, 502, 1};
    PLANKGraphicalSession otherConsole = {PLANKSessionDesktop, 501, 2};
    PLANKGraphicalSession unavailable = {PLANKSessionUnavailable, 501, 1};
    BOOL passed = PLANKSessionMatches(signIn, signIn) && PLANKSessionMatches(desktop, desktop) &&
        !PLANKSessionMatches(signIn, desktop) && !PLANKSessionMatches(desktop, signIn) &&
        !PLANKSessionMatches(desktop, otherUser) && !PLANKSessionMatches(desktop, otherConsole) &&
        !PLANKSessionMatches(desktop, unavailable) && !PLANKSessionMatches(unavailable, unavailable);
    uint32_t value = 0;
    passed &= !PLANKSessionNumber(@{}, kCGSessionUserIDKey, &value);
    passed &= !PLANKSessionNumber(@{(__bridge NSString *)kCGSessionUserIDKey: @YES}, kCGSessionUserIDKey, &value);
    passed &= !PLANKSessionNumber(@{(__bridge NSString *)kCGSessionUserIDKey: @(-1)}, kCGSessionUserIDKey, &value);
    passed &= PLANKSessionNumber(@{(__bridge NSString *)kCGSessionUserIDKey: @501}, kCGSessionUserIDKey, &value) && value == 501;
    printf("session_boundary_synthetic_tests=%d\n", passed);
    return passed ? 0 : 1;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        setbuf(stdout, NULL);
        if (argc == 2 && strcmp(argv[1], "--self-test") == 0) return selfTest();
        BOOL machine = argc == 2 && strcmp(argv[1], "--machine-watch") == 0;
        if (argc != 1 && !machine) return 2;
        __block PLANKGraphicalSession previous = {PLANKSessionUnavailable, 0, 0};
        __block BOOL first = YES;
        void (^sample)(void) = ^{
            PLANKGraphicalSession current = machine ? machineSession() : PLANKReadGraphicalSession();
            if (first || current.phase != previous.phase || current.user != previous.user || current.securitySession != previous.securitySession) {
                // No account names, credentials or raw session dictionaries.
                if (machine) printf("{\"phase\":\"%s\",\"uid\":%u}\n", PLANKSessionName(current.phase), current.user);
                else printf("graphical_session phase=%s uid=%u security_session=%u monotonic_s=%.3f\n",
                        PLANKSessionName(current.phase), current.user, current.securitySession, NSProcessInfo.processInfo.systemUptime);
                previous = current;
                first = NO;
            }
        };
        int consoleToken = -1, userToken = -1;
        uint32_t a = notify_register_dispatch(kCGNotifyGUIConsoleSessionChanged, &consoleToken,
            dispatch_get_main_queue(), ^(int token) { (void)token; sample(); });
        uint32_t b = notify_register_dispatch(kCGNotifyGUISessionUserChanged, &userToken,
            dispatch_get_main_queue(), ^(int token) { (void)token; sample(); });
        if (a || b) {
            if (!a) notify_cancel(consoleToken);
            if (!b) notify_cancel(userToken);
            return 2;
        }
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC, 20 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(timer, sample);
        dispatch_resume(timer);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (machine ? 185 : 15) * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            CFRunLoopStop(CFRunLoopGetMain());
        });
        CFRunLoopRun();
        dispatch_source_cancel(timer);
        notify_cancel(consoleToken);
        notify_cancel(userToken);
        if (!machine) printf("session_observer_complete=1 media_started=0 input_posted=0\n");
        return 0;
    }
}
