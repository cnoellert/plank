/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "plank_clipboard_wire.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

int main(void) {
    uint8_t packet[PLANK_CLIPBOARD_HEADER_BYTES + PLANK_CLIPBOARD_INPUT_BYTES];
    PlankClipboardChunk chunk;
    memset(packet, 'x', sizeof(packet));
    uint32_t offset = 0;
    unsigned frames = 0;
    while (offset < PLANK_CLIPBOARD_TEXT_LIMIT) {
        uint32_t count = PLANK_CLIPBOARD_TEXT_LIMIT - offset;
        if (count > PLANK_CLIPBOARD_INPUT_BYTES) count = PLANK_CLIPBOARD_INPUT_BYTES;
        plank_clipboard_header(packet, 17, PLANK_CLIPBOARD_TEXT_LIMIT, offset, count);
        assert(plank_clipboard_decode(packet, 32 + count, PLANK_CLIPBOARD_INPUT_BYTES, &chunk));
        assert(chunk.generation == 17 && chunk.offset == offset && chunk.size == count);
        assert(!plank_clipboard_decode(packet, 31 + count, PLANK_CLIPBOARD_INPUT_BYTES, &chunk));
        offset += count; ++frames;
    }
    assert(frames == 65);
    plank_clipboard_header(packet, 1, PLANK_CLIPBOARD_TEXT_LIMIT + 1, 0, 1);
    assert(!plank_clipboard_decode(packet, 33, PLANK_CLIPBOARD_INPUT_BYTES, &chunk));
    plank_clipboard_header(packet, 1, 1, 0, 1);
    assert(plank_clipboard_decode(packet, 33, PLANK_CLIPBOARD_INPUT_BYTES, &chunk));
    for (unsigned index = 0; index < 32; ++index) {
        uint8_t saved = packet[index]; packet[index] ^= 0x80;
        if (index < 12 || index >= 20)
            assert(!plank_clipboard_decode(packet, 33, PLANK_CLIPBOARD_INPUT_BYTES, &chunk));
        packet[index] = saved;
    }
    uint8_t *text = malloc(PLANK_CLIPBOARD_TEXT_LIMIT + 1); assert(text);
    memset(text, 'a', PLANK_CLIPBOARD_TEXT_LIMIT + 1);
    assert(plank_clipboard_valid_text(text, PLANK_CLIPBOARD_TEXT_LIMIT));
    assert(!plank_clipboard_valid_text(text, PLANK_CLIPBOARD_TEXT_LIMIT + 1));
    text[100] = 0;
    assert(!plank_clipboard_valid_text(text, PLANK_CLIPBOARD_TEXT_LIMIT));
    free(text);
    const uint8_t valid[] = {'a', '\n', 0xf0, 0x9f, 0x94, 0xa5};
    assert(plank_clipboard_valid_text(valid, sizeof(valid)));
    const uint8_t invalid[][4] = {{0xc0, 0xaf}, {0xed, 0xa0, 0x80}, {0xf4, 0x90, 0x80, 0x80}, {'a', 0, 'b'}};
    for (unsigned i = 0; i < 4; ++i) assert(!plank_clipboard_valid_text(invalid[i], 4));
    assert(!plank_clipboard_valid_text(NULL, 0));
    puts("Clipboard wire: bounds, framing, Unicode and 65-chunk maximum passed");
}
