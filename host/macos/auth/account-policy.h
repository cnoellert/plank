// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

typedef struct {
    uint32_t uid;
    uint8_t uuid[16];
} PLANKMacAccountIdentity;

// Supplied by the trusted session owner, never deserialized from a Client.
// Generation must change whenever session authority is revoked/replaced.
typedef struct {
    bool active;
    uint64_t generation;
    PLANKMacAccountIdentity account;
} PLANKMacDesktopIdentity;

static inline bool plank_macos_account_identity_valid(PLANKMacAccountIdentity account) {
    static const uint8_t empty[16] = {0};
    return account.uid != 0 && account.uid != UINT32_MAX &&
        memcmp(account.uuid, empty, sizeof(empty)) != 0;
}

// Password success alone never grants capture/input or logs into macOS.
// Compare the trusted desktop identity before and after account verification.
static inline bool plank_macos_account_may_attach(
        PLANKMacAccountIdentity verified, PLANKMacDesktopIdentity before,
        PLANKMacDesktopIdentity after) {
    return plank_macos_account_identity_valid(verified) &&
        before.active && after.active && before.generation != 0 &&
        before.generation == after.generation &&
        verified.uid == before.account.uid && verified.uid == after.account.uid &&
        memcmp(verified.uuid, before.account.uuid, sizeof(verified.uuid)) == 0 &&
        memcmp(verified.uuid, after.account.uuid, sizeof(verified.uuid)) == 0;
}
