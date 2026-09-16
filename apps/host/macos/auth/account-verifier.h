// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#import <Foundation/Foundation.h>
#include "account-policy.h"

typedef NS_ENUM(unsigned int, PLANKMacAuthenticationResult) {
    PLANKMacAuthenticationDenied,
    PLANKMacAuthenticationVerified,
    PLANKMacAuthenticationUnavailable
};

// Fixed, credential-free diagnostics across the private helper boundary.
// Never transmit directory error descriptions or account attributes in logs.
typedef NS_ENUM(unsigned int, PLANKMacAuthenticationStage) {
    PLANKMacAuthInput,
    PLANKMacAuthDirectory,
    PLANKMacAuthDirectoryRecord,
    PLANKMacAuthIdentity,
    PLANKMacAuthPassword,
    PLANKMacAuthIdentityRecheck,
    PLANKMacAuthComplete,
    PLANKMacAuthException
};

// Internal backend for a short-lived authentication process; not a network API.
// Password is mutable UTF-8, at most 4096 bytes, and is wiped on every return.
// Output is zeroed on failure. Caller must separately authorize desktop ownership.
// Framework-internal credential copies cannot be guaranteed wiped; use a
// short-lived helper with core dumps disabled, not a long-lived media process.
PLANKMacAuthenticationResult PLANKMacVerifyAccount(
    NSString *name, NSMutableData *password, PLANKMacAccountIdentity *output,
    PLANKMacAuthenticationStage *stage);
