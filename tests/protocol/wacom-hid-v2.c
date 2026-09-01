#include <stdint.h>
#include <stdio.h>

#include "Limelight.h"
#include "plank.h"

int main(void) {
    if (PLANK_RAW_HID_WIRE_VERSION != 2U) {
        fprintf(stderr, "unexpected raw HID wire version: %u\n",
                (unsigned int)PLANK_RAW_HID_WIRE_VERSION);
        return 1;
    }
    if (PLANK_RAW_HID_SUSPEND != 13) {
        fprintf(stderr, "unexpected raw HID suspend message type: %d\n",
                PLANK_RAW_HID_SUSPEND);
        return 1;
    }
    if (LI_FF_RAW_HID_FOCUS_SUSPEND != UINT32_C(0x20)) {
        fprintf(stderr, "unexpected raw HID focus-suspend feature bit: 0x%x\n",
                LI_FF_RAW_HID_FOCUS_SUSPEND);
        return 1;
    }
    if (sizeof(PLANK_RAW_HID_WIRE_HEADER) != 20U) {
        fprintf(stderr, "raw HID wire header size changed: %zu\n",
                sizeof(PLANK_RAW_HID_WIRE_HEADER));
        return 1;
    }
    return 0;
}
