// SPDX-License-Identifier: GPL-3.0-or-later
// Linux-only, explicitly preloaded into an uninstalled Client under isolated
// XDG paths. Exercises the actual packaged QML; never shipped or auto-enabled.
#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlExpression>
#include <QQuickWindow>
#include <QTimer>
#include <QImage>
#include <cstdio>

static void require(bool condition, const char* message)
{
    if (!condition) qFatal("bookmark_ui_smoke: %s", message);
}

static QObject* item(QQmlContext* context, const char* name)
{
    auto* result = context->objectForName(QString::fromLatin1(name));
    require(result != nullptr, name);
    return result;
}

static void checkEdit(QQuickWindow* window, QQmlContext* mainContext,
                      const QString& address, const QString& output)
{
    auto* grid = item(mainContext, "stackView")->property("currentItem").value<QObject*>();
    require(grid && grid->property("count").toInt() == 1, "isolated bookmark created");
    auto* context = qmlContext(grid);
    auto* dialog = item(context, "editBookmarkDialog");
    dialog->setProperty("pcIndex", 0);
    dialog->setProperty("originalAddress", address);
    dialog->setProperty("originalNickname", "UI qualification");
    dialog->setProperty("originalCaptureSource", 2);
    dialog->setProperty("originalProfile", 8);
    QQmlExpression layoutValue(context, grid, "computerModel.plankHostLayoutChoice(0)");
    const QVariant savedLayout = layoutValue.evaluate();
    require(!layoutValue.hasError() && savedLayout.toInt() == 0, "Add saved Mac Match");
    dialog->setProperty("hostLayoutIndex", savedLayout);
    QQmlExpression bitrates(context, grid, "computerModel.plankProfileBitratesKbps(0)");
    dialog->setProperty("originalProfileBitratesKbps", bitrates.evaluate());
    require(!bitrates.hasError(), "saved per-profile bitrates");
    require(QMetaObject::invokeMethod(dialog, "open"), "open Edit");
    QTimer::singleShot(6000, qApp, [window, context, dialog, output]() {
        require(item(context, "editCaptureSource")->property("count").toInt() == 1, "Edit Mac-only capture");
        require(item(context, "editEncodingProfile")->property("currentIndex").toInt() == 1, "Edit preserves Apple444");
        require(item(context, "editHostLayout")->property("currentIndex").toInt() == 0, "Edit preserves Match");
        require(window->grabWindow().save(output + "/mac-edit.png"), "Edit screenshot");
        QMetaObject::invokeMethod(dialog, "close");
        std::puts("bookmark_ui_smoke=pass actual_packaged_qml=1 live_mac_discovery=1 match_fixed_controls=1 offline_manual=1 add_edit_roundtrip=1");
        QCoreApplication::quit();
    });
}

static void runBookmarkSmoke()
{
    const QString address = qEnvironmentVariable("PLANK_UI_SMOKE_HOST");
    const QString output = qEnvironmentVariable("PLANK_UI_SMOKE_DIR");
    require(!address.isEmpty() && !output.isEmpty(), "explicit test host/output required");
    QTimer::singleShot(1500, qApp, [address, output]() {
        QQuickWindow* window = nullptr;
        for (auto* candidate : QGuiApplication::allWindows()) {
            if (auto* quick = qobject_cast<QQuickWindow*>(candidate); quick && quick->isVisible()) {
                window = quick;
                break;
            }
        }
        require(window != nullptr, "main window");
        auto* context = qmlContext(window);
        require(context != nullptr, "main QML context");
        auto* dialog = item(context, "addPcDialog");
        require(QMetaObject::invokeMethod(dialog, "open"), "open Add");
        item(context, "addressText")->setProperty("text", address);
        QTimer::singleShot(6000, qApp, [window, context, dialog, address, output]() {
            auto* capture = item(context, "addCaptureSource");
            auto* profile = item(context, "addEncodingProfile");
            auto* layout = item(context, "addHostLayout");
            auto* resolution = item(context, "addVirtualMode1");
            require(capture->property("hostPlatform").toInt() == 2, "real Mac discovery");
            require(capture->property("count").toInt() == 1, "Mac-only capture");
            require(capture->property("captureSource").toInt() == 2, "capture enum, not filtered index");
            require(profile->property("count").toInt() == 2, "both Apple profiles");
            require(profile->property("currentIndex").toInt() >= 0, "valid default profile");
            require(layout->property("count").toInt() == 2, "Mac match/fixed choices");
            require(layout->property("enabled").toBool(), "enabled Mac layout");
            require(layout->property("currentIndex").toInt() == 0, "Match default");
            require(!resolution->property("enabled").toBool(), "no fixed size during Match");
            require(window->grabWindow().save(output + "/mac-match.png"), "Match screenshot");
            layout->setProperty("currentIndex", 1);
            require(resolution->property("enabled").toBool(), "fixed size selectable");
            QTimer::singleShot(300, qApp, [window, context, dialog, address, output]() {
                require(window->grabWindow().save(output + "/mac-fixed.png"), "fixed screenshot");
                require(QMetaObject::invokeMethod(dialog, "close"), "close Add");
                require(QMetaObject::invokeMethod(dialog, "open"), "reopen Add");
                item(context, "addressText")->setProperty("text", "");
                auto* capture = item(context, "addCaptureSource");
                require(capture->property("count").toInt() == 3, "unknown/offline choices");
                require(QMetaObject::invokeMethod(capture, "selectCaptureSource", Q_ARG(QVariant, QVariant(2))), "manual Mac selection");
                require(item(context, "addEncodingProfile")->property("count").toInt() == 2, "manual Mac profiles");
                item(context, "addressText")->setProperty("text", address);
                item(context, "nicknameText")->setProperty("text", "UI qualification");
                item(context, "addHostLayout")->setProperty("currentIndex", 0);
                item(context, "addEncodingProfile")->setProperty("currentIndex", 1);
                require(QMetaObject::invokeMethod(dialog, "accept"), "save isolated bookmark");
                QTimer::singleShot(2500, qApp, [window, context, address, output]() {
                    checkEdit(window, context, address, output);
                });
            });
        });
    });
}
Q_COREAPP_STARTUP_FUNCTION(runBookmarkSmoke)
