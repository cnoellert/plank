#include "backend/macpreviewlaunch.h"
#include <QCoreApplication>
#include <QFile>
#include <QJsonDocument>
#include <cstdio>
#include <cstdlib>

static unsigned checks;
#define CHECK(x) do { checks++; if (!(x)) { \
    std::fprintf(stderr, "line %d: %s\n", __LINE__, #x); std::exit(1); } } while (0)

int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);
    CHECK(argc == 3);
    QFile topologyFile(QString::fromLocal8Bit(argv[1]));
    QFile requestFile(QString::fromLocal8Bit(argv[2]));
    CHECK(topologyFile.open(QIODevice::ReadOnly));
    CHECK(requestFile.open(QIODevice::ReadOnly));
    const auto rawTopology = QJsonDocument::fromJson(topologyFile.readAll()).object();
    const auto expected = QJsonDocument::fromJson(requestFile.readAll()).object();
    NvOutputTopology topology;
    CHECK(NvOutputTopology::fromJson(rawTopology, topology));
    CHECK(MacPreviewLaunch::request(topology, expected.value("bitrate_kbps").toInt(),
                                   expected.value("max_udp_payload_size").toInt()) == expected);
    CHECK(MacPreviewLaunch::request(topology, 9999, 1200).isEmpty());
    CHECK(MacPreviewLaunch::request(topology, 150001, 1200).isEmpty());
    CHECK(MacPreviewLaunch::request(topology, 10000, 1199).isEmpty());
    CHECK(MacPreviewLaunch::request(topology, 10000, 65528).isEmpty());
    CHECK(!MacPreviewLaunch::request(topology, 150000, 65527).isEmpty());
    CHECK(MacPreviewLaunch::request({}, 10000, 1200).isEmpty());
    const QJsonObject valid {
        {"schema_version", 1}, {"state", "connecting"}, {"udp_port", 28989},
        {"max_udp_payload_size", 1200}, {"capture", rawTopology.value("capture")},
        {"transport_token", QString::fromLatin1(QByteArray(32, 'x').toBase64())},
        {"services", QJsonObject {{"audio", true}, {"input", true}, {"cursor", "embedded"}}}
    };
    MacPreviewLaunch::Reply parsed;
    CHECK(MacPreviewLaunch::parseReply(valid, topology, 28989, 1200, parsed));
    CHECK(parsed.configuration.serviceFlags == (PLANK_NATIVE_SERVICE_AUDIO | PLANK_NATIVE_SERVICE_INPUT));
    CHECK(parsed.configuration.hostFeatureFlags == LI_FF_DYNAMIC_VIDEO_BITRATE);
    CHECK(parsed.configuration.audioPacketDurationMs == 5);
    CHECK(parsed.configuration.opusConfiguration.sampleRate == 48000);
    CHECK(parsed.configuration.opusConfiguration.channelCount == 2);
    CHECK(parsed.configuration.opusConfiguration.streams == 1);
    CHECK(parsed.configuration.opusConfiguration.coupledStreams == 1);
    CHECK(parsed.configuration.opusConfiguration.mapping[0] == 0);
    CHECK(parsed.configuration.opusConfiguration.mapping[1] == 1);
    CHECK(parsed.configuration.negotiatedVideoFormat == VIDEO_FORMAT_H265_MAIN10);
    CHECK(parsed.configuration.sessionPort == 28989);
    auto reject = [&](const QJsonObject& bad) {
        CHECK(MacPreviewLaunch::parseReply(valid, topology, 28989, 1200, parsed));
        CHECK(!MacPreviewLaunch::parseReply(bad, topology, 28989, 1200, parsed));
        CHECK(parsed.transportToken.isEmpty() && parsed.configuration.structSize == 0);
    };
    for (const auto& key : valid.keys()) {
        auto bad = valid; bad.remove(key); reject(bad);
        bad = valid; bad[key] = QJsonValue::Null; reject(bad);
    }
    for (const char* key : {"udp_port", "schema_version", "max_udp_payload_size"}) {
        auto bad = valid; bad[key] = true; reject(bad);
        bad[key] = valid.value(key).toDouble() + 0.5; reject(bad);
    }
    auto bad = valid; bad["udp_port"] = 443; reject(bad);
    bad = valid; bad["max_udp_payload_size"] = 1500; reject(bad);
    bad = valid; bad["remote_address"] = "another-host"; reject(bad);
    bad = valid; bad["certificate_sha256"] = "another-certificate"; reject(bad);
    bad = valid; bad["transport_token"] = QString(44, 'x'); reject(bad);
    bad = valid; bad["transport_token"] = QString::fromLatin1(QByteArray(31, 'x').toBase64()); reject(bad);
    for (const char* service : {"audio", "input", "cursor"}) {
        auto services = valid.value("services").toObject(); services[service] = false;
        bad = valid; bad["services"] = services; reject(bad);
    }
    auto capture = rawTopology.value("capture").toObject();
    capture["width"] = capture.value("width").toInt() + 2;
    bad = valid; bad["capture"] = capture; reject(bad);
    CHECK(!MacPreviewLaunch::parseReply(valid, topology, 28990, 1200, parsed));
    CHECK(!MacPreviewLaunch::parseReply(valid, topology, 28989, 1300, parsed));
    std::printf("Mac preview launch: %u checks passed\n", checks);
}
