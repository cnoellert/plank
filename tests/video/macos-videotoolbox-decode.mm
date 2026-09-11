// Standalone exact-format decode probe. No windows, capture, input or TCC edits.
#import <VideoToolbox/VideoToolbox.h>
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/hwcontext.h>
#include <libavutil/pixdesc.h>
}
#include <cstdio>
#include <cstring>

static AVPixelFormat requireVT(AVCodecContext*, const AVPixelFormat* formats)
{
    for (; *formats != AV_PIX_FMT_NONE; ++formats)
        if (*formats == AV_PIX_FMT_VIDEOTOOLBOX) return *formats;
    return AV_PIX_FMT_NONE; // Never disguise an unsupported hardware profile.
}

int main(int argc, char** argv)
{
    if (argc != 3 || (strcmp(argv[1], "hardware") && strcmp(argv[1], "software"))) return 2;
    const bool hardware = !strcmp(argv[1], "hardware");
    AVFormatContext* input = nullptr;
    if (avformat_open_input(&input, argv[2], nullptr, nullptr) < 0 ||
        avformat_find_stream_info(input, nullptr) < 0) return 3;
    const int stream = av_find_best_stream(input, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
    if (stream < 0) return 4;
    auto* context = avcodec_alloc_context3(avcodec_find_decoder(input->streams[stream]->codecpar->codec_id));
    avcodec_parameters_to_context(context, input->streams[stream]->codecpar);
    context->thread_count = 1;
    if (hardware) {
        context->get_format = requireVT;
        // Pinned FFmpeg's H.264/HEVC VT session requests RequireHardware.
        if (av_hwdevice_ctx_create(&context->hw_device_ctx, AV_HWDEVICE_TYPE_VIDEOTOOLBOX,
                                   nullptr, nullptr, 0) < 0) return 5;
    }
    if (avcodec_open2(context, context->codec, nullptr) < 0) return 6;
    auto* packet = av_packet_alloc();
    auto* frame = av_frame_alloc();
    int result = AVERROR(EAGAIN);
    while (av_read_frame(input, packet) >= 0) {
        if (packet->stream_index == stream) {
            result = avcodec_send_packet(context, packet);
            if (result >= 0)
                result = avcodec_receive_frame_flags(context, frame, AV_CODEC_RECEIVE_FRAME_FLAG_SYNCHRONOUS);
        }
        av_packet_unref(packet);
        if (result != AVERROR(EAGAIN)) break;
    }
    if (result == AVERROR(EAGAIN)) {
        avcodec_send_packet(context, nullptr);
        result = avcodec_receive_frame_flags(context, frame, AV_CODEC_RECEIVE_FRAME_FLAG_SYNCHRONOUS);
    }
    if (result < 0 || (hardware && frame->format != AV_PIX_FMT_VIDEOTOOLBOX)) {
        char error[128]; av_strerror(result, error, sizeof(error));
        fprintf(stderr, "decode=%s result=FAIL error=%s\n", argv[1], error);
        return 7;
    }
    AVPixelFormat storage = (AVPixelFormat)frame->format;
    if (frame->hw_frames_ctx)
        storage = ((AVHWFramesContext*)frame->hw_frames_ctx->data)->sw_format;
    const auto* desc = av_pix_fmt_desc_get(storage);
    OSType cvFormat = 0;
    if (hardware) cvFormat = CVPixelBufferGetPixelFormatType((CVPixelBufferRef)frame->data[3]);
    printf("decode=%s result=PASS size=%dx%d profile=%d storage=%s depth=%d chroma=%d:%d matrix=%d range=%d cv=%c%c%c%c\n",
           argv[1], frame->width, frame->height, context->profile, av_get_pix_fmt_name(storage),
           desc ? desc->comp[0].depth : -1, desc ? desc->log2_chroma_w : -1,
           desc ? desc->log2_chroma_h : -1, frame->colorspace, frame->color_range,
           hardware ? (cvFormat >> 24) & 255 : '-', hardware ? (cvFormat >> 16) & 255 : '-',
           hardware ? (cvFormat >> 8) & 255 : '-', hardware ? cvFormat & 255 : '-');
    av_frame_free(&frame); av_packet_free(&packet);
    avcodec_free_context(&context); avformat_close_input(&input);
    return 0;
}
