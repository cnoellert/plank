// Actual common-c input worker, with an in-memory native sender only.
// No host, socket, input device, desktop or upstream application version.
#include "Limelight-internal.h"
#include "plank_transport_input.h"
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "line %d failed\n", __LINE__); exit(1); } } while (0)
static struct { uint8_t type; size_t size; uint8_t payload[32]; } records[16];
static atomic_uint count;
static atomic_bool holdSender, senderBlocked;
static int sendNative(void* context, uint8_t type, const uint8_t* data, size_t size) {
    (void)context;
    if (atomic_load(&holdSender)) {
        atomic_store(&senderBlocked, true);
        while (atomic_load(&holdSender)) PltSleepMs(1);
    }
    unsigned index = atomic_load(&count);
    CHECK(index < 16 && size <= 32);
    records[index].type = type; records[index].size = size;
    memcpy(records[index].payload, data, size);
    atomic_store(&count, index + 1);
    return 0;
}
static void waitFor(unsigned total) {
    for (unsigned i = 0; atomic_load(&count) < total && i < 200; ++i) PltSleepMs(5);
    if (atomic_load(&count) != total) fprintf(stderr, "expected %u events, received %u\n", total, atomic_load(&count));
    CHECK(atomic_load(&count) == total);
}
int main(void) {
    CHECK(initializePlatform() == 0);
    LiSetPlankNativeInputSender(sendNative, NULL);
    CHECK(initializeInputStream() == 0 && startInputStream() == 0);
    CHECK(LiSendMousePositionEvent(123, 456, 1920, 1080) == 0); waitFor(1);
    CHECK(records[0].type == PLANK_TRANSPORT_INPUT_ABSOLUTE_MOUSE && records[0].size == 8);
    CHECK(plank_transport_input_read_u16(records[0].payload) == 123);
    CHECK(plank_transport_input_read_u16(records[0].payload + 2) == 456);
    CHECK(plank_transport_input_read_u16(records[0].payload + 4) == 1919);
    CHECK(plank_transport_input_read_u16(records[0].payload + 6) == 1079);
    CHECK(LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT) == 0); waitFor(2);
    CHECK(LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT) == 0); waitFor(3);
    CHECK(records[1].type == PLANK_TRANSPORT_INPUT_MOUSE_BUTTON && records[1].payload[1] == 1);
    CHECK(records[2].type == PLANK_TRANSPORT_INPUT_MOUSE_BUTTON && records[2].payload[1] == 0);
    CHECK(LiSendKeyboardEvent2(0x41, KEY_ACTION_DOWN, MODIFIER_CTRL, 0) == 0); waitFor(4);
    CHECK(LiSendKeyboardEvent2(0x41, KEY_ACTION_UP, 0, 0) == 0); waitFor(5);
    CHECK(records[3].type == PLANK_TRANSPORT_INPUT_KEYBOARD && records[3].payload[2] == 1);
    CHECK(records[3].payload[3] == MODIFIER_CTRL && records[4].payload[2] == 0);
    CHECK(LiSendHighResScrollEvent(30) == 0); waitFor(6);
    CHECK(LiSendHighResHScrollEvent(-30) == 0); waitFor(7);
    CHECK(records[5].type == PLANK_TRANSPORT_INPUT_VERTICAL_SCROLL);
    CHECK(plank_transport_input_read_u16(records[5].payload) == 30);
    CHECK(records[6].type == PLANK_TRANSPORT_INPUT_HORIZONTAL_SCROLL);
    CHECK((int16_t)plank_transport_input_read_u16(records[6].payload) == -30);

    // Hold the real sender while a complete drag queues. Motion may coalesce
    // with adjacent motion, but must never overwrite a position across a
    // press/release boundary. No sleeps between producer events hide the race.
    atomic_store(&holdSender, true);
    CHECK(LiSendKeyboardEvent2(0x41, KEY_ACTION_UP, 0, 0) == 0);
    for (unsigned i = 0; !atomic_load(&senderBlocked) && i < 200; ++i) PltSleepMs(5);
    CHECK(atomic_load(&senderBlocked));
    CHECK(LiSendMousePositionEvent(50, 50, 1920, 1080) == 0);
    CHECK(LiSendMousePositionEvent(100, 100, 1920, 1080) == 0);
    CHECK(LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT) == 0);
    CHECK(LiSendMousePositionEvent(300, 150, 1920, 1080) == 0);
    CHECK(LiSendMousePositionEvent(400, 200, 1920, 1080) == 0);
    CHECK(LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT) == 0);
    CHECK(LiSendMousePositionEvent(800, 300, 1920, 1080) == 0);
    atomic_store(&holdSender, false);
    waitFor(13);
    CHECK(records[8].type == PLANK_TRANSPORT_INPUT_ABSOLUTE_MOUSE);
    CHECK(plank_transport_input_read_u16(records[8].payload) == 100);
    CHECK(plank_transport_input_read_u16(records[8].payload + 2) == 100);
    CHECK(records[9].type == PLANK_TRANSPORT_INPUT_MOUSE_BUTTON && records[9].payload[1] == 1);
    CHECK(records[10].type == PLANK_TRANSPORT_INPUT_ABSOLUTE_MOUSE);
    CHECK(plank_transport_input_read_u16(records[10].payload) == 400);
    CHECK(plank_transport_input_read_u16(records[10].payload + 2) == 200);
    CHECK(records[11].type == PLANK_TRANSPORT_INPUT_MOUSE_BUTTON && records[11].payload[1] == 0);
    CHECK(records[12].type == PLANK_TRANSPORT_INPUT_ABSOLUTE_MOUSE);
    CHECK(plank_transport_input_read_u16(records[12].payload) == 800);
    CHECK(stopInputStream() == 0); destroyInputStream(); cleanupPlatform();
    puts("native_input_wire=pass absolute_geometry=1 buttons=1 modifiers=1 scrolling=1 queued_drag_order=1 appversion_required=0");
}
