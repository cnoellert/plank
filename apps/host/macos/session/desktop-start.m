// SPDX-License-Identifier: GPL-3.0-or-later
#import "desktop-start.h"
#import "../auth/boot-sign-in.h"
#include <unistd.h>

BOOL PLANKMacDesktopStartObserve(PLANKMacDesktopStartState *state, NSDictionary *console) {
    uint32_t uid = 0, audit = 0;
    if ([console isKindOfClass:NSDictionary.class] &&
        [console[@"Name"] isKindOfClass:NSString.class] &&
        [console[@"Name"] length] && ![console[@"Name"] isEqual:@"loginwindow"] &&
        PLANKMacScopeNumber(console[@"UID"], &uid) && uid && uid != UINT32_MAX) {
        id sessions = console[@"SessionInfo"];
        NSDictionary *active = nil;
        if ([sessions isKindOfClass:NSArray.class] && [sessions count] <= 32) {
            for (id record in sessions) {
                if (![record isKindOfClass:NSDictionary.class]) { active = nil; break; }
                if (record[@"kCGSSessionOnConsoleKey"] != (__bridge id)kCFBooleanTrue) continue;
                if (active) { active = nil; break; }
                active = record;
            }
        }
        uint32_t sessionUID = 0;
        if (!active || active[@"kCGSessionLoginDoneKey"] != (__bridge id)kCFBooleanTrue ||
            !PLANKMacScopeNumber(active[@"kCGSSessionUserIDKey"], &sessionUID) || sessionUID != uid ||
            !PLANKMacScopeNumber(active[@"kCGSSessionAuditIDKey"], &audit) || !audit || audit == UINT32_MAX)
            uid = audit = 0;
    } else uid = 0;
    BOOL changed = state->uid != uid || state->audit != audit;
    if (changed) *state = (PLANKMacDesktopStartState){.uid = uid, .audit = audit};
    return changed;
}

BOOL PLANKMacDesktopStartNext(PLANKMacDesktopStartState *state) {
    if (!state->uid || !state->audit || state->finished || state->attempts >= 10) return NO;
    ++state->attempts;
    return YES;
}

@implementation PLANKMacDesktopStart {
    SCDynamicStoreRef _store;
    PLANKMacDesktopStartState _state;
    NSTask *_task;
    BOOL _stopped;
}

- (void)refresh {
    if (_stopped) return;
    NSDictionary *console = CFBridgingRelease(SCDynamicStoreCopyValue(_store, CFSTR("State:/Users/ConsoleUser")));
    PLANKMacDesktopStartObserve(&_state, console);
    if (_task || !PLANKMacDesktopStartNext(&_state)) return;
    uint32_t uid = _state.uid, audit = _state.audit;
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    // No shell, enable, bootstrap, -k, or user-provided executable/arguments.
    // launchd still owns the job, its UID, signing policy and background consent.
    task.arguments = @[@"kickstart", [NSString stringWithFormat:@"gui/%u/la.instinctual.PLANK.Host.desktop", uid]];
    task.standardInput = NSFileHandle.fileHandleWithNullDevice;
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *ended) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) owner = weakSelf;
            if (!owner || owner->_stopped || owner->_task != ended) return;
            owner->_task = nil;
            NSDictionary *current = CFBridgingRelease(SCDynamicStoreCopyValue(owner->_store, CFSTR("State:/Users/ConsoleUser")));
            PLANKMacDesktopStartObserve(&owner->_state, current);
            if (owner->_state.uid == uid && owner->_state.audit == audit) {
                owner->_state.finished = ended.terminationReason == NSTaskTerminationReasonExit && ended.terminationStatus == 0;
                if (owner->_state.finished || owner->_state.attempts == 10)
                    NSLog(@"PLANK desktop agent start uid=%u audit=%u attempts=%u status=%d", uid, audit,
                        owner->_state.attempts, ended.terminationStatus);
            }
            [owner retry];
        });
    };
    NSError *error = nil;
    _task = task;
    if (![task launchAndReturnError:&error]) {
        _task = nil;
        NSLog(@"PLANK desktop agent start could not invoke launchctl (code=%ld)", (long)error.code);
        [self retry];
        return;
    }
    // Never block the coordinator's ownership/authentication loop on launchctl.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        typeof(self) owner = weakSelf;
        if (owner && owner->_task == task && task.running) {
            NSLog(@"PLANK desktop agent start request timed out uid=%u", uid);
            [task terminate];
        }
    });
}

- (void)retry {
    if (_stopped || !_state.uid || _state.finished || _state.attempts >= 10) return;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [weakSelf refresh]; });
}

static void consoleChanged(SCDynamicStoreRef store, CFArrayRef keys, void *context) {
    (void)store; (void)keys;
    [(__bridge PLANKMacDesktopStart *)context refresh];
}

- (BOOL)start {
    if (getuid() != 0 || _store || _stopped) return NO;
    SCDynamicStoreContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
    _store = SCDynamicStoreCreate(NULL, CFSTR("PLANK desktop startup"), consoleChanged, &context);
    if (!_store || !SCDynamicStoreSetNotificationKeys(_store,
        (__bridge CFArrayRef)@[ @"State:/Users/ConsoleUser" ], NULL) ||
        !SCDynamicStoreSetDispatchQueue(_store, dispatch_get_main_queue())) { [self stop]; return NO; }
    [self refresh];
    return YES;
}

- (void)stop {
    _stopped = YES;
    if (_store) { SCDynamicStoreSetDispatchQueue(_store, NULL); CFRelease(_store); _store = NULL; }
    if (_task.running) [_task terminate];
    _task = nil;
}
- (void)dealloc { [self stop]; }
@end
