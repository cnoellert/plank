// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

// Temporary bounded stutter diagnostic. Numeric metadata only; no frame bytes.
// One owner queue reserves/updates records. Dump only after encoder drain so
// there is no per-frame formatting or disk I/O during measured playback.
#define PLANK_FRAME_TIMING_CAPACITY 8192
#define PLANK_FRAME_TIMING_DURATION_NS UINT64_C(120000000000)
typedef struct {
    uint64_t capture_ns, submitted_ns, completed_ns, handled_ns, sent_ns;
    uint64_t pts_ns, number, bytes;
    unsigned in_flight, forced, key, stage;
    int32_t result;
} PLANKFrameTimingRecord;
typedef struct {
    uint64_t origin_ns, wall_ns;
    size_t count;
    PLANKFrameTimingRecord records[PLANK_FRAME_TIMING_CAPACITY];
} PLANKFrameTiming;

static inline PLANKFrameTimingRecord *PLANKFrameTimingAppend(PLANKFrameTiming *trace,
                                                            uint64_t now) {
    if (!trace || now < trace->origin_ns ||
        now - trace->origin_ns >= PLANK_FRAME_TIMING_DURATION_NS ||
        trace->count == PLANK_FRAME_TIMING_CAPACITY) return NULL;
    PLANKFrameTimingRecord *record = &trace->records[trace->count++];
    record->capture_ns = now;
    return record;
}
static inline void PLANKFrameTimingDump(const PLANKFrameTiming *trace, FILE *output) {
    if (!trace || !output) return;
    fprintf(output, "PLANK frame-timing begin wall-unix-ns=%llu mono-ns=%llu count=%zu\n",
            (unsigned long long)trace->wall_ns, (unsigned long long)trace->origin_ns, trace->count);
    fprintf(output, "PLANK frame-timing columns=index,capture-ns,submit-ns,complete-ns,handled-ns,sent-ns,pts-ns,frame-number,encoded-bytes,in-flight,forced,key,stage,result\n");
    for (size_t i = 0; i < trace->count; ++i) {
        const PLANKFrameTimingRecord *r = &trace->records[i];
        fprintf(output, "PLANK frame-timing %zu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%llu,%u,%u,%u,%u,%d\n",
                i, (unsigned long long)r->capture_ns, (unsigned long long)r->submitted_ns,
                (unsigned long long)r->completed_ns, (unsigned long long)r->handled_ns,
                (unsigned long long)r->sent_ns, (unsigned long long)r->pts_ns,
                (unsigned long long)r->number, (unsigned long long)r->bytes,
                r->in_flight, r->forced, r->key, r->stage, r->result);
    }
    fprintf(output, "PLANK frame-timing end\n");
}
