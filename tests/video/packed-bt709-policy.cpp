#include "streaming/video/packedbt709.h"
#include <cstdlib>

int main()
{
    DECODER_PARAMETERS p{};
    p.captureSource = DecoderCaptureSource::ScreenCaptureKit;
    p.encoderBackend = DecoderEncoderBackend::VideoToolbox;
    p.videoFormat = VIDEO_FORMAT_H265_REXT10_444;
    if (!plankUsesPackedBt709(&p)) return EXIT_FAILURE;
    p.enableIdentityGbr = true;
    if (plankUsesPackedBt709(&p)) return EXIT_FAILURE;
    p.enableIdentityGbr = false;
    p.videoFormat = VIDEO_FORMAT_H265_MAIN10;
    if (plankUsesPackedBt709(&p)) return EXIT_FAILURE;
    p.videoFormat = VIDEO_FORMAT_H265_REXT10_444;
    p.captureSource = DecoderCaptureSource::Nvfbc8Bit;
    if (plankUsesPackedBt709(&p)) return EXIT_FAILURE;
    p.captureSource = DecoderCaptureSource::ScreenCaptureKit;
    p.encoderBackend = DecoderEncoderBackend::NvencDirect;
    if (plankUsesPackedBt709(&p)) return EXIT_FAILURE;
    return EXIT_SUCCESS;
}
