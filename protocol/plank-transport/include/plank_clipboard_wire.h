/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef PLANK_CLIPBOARD_WIRE_H
#define PLANK_CLIPBOARD_WIRE_H
#include <stddef.h>
#include <stdint.h>

/* Clipboard v1, independent of AppKit, Qt, X11 and packed C struct alignment. */
#define PLANK_CLIPBOARD_TEXT_LIMIT (512u * 1024u)
#define PLANK_CLIPBOARD_HEADER_BYTES 32u
#define PLANK_CLIPBOARD_INPUT_BYTES 8160u
#define PLANK_CLIPBOARD_EVENT_BYTES (48u * 1024u)
#define PLANK_CLIPBOARD_FIRST 1u
#define PLANK_CLIPBOARD_LAST 2u

typedef struct PlankClipboardChunk {
    uint64_t generation;
    uint32_t total, offset, size, flags;
    const uint8_t *bytes;
} PlankClipboardChunk;

static inline uint64_t plank_clipboard_read_le(const uint8_t *p, unsigned n) {
    uint64_t result = 0;
    for (unsigned i = 0; i < n; ++i) result |= (uint64_t)p[i] << (8 * i);
    return result;
}
static inline void plank_clipboard_write_le(uint8_t *p, uint64_t value, unsigned n) {
    for (unsigned i = 0; i < n; ++i) p[i] = (uint8_t)(value >> (8 * i));
}

/* Validate before allocation, generation suppression or reading chunk bytes. */
static inline int plank_clipboard_decode(const uint8_t *p, size_t size,
                                        uint32_t limit, PlankClipboardChunk *out) {
    if (!p || !out || size < PLANK_CLIPBOARD_HEADER_BYTES) return 0;
    PlankClipboardChunk c;
    c.flags = (uint32_t)plank_clipboard_read_le(p + 8, 4);
    c.generation = plank_clipboard_read_le(p + 12, 8);
    c.total = (uint32_t)plank_clipboard_read_le(p + 20, 4);
    c.offset = (uint32_t)plank_clipboard_read_le(p + 24, 4);
    c.size = (uint32_t)plank_clipboard_read_le(p + 28, 4);
    c.bytes = p + PLANK_CLIPBOARD_HEADER_BYTES;
    if (plank_clipboard_read_le(p, 4) != 0x504c4342u ||
        plank_clipboard_read_le(p + 4, 2) != 1 || plank_clipboard_read_le(p + 6, 2) ||
        !c.generation || (c.flags & ~3u) || !c.total || c.total > PLANK_CLIPBOARD_TEXT_LIMIT ||
        !c.size || c.size > limit || c.offset > c.total || c.size > c.total - c.offset ||
        size != PLANK_CLIPBOARD_HEADER_BYTES + c.size ||
        ((c.flags & PLANK_CLIPBOARD_FIRST) && c.offset != 0) ||
        (!!(c.flags & PLANK_CLIPBOARD_LAST) != (c.offset + c.size == c.total))) return 0;
    *out = c;
    return 1;
}

static inline void plank_clipboard_header(uint8_t *p, uint64_t generation,
                                         uint32_t total, uint32_t offset, uint32_t size) {
    plank_clipboard_write_le(p, 0x504c4342u, 4);
    plank_clipboard_write_le(p + 4, 1, 2);
    plank_clipboard_write_le(p + 6, 0, 2);
    plank_clipboard_write_le(p + 8, (offset == 0 ? PLANK_CLIPBOARD_FIRST : 0) |
        (offset + size == total ? PLANK_CLIPBOARD_LAST : 0), 4);
    plank_clipboard_write_le(p + 12, generation, 8);
    plank_clipboard_write_le(p + 20, total, 4);
    plank_clipboard_write_le(p + 24, offset, 4);
    plank_clipboard_write_le(p + 28, size, 4);
}

/* Scalar-valid UTF-8, with no NUL or silent conversion/truncation. */
static inline int plank_clipboard_valid_text(const uint8_t *p, size_t size) {
    if (!p || !size || size > PLANK_CLIPBOARD_TEXT_LIMIT) return 0;
    for (size_t i = 0; i < size;) {
        uint8_t c = p[i++];
        if (!c) return 0;
        if (c < 0x80) continue;
        unsigned extra = c >= 0xc2 && c <= 0xdf ? 1 :
                         c >= 0xe0 && c <= 0xef ? 2 :
                         c >= 0xf0 && c <= 0xf4 ? 3 : 0;
        if (!extra || extra > size - i) return 0;
        if ((c == 0xe0 && p[i] < 0xa0) || (c == 0xed && p[i] > 0x9f) ||
            (c == 0xf0 && p[i] < 0x90) || (c == 0xf4 && p[i] > 0x8f)) return 0;
        for (unsigned n = 0; n < extra; ++n) if ((p[i++] & 0xc0) != 0x80) return 0;
    }
    return 1;
}
#endif
