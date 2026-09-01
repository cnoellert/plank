#include <stdint.h>
#include <stdio.h>

#include "Limelight.h"
#include "plank.h"

int main(void) {
    if (PLANK_CURSOR_WIRE_MAGIC != UINT32_C(0x504c4352) ||
            PLANK_CURSOR_WIRE_VERSION != 1U ||
            PLANK_CURSOR_PIXEL_FORMAT_ARGB8888 != 1U) {
        fprintf(stderr, "local cursor wire identity mismatch\n");
        return 1;
    }
    if (sizeof(PLANK_CURSOR_WIRE_HEADER) != 48U) {
        fprintf(stderr, "local cursor header size mismatch: %zu\n",
                sizeof(PLANK_CURSOR_WIRE_HEADER));
        return 1;
    }
    if (PLANK_CURSOR_POSITION_WIRE_MAGIC != UINT32_C(0x504c4350) ||
            PLANK_CURSOR_POSITION_WIRE_VERSION != 1U ||
            sizeof(PLANK_CURSOR_POSITION_WIRE_MESSAGE) != 32U) {
        fprintf(stderr, "local cursor position wire identity mismatch\n");
        return 1;
    }
    if (PLANK_CURSOR_MAX_DIMENSION != 512U ||
            PLANK_CURSOR_MAX_IMAGE_SIZE != 1048576U ||
            PLANK_CURSOR_MAX_CHUNK_SIZE != 49152U) {
        fprintf(stderr, "local cursor bounds mismatch\n");
        return 1;
    }
    if (LI_FF_LOCAL_CURSOR != UINT32_C(0x40) ||
            PLANK_CURSOR_CLIENT_FEATURE_FLAG != UINT32_C(0x10)) {
        fprintf(stderr, "local cursor feature flags mismatch\n");
        return 1;
    }
    if (sizeof(PLANK_CURSOR_WIRE_HEADER) + PLANK_CURSOR_MAX_CHUNK_SIZE > UINT16_MAX) {
        fprintf(stderr, "local cursor chunk exceeds control payload length\n");
        return 1;
    }
    return 0;
}
