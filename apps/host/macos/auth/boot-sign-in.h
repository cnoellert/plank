// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>
#import <SystemConfiguration/SystemConfiguration.h>
#include <pwd.h>
#include <stdint.h>

static inline BOOL PLANKMacScopeNumber(id value, uint32_t *result) {
    if (!value || CFGetTypeID((__bridge CFTypeRef)value) != CFNumberGetTypeID()) return NO;
    int64_t number;
    if (!CFNumberGetValue((__bridge CFNumberRef)value, kCFNumberSInt64Type, &number) ||
        number < 0 || number > UINT32_MAX || [value doubleValue] != (double)number) return NO;
    *result = (uint32_t)number;
    return YES;
}

// OS-owned console/session data only, never peer-supplied fields. Initial boot
// has an anonymous WindowServer session rather than the root/loginwindow console
// identity seen after logout. Missing console identity alone grants nothing.
static inline BOOL PLANKMacBootSignInRecord(NSDictionary *record, uint32_t audit, uint32_t windowServerUID) {
    uint32_t uid, securityID, auditID;
    return [record isKindOfClass:NSDictionary.class] && audit && audit != UINT32_MAX &&
        windowServerUID && windowServerUID != UINT32_MAX &&
        record[@"kCGSSessionOnConsoleKey"] == (__bridge id)kCFBooleanTrue &&
        record[@"kCGSessionLoginDoneKey"] == (__bridge id)kCFBooleanFalse &&
        [record[@"kCGSSessionUserNameKey"] isEqual:@"unknown"] &&
        PLANKMacScopeNumber(record[@"kCGSSessionUserIDKey"], &uid) && uid == windowServerUID &&
        PLANKMacScopeNumber(record[@"kCGSSessionAuditIDKey"], &auditID) && auditID == audit &&
        PLANKMacScopeNumber(record[@"kSCSecuritySessionID"], &securityID) && securityID == audit;
}

static inline BOOL PLANKMacBootSignInConsole(NSDictionary *console, uint32_t audit, uint32_t windowServerUID) {
    if (![console isKindOfClass:NSDictionary.class] || console[@"Name"] || console[@"UID"]) return NO;
    NSArray *sessions = console[@"SessionInfo"];
    if (![sessions isKindOfClass:NSArray.class] || !sessions.count || sessions.count > 32) return NO;
    NSDictionary *active = nil;
    for (id record in sessions) {
        if (![record isKindOfClass:NSDictionary.class]) return NO;
        if (record[@"kCGSSessionOnConsoleKey"] == (__bridge id)kCFBooleanTrue) {
            if (active) return NO;
            active = record;
        }
    }
    return PLANKMacBootSignInRecord(active, audit, windowServerUID);
}

static inline uint32_t PLANKMacWindowServerUID(void) {
    static uint32_t uid = UINT32_MAX;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        struct passwd entry, *found = NULL;
        char buffer[16384];
        if (!getpwnam_r("_windowserver", &entry, buffer, sizeof(buffer), &found) && found)
            uid = found->pw_uid;
    });
    return uid;
}

static inline BOOL PLANKMacBootSignInSession(uint32_t audit) {
    NSDictionary *console = CFBridgingRelease(SCDynamicStoreCopyValue(NULL, CFSTR("State:/Users/ConsoleUser")));
    return PLANKMacBootSignInConsole(console, audit, PLANKMacWindowServerUID());
}
