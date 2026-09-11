// Non-authenticated TLS1.3 packaging probe. No secrets or OS permission edits.
#include <QCoreApplication>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QSslConfiguration>
#include <QSslSocket>
#include <QTimer>
#include <QDebug>

int main(int argc, char** argv)
{
    QCoreApplication app(argc, argv);
    if (argc != 3) return 2;
    QCoreApplication::setLibraryPaths({QString::fromLocal8Bit(argv[1])});
    qInfo() << "backends" << QSslSocket::availableBackends()
            << "selected" << QSslSocket::activeBackend()
            << "SSL" << QSslSocket::sslLibraryVersionString();
    QNetworkAccessManager network;
    QNetworkRequest request{QUrl(QString::fromLocal8Bit(argv[2]))};
    auto ssl = QSslConfiguration::defaultConfiguration();
    ssl.setProtocol(QSsl::TlsV1_3OrLater);
    // This probe fetches only public metadata from the explicitly supplied test
    // Host. Production pinning/authentication policy is not changed or tested.
    ssl.setPeerVerifyMode(QSslSocket::VerifyNone);
    request.setSslConfiguration(ssl);
    auto* reply = network.get(request);
    QObject::connect(reply, &QNetworkReply::finished, &app, [&] {
        qInfo() << "reply" << reply->error() << reply->errorString()
                << "TLS" << reply->sslConfiguration().sessionProtocol();
        app.exit(reply->error() == QNetworkReply::NoError ? 0 : 1);
    });
    QTimer::singleShot(5000, &app, [&] { reply->abort(); });
    return app.exec();
}
