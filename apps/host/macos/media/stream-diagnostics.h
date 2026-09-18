// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stdint.h>
#include <string.h>

// Native last-error text can contain peer-supplied close reasons/addresses.
// Return only fixed labels. Never log the original buffer, even on an unknown
// error. Exact queue matches precede broader lane classifications.
static inline const char *PLANKMacTransportFailureClass(const char *error) {
    if (!error || !*error) return "none";
    if (!strcmp(error, "native input receiver failed: native input receive queue exhausted"))
        return "input-receive-queue-exhausted";
    if (!strcmp(error, "native data receiver failed: native reliable data receive queue exhausted"))
        return "data-receive-queue-exhausted";
    static const struct { const char *prefix, *label; } lanes[] = {
        {"native input receiver failed:", "input-receiver-failed"},
        {"native data receiver failed:", "data-receiver-failed"},
        {"native data sender failed:", "data-sender-failed"},
        {"native video sender failed:", "video-sender-failed"},
        {"native audio sender failed:", "audio-sender-failed"},
        {"native stats sampler failed:", "stats-sampler-failed"},
        {"native input receiver ended while the native endpoint was active", "input-receiver-ended"},
        {"native data receiver ended while the native endpoint was active", "data-receiver-ended"},
    };
    for (unsigned i = 0; i < sizeof(lanes) / sizeof(lanes[0]); ++i)
        if (!strncmp(error, lanes[i].prefix, strlen(lanes[i].prefix))) return lanes[i].label;
    return "other";
}

// Owner-queue-only bounded aggregates, emitted once at teardown. No per-event
// log, coordinates, key/clipboard contents or input scheduling changes.
typedef struct {
    uint64_t count, slow, maximum;
} PLANKMacInputTiming;
static inline void PLANKMacInputTimingNote(PLANKMacInputTiming *timing, uint64_t start, uint64_t end) {
    if (end < start) return;
    uint64_t elapsed = end - start;
    ++timing->count;
    if (elapsed >= 20000000) ++timing->slow; // 20 ms, not an input timeout
    if (elapsed > timing->maximum) timing->maximum = elapsed;
}
