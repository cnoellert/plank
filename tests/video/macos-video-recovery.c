// SPDX-License-Identifier: GPL-3.0-or-later
#include "video-recovery.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    PLANKMacVideoRecovery state = {.requested = true};
    assert(PLANKMacVideoRecoveryBegin(&state));
    // Two additional in-flight frames and repeated receiver requests must not
    // turn one recovery request into three forced keyframes.
    assert(!PLANKMacVideoRecoveryBegin(&state));
    state.requested = true;
    assert(!PLANKMacVideoRecoveryBegin(&state));
    // Accepted recovery key replaces an older queued frame: recovery succeeds.
    PLANKMacVideoRecoverySent(&state, true, true, true);
    assert(!state.requested && state.encoding);
    state.encoding = false;
    assert(!PLANKMacVideoRecoveryBegin(&state));
    // A later delta evicting any reference requires fresh recovery.
    PLANKMacVideoRecoverySent(&state, false, true, true);
    assert(state.requested);
    assert(PLANKMacVideoRecoveryBegin(&state));
    // Missing/failed output cannot consume the request permanently.
    state.encoding = false;
    assert(state.requested && PLANKMacVideoRecoveryBegin(&state));
    PLANKMacVideoRecoverySent(&state, true, false, false);
    state.encoding = false;
    assert(state.requested && PLANKMacVideoRecoveryBegin(&state));
    // Encoder ignores force and gives a delta: still need a genuine key.
    PLANKMacVideoRecoverySent(&state, false, true, false);
    state.encoding = false;
    assert(state.requested && PLANKMacVideoRecoveryBegin(&state));
    PLANKMacVideoRecoverySent(&state, true, true, false);
    state.encoding = false;
    assert(!state.requested);
    // A new loss request after completed recovery must not be suppressed.
    state.requested = true;
    assert(PLANKMacVideoRecoveryBegin(&state));
    // Natural key ahead of the forced callback also satisfies recovery; keep
    // the submission guard until the outstanding forced encode completes.
    PLANKMacVideoRecoverySent(&state, true, true, false);
    state.requested = true;
    assert(!PLANKMacVideoRecoveryBegin(&state));
    PLANKMacVideoRecoverySent(&state, true, true, true);
    state.encoding = false;
    assert(!state.requested && !PLANKMacVideoRecoveryBegin(&state));
    PLANKMacVideoRecoverySent(&state, false, true, false);
    assert(!state.requested);
    puts("macos_video_recovery_pass=1 async_coalescing=1 key_eviction=1 retry=1");
}
