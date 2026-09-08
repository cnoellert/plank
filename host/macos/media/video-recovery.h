// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stdbool.h>

// Mac capture-owner queue only. Distinguish needing a recovery picture from
// already having submitted one to the asynchronous encoder.
typedef struct {
    bool requested;
    bool encoding;
} PLANKMacVideoRecovery;

static inline bool PLANKMacVideoRecoveryBegin(PLANKMacVideoRecovery *state) {
    if (!state->requested || state->encoding) return false;
    state->encoding = true;
    return true;
}

static inline void PLANKMacVideoRecoverySent(PLANKMacVideoRecovery *state,
                                            bool key, bool accepted, bool evicted) {
    // Native DROPPED accepts the new frame and evicts an older queued frame.
    // An accepted key makes that older frame unnecessary. A delta does not.
    if (key && accepted) state->requested = false;
    else if (!accepted || evicted) state->requested = true;
}
