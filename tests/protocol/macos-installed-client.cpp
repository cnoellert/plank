// Actual Client HTTPS/auth/launch plus native media. No GUI, device access,
// installation, synthetic verifier, password file, or login-screen input.
#include "backend/nvhttp.h"
#include "plank_transport.h"
#include "plank_transport_control.h"
#include "streaming/video/applevideoprofile.h"
#include <QCoreApplication>
#include <QFile>
#include <QElapsedTimer>
#include <QThread>
#include <cstdio>
#include <cstring>
#include <memory>
#include <vector>
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavutil/pixdesc.h>
#include <opus/opus.h>
}

#define CHECK(x) do { if (!(x)) { std::fprintf(stderr, "check failed at %d\n", __LINE__); return 1; } } while (0)
int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);
    CHECK(argc == 4);
    bool valid = false;
    const int port = QString::fromLocal8Bit(argv[2]).toInt(&valid);
    CHECK(valid && port > 0 && port <= 65535);
    QFile input;
    CHECK(input.open(stdin, QIODevice::ReadOnly));
    QByteArray password = input.readLine(4098).trimmed();
    CHECK(!password.isEmpty() && password.size() <= 4096);
    try {
        NvHTTP http(NvAddress(QString::fromLocal8Bit(argv[1]), static_cast<quint16>(port)));
        const QString info = http.getServerInfo(NvHTTP::NVLL_NONE);
        CHECK(NvHTTP::getXmlString(info, "ServerCodecModeSupport") == "512");
        const QString token = http.authenticate(QString::fromLocal8Bit(argv[3]), QString::fromUtf8(password));
        password.fill('\0'); password.clear();
        http.setPlankSessionToken(token);
        QString pin;
        const auto topology = http.getOutputTopology(&pin);
        CHECK(topology.featureFlags == NvOutputTopology::FixedCaptureFlags);
        const auto desktops = http.getAppList();
        CHECK(desktops.size() == 1 && desktops[0].name == QStringLiteral("Desktop"));
        auto launch = http.startMacPreview(topology, pin, 50000, 1200);
        const QByteArray remote = QByteArray(argv[1]) + ':' + QByteArray::number(port);
        const QByteArray fingerprint = pin.toLatin1();
        PlankTransportConfig config {};
        config.struct_size = sizeof(config); config.abi_version = PLANK_TRANSPORT_ABI_VERSION;
        config.mode = PLANK_TRANSPORT_MODE_CLIENT;
        config.remote_address = remote.constData(); config.server_name = "plank-host";
        config.certificate_sha256 = fingerprint.constData();
        config.session_token = launch.transportToken.constData();
        config.handshake_timeout_ms = 5000; config.idle_timeout_ms = 5000;
        config.keep_alive_interval_ms = 1000; config.max_udp_payload_size = 1200;
        PlankTransportNativeEndpoint* raw = nullptr;
        CHECK(plank_transport_native_endpoint_create(&config, &raw) == PLANK_TRANSPORT_OK);
        std::unique_ptr<PlankTransportNativeEndpoint, decltype(&plank_transport_native_endpoint_destroy)>
            endpoint(raw, plank_transport_native_endpoint_destroy);
        launch.transportToken.fill('\0'); launch.transportToken.clear();
        CHECK(plank_transport_native_endpoint_start(raw) == PLANK_TRANSPORT_OK);
        CHECK(plank_transport_native_endpoint_wait_ready(raw, 5000) == PLANK_TRANSPORT_OK);
        AVCodecContext* codec = avcodec_alloc_context3(avcodec_find_decoder(AV_CODEC_ID_HEVC));
        CHECK(codec);
        codec->thread_count = 4;
        CHECK(avcodec_open2(codec, codec->codec, nullptr) == 0);
        AVFrame* frame = av_frame_alloc();
        AVPacket* packet = av_packet_alloc();
        int opusError;
        OpusDecoder* audio = opus_decoder_create(48000, 2, &opusError);
        CHECK(audio && opusError == OPUS_OK);
        std::vector<uint8_t> bytes(64 * 1024 * 1024);
        unsigned frames = 0, decoded = 0, audioPackets = 0;
        uint64_t lastPTS = 0;
        QElapsedTimer clock; clock.start();
        while (clock.elapsed() < 15000) {
            PlankTransportNativeVideoFrameInfo video {}; video.struct_size = sizeof(video);
            size_t count = 0;
            const int result = plank_transport_native_video_receive(raw, &video, bytes.data(), bytes.size(), &count, 5);
            CHECK(result == PLANK_TRANSPORT_OK || result == PLANK_TRANSPORT_TIMEOUT);
            if (result == PLANK_TRANSPORT_OK) {
                CHECK(video.codec == PLANK_TRANSPORT_NATIVE_VIDEO_CODEC_HEVC && count > 0);
                CHECK(!frames || video.pts > lastPTS);
                lastPTS = video.pts; ++frames;
                CHECK(av_new_packet(packet, static_cast<int>(count)) == 0);
                std::memcpy(packet->data, bytes.data(), count);
                CHECK(avcodec_send_packet(codec, packet) == 0);
                av_packet_unref(packet);
                int status;
                while ((status = avcodec_receive_frame(codec, frame)) == 0) {
                    CHECK(frame->width == topology.desktopWidth && frame->height == topology.desktopHeight);
                    CHECK(frame->format == AV_PIX_FMT_YUV420P10LE && frame->color_range == AVCOL_RANGE_MPEG);
                    CHECK(frame->colorspace == AVCOL_SPC_BT709 && frame->color_primaries == AVCOL_PRI_BT709);
                    CHECK(plankAppleVideoFrameMatches(frame, codec->profile));
                    ++decoded;
                    av_frame_unref(frame);
                }
                CHECK(status == AVERROR(EAGAIN));
            }
            for (unsigned i = 0; i < 64; ++i) {
                uint8_t opus[65536]; size_t size = 0;
                PlankTransportNativeAudioPacketInfo sound {}; sound.struct_size = sizeof(sound);
                const int got = plank_transport_native_audio_receive(raw, &sound, opus, sizeof(opus), &size, 0);
                if (got == PLANK_TRANSPORT_TIMEOUT) break;
                CHECK(got == PLANK_TRANSPORT_OK && sound.frame_samples == 240 && sound.missing_samples == 0);
                float pcm[480];
                CHECK(opus_decode_float(audio, opus, static_cast<opus_int32>(size), pcm, 240, 0) == 240);
                ++audioPackets;
            }
        }
        CHECK(frames > 1 && decoded > 1 && audioPackets > 100);
        uint8_t control[20]; size_t count = 0; uint32_t bitrate = 55000;
        CHECK(!plank_transport_control_encode(PLANK_TRANSPORT_CONTROL_SET_VIDEO_BITRATE, &bitrate, 1, control, sizeof(control), &count));
        CHECK(plank_transport_native_data_send(raw, control, count) == PLANK_TRANSPORT_OK);
        CHECK(plank_transport_native_data_receive(raw, control, sizeof(control), &count, 5000) == PLANK_TRANSPORT_OK);
        PlankTransportControlPacket ack {};
        CHECK(!plank_transport_control_decode(control, count, &ack));
        CHECK(ack.type == PLANK_TRANSPORT_CONTROL_VIDEO_BITRATE_APPLIED && ack.payload_size == 12);
        CHECK(plank_transport_control_read_u32(ack.payload + 4) == bitrate);
        CHECK(!plank_transport_control_encode(PLANK_TRANSPORT_CONTROL_CLIENT_DISCONNECT, nullptr, 0, control, sizeof(control), &count));
        CHECK(plank_transport_native_data_send(raw, control, count) == PLANK_TRANSPORT_OK);
        QElapsedTimer drain; drain.start();
        while (plank_transport_native_endpoint_state(raw) == PLANK_TRANSPORT_STATE_READY && drain.elapsed() < 5000)
            QThread::msleep(10);
        CHECK(plank_transport_native_endpoint_state(raw) != PLANK_TRANSPORT_STATE_READY);
        opus_decoder_destroy(audio); av_packet_free(&packet); av_frame_free(&frame); avcodec_free_context(&codec);
        std::printf("installed_mac_client=pass network_frames=%u decoded_frames=%u opus_packets=%u pixels=%dx%d exact_main10=1 bitrate_ack=1 disconnect=1 graphical_client=0 input_posting=0\n",
                    frames, decoded, audioPackets, topology.desktopWidth, topology.desktopHeight);
    } catch (const GfeHttpResponseException& error) {
        std::fprintf(stderr, "HTTP failure: %d\n", error.getStatusCode()); return 1;
    } catch (const QtNetworkReplyException& error) {
        std::fprintf(stderr, "Network failure: %s\n", qPrintable(error.toQString())); return 1;
    }
}
