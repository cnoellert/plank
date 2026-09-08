// SPDX-License-Identifier: GPL-3.0-or-later
#include "frame-timing.h"
#include <assert.h>
#include <string.h>
int main(void) {
    PLANKFrameTiming *trace = calloc(1, sizeof(*trace));
    assert(trace && sizeof(*trace) < 1024 * 1024);
    trace->origin_ns = 100; trace->wall_ns = 200;
    assert(!PLANKFrameTimingAppend(NULL, 100));
    assert(!PLANKFrameTimingAppend(trace, 99));
    PLANKFrameTimingRecord *first = PLANKFrameTimingAppend(trace, 100);
    assert(first && first->capture_ns == 100 && first->stage == 0);
    first->number = 42; first->stage = 3; first->key = 1;
    // Later reservations cannot invalidate pointers retained by VT callbacks.
    for (size_t i = 1; i < PLANK_FRAME_TIMING_CAPACITY; ++i)
        assert(PLANKFrameTimingAppend(trace, 100 + i));
    assert(!PLANKFrameTimingAppend(trace, 9000));
    assert(first == &trace->records[0] && first->number == 42);
    trace->count = 1;
    assert(!PLANKFrameTimingAppend(trace, 100 + PLANK_FRAME_TIMING_DURATION_NS));
    FILE *out = tmpfile(); assert(out);
    PLANKFrameTimingDump(trace, out);
    rewind(out); char data[2048] = {0};
    assert(fread(data, 1, sizeof(data) - 1, out) > 0);
    assert(strstr(data, "wall-unix-ns=200 mono-ns=100 count=1"));
    assert(strstr(data, "PLANK frame-timing 0,100,0,0,0,0,0,42,0,0,0,1,3,0"));
    assert(strstr(data, "PLANK frame-timing end"));
    fclose(out); free(trace);
    puts("macos_frame_timing_pass=1 capacity=8192 duration_seconds=120");
}
