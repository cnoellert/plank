// SPDX-License-Identifier: GPL-3.0-or-later
// Exercise the existing Client parser, not a substitute XML implementation.
#include "backend/nvcomputer.h"
#include <QCoreApplication>
#include <QFile>
#include <cstdio>

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    if (argc != 2) return 2;
    QFile fixture(QString::fromLocal8Bit(argv[1]));
    if (!fixture.open(QIODevice::ReadOnly)) return 2;
    const QString xml = QString::fromUtf8(fixture.readAll());
    try {
        NvHTTP::verifyResponseStatus(xml);
        NvHTTP http(NvAddress(QStringLiteral("127.0.0.1"), 28989));
        NvComputer computer(http, xml);
        if (computer.name != QStringLiteral("PLANK Mac qualification") ||
                computer.uuid != QStringLiteral("f92140f5-8740-4b3b-82f7-74db5353de27") ||
                computer.state != NvComputer::CS_ONLINE || !computer.plankAuthentication ||
                computer.authorizationState != NvComputer::AS_UNAUTHORIZED ||
                computer.plankHostMetadataVersion != 1 ||
                computer.plankHostVersion != QStringLiteral("macos-host-qualification") ||
                computer.serverCodecModeSupport != 0 || computer.plankFeatureFlags != 0 ||
                computer.plankTopologyVersion != 0 || computer.currentGameId != 0 ||
                !computer.displayModes.isEmpty() || !computer.sessionToken.isEmpty() ||
                !computer.localAddress.isNull() || !computer.remoteAddress.isNull()) return 1;
        NvHTTP wrongPort(NvAddress(QStringLiteral("127.0.0.1"), 28990));
        bool rejectedPort = false;
        try { NvComputer invalid(wrongPort, xml); }
        catch (const GfeHttpResponseException& exception) { rejectedPort = exception.getStatusCode() == 400; }
        if (!rejectedPort) return 1;
        std::puts("macos_client_discovery=pass actual_client_parser=1 online_metadata=1 no_media_claim=1 mismatched_port_rejected=1");
        return 0;
    } catch (const std::exception&) {
        // Do not echo unknown server response text into a test log.
        return 1;
    }
}
