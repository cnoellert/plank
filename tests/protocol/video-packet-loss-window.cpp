#include <cstdio>

#include "app/streaming/videopacketlosswindow.h"

static int expectPeak(const char* name, float actual, float expected)
{
    if (actual != expected) {
        std::fprintf(stderr, "%s: expected %.1f, got %.1f\n",
                     name, expected, actual);
        return 1;
    }

    return 0;
}

int main()
{
    VideoPacketLossPeakWindow window;
    int result = 0;

    result |= expectPeak("initial peak", window.addSample(1000, 1.9f), 1.9f);
    result |= expectPeak("peak retained", window.addSample(10999, 0.0f), 1.9f);
    result |= expectPeak("peak expired", window.addSample(11000, 0.0f), 0.0f);
    result |= expectPeak("new peak", window.addSample(12000, 0.8f), 0.8f);
    result |= expectPeak("higher peak", window.addSample(13000, 4.2f), 4.2f);
    result |= expectPeak("lower sample", window.addSample(21000, 0.4f), 4.2f);
    result |= expectPeak("individual expiry", window.addSample(23000, 0.0f), 0.4f);

    return result;
}
