#include <stdint.h>
#include <stdio.h>

#include "Limelight.h"
#include "Video.h"

static int check_round_trip(uint8_t current, uint8_t last) {
    NV_VIDEO_PACKET packet = {0};

    // Verify the setter does not consume the extension flag or reserved low bits.
    packet.multiFecFlags = 0xD0;
    packet.multiFecBlocks = 0x0B;
    setMultiFecBlockNumbers(&packet, current, last);

    if (getMultiFecCurrentBlockNumber(&packet) != current ||
            getMultiFecLastBlockNumber(&packet) != last ||
            (packet.multiFecFlags & 0xF0) != 0xD0 ||
            (packet.multiFecBlocks & 0x0F) != 0x0B) {
        fprintf(stderr, "FEC block index round trip failed for %u/%u\n", current, last);
        return 1;
    }

    return 0;
}

int main(void) {
    static const uint8_t indices[] = {0, 3, 4, 11, 15};

    for (unsigned int current = 0; current < sizeof(indices); current++) {
        for (unsigned int last = 0; last < sizeof(indices); last++) {
            if (check_round_trip(indices[current], indices[last]) != 0) {
                return 1;
            }
        }
    }

    // A legacy packet has zero high bits and must retain its original decoding.
    NV_VIDEO_PACKET legacy = {0};
    legacy.multiFecFlags = 0x10;
    legacy.multiFecBlocks = (3u << 4) | (3u << 6);
    if (getMultiFecCurrentBlockNumber(&legacy) != 3 ||
            getMultiFecLastBlockNumber(&legacy) != 3) {
        fprintf(stderr, "legacy FEC block index decoding failed\n");
        return 1;
    }

    // Reconstructed shards must replace all negotiated metadata rather than
    // preserving bytes that were generated before the final wire header.
    NV_VIDEO_PACKET recovered = {0};
    recovered.multiFecFlags = 0xEF;
    recovered.multiFecBlocks = 0xFF;
    recovered.multiFecFlags = 0x10;
    recovered.multiFecBlocks = 0;
    setMultiFecBlockNumbers(&recovered, 11, 15);
    if (recovered.multiFecFlags != 0x1E || recovered.multiFecBlocks != 0xF0 ||
            getMultiFecCurrentBlockNumber(&recovered) != 11 ||
            getMultiFecLastBlockNumber(&recovered) != 15) {
        fprintf(stderr, "recovered FEC metadata normalization failed\n");
        return 1;
    }

    return 0;
}
