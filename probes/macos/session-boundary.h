// SPDX-License-Identifier: GPL-3.0-or-later
// Probe-only session identity. This is not remote-account authorization.
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <unistd.h>
#import <Security/AuthSession.h>

typedef NS_ENUM(unsigned int, PLANKSessionPhase) {
    PLANKSessionUnavailable, PLANKSessionLoginWindow, PLANKSessionDesktop
};
typedef struct {
    PLANKSessionPhase phase;
    uint32_t user;
    uint32_t securitySession;
} PLANKGraphicalSession;

static inline BOOL PLANKSessionNumber(NSDictionary *dictionary, CFStringRef key, uint32_t *output) {
    id value = dictionary[(__bridge NSString *)key];
    if (!value || CFGetTypeID((__bridge CFTypeRef)value) != CFNumberGetTypeID()) return NO;
    int64_t number = 0;
    if (!CFNumberGetValue((__bridge CFNumberRef)value, kCFNumberSInt64Type, &number) ||
        number < 0 || number > UINT32_MAX) return NO;
    *output = (uint32_t)number;
    return YES;
}

static inline PLANKGraphicalSession PLANKReadGraphicalSession(void) {
    PLANKGraphicalSession state = {PLANKSessionUnavailable, 0, 0};
    SecuritySessionId identity = noSecuritySession;
    SessionAttributeBits attributes = 0;
    if (SessionGetInfo(callerSecuritySession, &identity, &attributes) != errSecSuccess ||
        identity == noSecuritySession || !(attributes & sessionHasGraphicAccess)) return state;
    state.securitySession = identity;
    NSDictionary *session = CFBridgingRelease(CGSessionCopyCurrentDictionary());
    if (!session || session[(__bridge NSString *)kCGSessionOnConsoleKey] != (__bridge id)kCFBooleanTrue ||
        !PLANKSessionNumber(session, kCGSessionUserIDKey, &state.user)) return state;
    id done = session[(__bridge NSString *)kCGSessionLoginDoneKey];
    uid_t consoleUser = (uid_t)-1;
    NSString *name = CFBridgingRelease(SCDynamicStoreCopyConsoleUser(NULL, &consoleUser, NULL));
    // NULL can mean no logged-in user OR a lookup error. Never infer authority
    // from that ambiguity. LoginWindow must positively identify itself.
    if (!name) return state;
    if (done == (__bridge id)kCFBooleanTrue && state.user == geteuid() &&
        state.user != 0 && consoleUser == state.user) state.phase = PLANKSessionDesktop;
    else if (done == (__bridge id)kCFBooleanFalse && geteuid() == 0 &&
        state.user == 0 && consoleUser == 0 && [name isEqualToString:@"loginwindow"])
        state.phase = PLANKSessionLoginWindow;
    return state;
}

static inline BOOL PLANKSessionMatches(PLANKGraphicalSession initial, PLANKGraphicalSession current) {
    return initial.phase != PLANKSessionUnavailable && initial.phase == current.phase &&
        initial.user == current.user && initial.securitySession == current.securitySession;
}

static inline const char *PLANKSessionName(PLANKSessionPhase phase) {
    switch (phase) {
        case PLANKSessionLoginWindow: return "sign-in";
        case PLANKSessionDesktop: return "desktop";
        default: return "unavailable";
    }
}
