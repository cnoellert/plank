#include <stdint.h>
#include <stdio.h>

#include "Limelight.h"
#include "Video.h"

static int expect_near(const char* name, float actual, float expected) {
    float difference = actual - expected;

    if (difference < 0.0f) {
        difference = -difference;
    }

    if (difference > 0.0001f) {
        fprintf(stderr, "%s: expected %.4f, got %.4f\n", name, expected, actual);
        return 1;
    }

    return 0;
}

int main(void) {
    int result = 0;

    result |= expect_near("no sample", getVideoDataPacketLossPercentage(0, 0), -1.0f);
    result |= expect_near("zero loss", getVideoDataPacketLossPercentage(10000, 0), 0.0f);
    result |= expect_near("five percent", getVideoDataPacketLossPercentage(10000, 500), 5.0f);
    result |= expect_near("ten percent", getVideoDataPacketLossPercentage(10000, 1000), 10.0f);
    result |= expect_near("clamped loss", getVideoDataPacketLossPercentage(100, 101), 100.0f);
    result |= expect_near("fractional loss", getVideoDataPacketLossPercentage(160000, 849),
                          0.530625f);

    return result;
}
