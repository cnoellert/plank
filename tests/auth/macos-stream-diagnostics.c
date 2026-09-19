// SPDX-License-Identifier: GPL-3.0-or-later
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <stdio.h>
#include "stream-diagnostics.h"
int main(void) {
    assert(!strcmp(PLANKMacTransportFailureClass(NULL), "none"));
    assert(!strcmp(PLANKMacTransportFailureClass(""), "none"));
    assert(!strcmp(PLANKMacTransportFailureClass("native input receiver failed: native input receive queue exhausted"),
        "input-receive-queue-exhausted"));
    assert(!strcmp(PLANKMacTransportFailureClass("native data receiver failed: native reliable data receive queue exhausted"),
        "data-receive-queue-exhausted"));
    // Untrusted suffixes never appear in the result or impersonate queue failures.
    assert(!strcmp(PLANKMacTransportFailureClass("native input receiver failed: peer closed: native input receive queue exhausted"),
        "input-receiver-failed"));
    assert(!strcmp(PLANKMacTransportFailureClass("native data sender failed: remote-private-text"), "data-sender-failed"));
    assert(!strcmp(PLANKMacTransportFailureClass("native video sender failed: remote-private-text"), "video-sender-failed"));
    assert(!strcmp(PLANKMacTransportFailureClass("native audio sender failed: remote-private-text"), "audio-sender-failed"));
    assert(!strcmp(PLANKMacTransportFailureClass("native stats sampler failed: remote-private-text"), "stats-sampler-failed"));
    assert(!strcmp(PLANKMacTransportFailureClass("native data receiver failed: remote-private-text"), "data-receiver-failed"));
    assert(!strcmp(PLANKMacTransportFailureClass("native input receiver ended while the native endpoint was active"), "input-receiver-ended"));
    assert(!strcmp(PLANKMacTransportFailureClass("native data receiver ended while the native endpoint was active"), "data-receiver-ended"));
    assert(!strcmp(PLANKMacTransportFailureClass("unrecognized-private-text"), "other"));
    PLANKMacInputTiming timing = {0};
    PLANKMacInputTimingNote(&timing, 100, 99);
    assert(!timing.count);
    PLANKMacInputTimingNote(&timing, 100, 101);
    PLANKMacInputTimingNote(&timing, 100, 20000100);
    PLANKMacInputTimingNote(&timing, 100, 2000000100);
    assert(timing.count == 3 && timing.slow == 2 && timing.maximum == 2000000000);
    puts("macos_stream_diagnostics=pass fixed_labels=1 timing=1");
}
