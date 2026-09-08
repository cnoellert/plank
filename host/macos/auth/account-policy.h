// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

typedef struct {
    uint32_t uid;
    uint8_t uuid[16];
} PLANKMacAccountIdentity;

typedef enum {
    PLANKMacScopeUnavailable, PLANKMacScopeSignIn, PLANKMacScopeDesktop
} PLANKMacGraphicalPhase;

// Supplied by the trusted session owner, never deserialized from a Client.
// Generation changes whenever graphical authority is revoked/replaced. Sign-in
// is a positively verified LoginWindow scope, NOT a missing desktop/account.
typedef struct {
    bool active;
    uint64_t generation;
    PLANKMacAccountIdentity account;
    PLANKMacGraphicalPhase phase;
} PLANKMacGraphicalIdentity;

static inline bool plank_macos_account_identity_valid(PLANKMacAccountIdentity account) {
    static const uint8_t empty[16] = {0};
    return account.uid != 0 && account.uid != UINT32_MAX &&
        memcmp(account.uuid, empty, sizeof(empty)) != 0;
}

static inline bool plank_macos_graphical_identity_valid(PLANKMacGraphicalIdentity scope) {
    if (!scope.active || !scope.generation) return false;
    if (scope.phase == PLANKMacScopeDesktop) return plank_macos_account_identity_valid(scope.account);
    static const uint8_t empty[16] = {0};
    return scope.phase == PLANKMacScopeSignIn && scope.account.uid == 0 &&
        memcmp(scope.account.uuid, empty, sizeof(empty)) == 0;
}

static inline bool plank_macos_same_graphical_scope(
        PLANKMacGraphicalIdentity before, PLANKMacGraphicalIdentity after) {
    return plank_macos_graphical_identity_valid(before) && plank_macos_graphical_identity_valid(after) &&
        before.generation == after.generation && before.phase == after.phase &&
        before.account.uid == after.account.uid &&
        memcmp(before.account.uuid, after.account.uuid, sizeof(before.account.uuid)) == 0;
}

// Verification grants only the positively observed scope, not an OS login or
// permission to follow into another scope. A desktop admits only its owner;
// LoginWindow admits verified non-root users. Never carry a token across phases.
static inline bool plank_macos_account_may_attach(
        PLANKMacAccountIdentity verified, PLANKMacGraphicalIdentity before,
        PLANKMacGraphicalIdentity after) {
    return plank_macos_account_identity_valid(verified) && plank_macos_same_graphical_scope(before, after) &&
        (after.phase == PLANKMacScopeSignIn ||
         (verified.uid == after.account.uid &&
          memcmp(verified.uuid, after.account.uuid, sizeof(verified.uuid)) == 0));
}
