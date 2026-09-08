// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <math.h>

// Single HAL producer and single session-queue consumer. A full ring fails
// capture; it never overwrites unread audio or invents timestamps after a gap.
enum { PLANKTapSlots = 16, PLANKTapMaxFrames = 8192 };
typedef struct {
    uint32_t frames;
    uint64_t hostTime;
    float samples[PLANKTapMaxFrames * 2];
} PLANKTapBlock;
typedef struct {
    _Atomic uint32_t readIndex, writeIndex;
    _Atomic int failed;
    _Atomic bool stopped;
    PLANKTapBlock blocks[PLANKTapSlots];
} PLANKTapBuffer;

static inline void PLANKTapBufferInit(PLANKTapBuffer *buffer) {
    atomic_init(&buffer->readIndex, 0); atomic_init(&buffer->writeIndex, 0);
    atomic_init(&buffer->failed, 0); atomic_init(&buffer->stopped, false);
}
static inline bool PLANKTapPush(PLANKTapBuffer *buffer, const float *left,
                               const float *right, uint32_t frames, uint64_t hostTime) {
    if (atomic_load_explicit(&buffer->stopped, memory_order_acquire)) return false;
    uint32_t write = atomic_load_explicit(&buffer->writeIndex, memory_order_relaxed);
    uint32_t read = atomic_load_explicit(&buffer->readIndex, memory_order_acquire);
    int error = 0;
    if (!left || !frames || frames > PLANKTapMaxFrames || !hostTime) error = 1;
    else if ((uint32_t)(write - read) >= PLANKTapSlots) error = 2;
    if (error) { atomic_store(&buffer->failed, error); return false; }
    PLANKTapBlock *block = &buffer->blocks[write % PLANKTapSlots];
    block->frames = frames; block->hostTime = hostTime;
    for (uint32_t i = 0; i < frames; i++) {
        float l = left[right ? i : i * 2], r = right ? right[i] : left[i * 2 + 1];
        if (!isfinite(l) || !isfinite(r)) { atomic_store(&buffer->failed, 1); return false; }
        block->samples[i * 2] = l; block->samples[i * 2 + 1] = r;
    }
    atomic_store_explicit(&buffer->writeIndex, write + 1, memory_order_release);
    return true;
}
static inline PLANKTapBlock *PLANKTapPeek(PLANKTapBuffer *buffer) {
    uint32_t read = atomic_load_explicit(&buffer->readIndex, memory_order_relaxed);
    if (read == atomic_load_explicit(&buffer->writeIndex, memory_order_acquire)) return NULL;
    return &buffer->blocks[read % PLANKTapSlots];
}
static inline void PLANKTapPop(PLANKTapBuffer *buffer) {
    uint32_t read = atomic_load_explicit(&buffer->readIndex, memory_order_relaxed);
    atomic_store_explicit(&buffer->readIndex, read + 1, memory_order_release);
}
