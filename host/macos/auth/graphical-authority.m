// SPDX-License-Identifier: GPL-3.0-or-later
#import "graphical-authority.h"
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Security/AuthSession.h>
#import <Security/Security.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <membership.h>
#include <unistd.h>

static BOOL readGraphical(PLANKMacGraphicalPhase phase, PLANKMacAccountIdentity *account, SecuritySessionId *sessionID) {
    memset(account, 0, sizeof(*account));
    if (getuid() != geteuid() ||
        (phase == PLANKMacScopeDesktop ? !geteuid() : phase != PLANKMacScopeSignIn || geteuid() != 0)) return NO;
    SessionAttributeBits attributes = 0;
    if (SessionGetInfo(callerSecuritySession, sessionID, &attributes) != errSecSuccess ||
        *sessionID == noSecuritySession || !(attributes & sessionHasGraphicAccess)) return NO;
    NSDictionary *session = CFBridgingRelease(CGSessionCopyCurrentDictionary());
    if (!session || session[(__bridge NSString *)kCGSessionOnConsoleKey] != (__bridge id)kCFBooleanTrue) return NO;
    id done = session[(__bridge NSString *)kCGSessionLoginDoneKey];
    id number = session[(__bridge NSString *)kCGSessionUserIDKey];
    int64_t uid = -1;
    if (!number || CFGetTypeID((__bridge CFTypeRef)number) != CFNumberGetTypeID() ||
        !CFNumberGetValue((__bridge CFNumberRef)number, kCFNumberSInt64Type, &uid) ||
        uid != geteuid()) return NO;
    uid_t consoleUID = (uid_t)-1;
    NSString *name = CFBridgingRelease(SCDynamicStoreCopyConsoleUser(NULL, &consoleUID, NULL));
    if (!name || consoleUID != geteuid()) return NO;
    if (phase == PLANKMacScopeSignIn)
        return done == (__bridge id)kCFBooleanFalse && [name isEqualToString:@"loginwindow"];
    if (done != (__bridge id)kCFBooleanTrue || [name isEqualToString:@"loginwindow"]) return NO;
    account->uid = (uint32_t)uid;
    return !mbr_uid_to_uuid(consoleUID, account->uuid) && plank_macos_account_identity_valid(*account);
}

@implementation PLANKMacGraphicalAuthority {
    PLANKMacGraphicalIdentity _initial;
    SecuritySessionId _sessionID;
    BOOL _revoked;
    BOOL _notified;
    dispatch_source_t _watch;
    NSMutableArray *_workspaceObservers;
    id _lockObserver;
}

- (instancetype)init { return nil; }
- (instancetype)initWithPhase:(PLANKMacGraphicalPhase)phase {
    if (phase != PLANKMacScopeDesktop && phase != PLANKMacScopeSignIn) return nil;
    self = [super init];
    if (!self) return nil;
    _revoked = YES;
    _initial.phase = phase;
    // Subscribe before sampling. Notifications can only revoke, never grant.
    // The distributed lock notification is defense-in-depth, not proof of an
    // unlocked session or a supported substitute for LoginWindow qualification.
    __weak typeof(self) weakSelf = self;
    _workspaceObservers = [NSMutableArray array];
    for (NSNotificationName name in @[NSWorkspaceSessionDidResignActiveNotification, NSWorkspaceWillSleepNotification]) {
        id observer = [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:name
            object:nil queue:nil usingBlock:^(NSNotification *notification) {
                (void)notification; [weakSelf revoke];
            }];
        [_workspaceObservers addObject:observer];
    }
    _lockObserver = [NSDistributedNotificationCenter.defaultCenter
        addObserverForName:@"com.apple.screenIsLocked" object:nil queue:nil
        usingBlock:^(NSNotification *notification) { (void)notification; [weakSelf revoke]; }];
    @synchronized(self) {
        if (!_notified && readGraphical(phase, &_initial.account, &_sessionID) &&
            SecRandomCopyBytes(kSecRandomDefault, sizeof(_initial.generation),
                               (uint8_t *)&_initial.generation) == errSecSuccess && _initial.generation) {
            _initial.active = true;
            _revoked = NO;
        }
    }
    _watch = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_watch, DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC, 25 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(_watch, ^{ (void)[weakSelf snapshot]; });
    dispatch_resume(_watch);
    return self;
}

- (PLANKMacGraphicalIdentity)snapshot {
    @synchronized(self) {
        PLANKMacAccountIdentity account = {0};
        SecuritySessionId sessionID = noSecuritySession;
        if (_revoked || !readGraphical(_initial.phase, &account, &sessionID) || sessionID != _sessionID ||
            account.uid != _initial.account.uid || memcmp(account.uuid, _initial.account.uuid, sizeof(account.uuid))) {
            _revoked = YES;
            return (PLANKMacGraphicalIdentity){0};
        }
        return _initial;
    }
}

- (void)revoke { @synchronized(self) { _notified = YES; _revoked = YES; } }

- (void)dealloc {
    if (_watch) dispatch_source_cancel(_watch);
    for (id observer in _workspaceObservers)
        [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:observer];
    if (_lockObserver) [NSDistributedNotificationCenter.defaultCenter removeObserver:_lockObserver];
}
@end
