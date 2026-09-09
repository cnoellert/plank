#!/bin/bash
# Uninstalled native Host executable; no synthetic verifier or probe main.
set -euo pipefail
if [[ $# != 3 || $1 != /* || $2 != /* || $3 != /* || $(uname -s) != Darwin ||
      $(sw_vers -productVersion | cut -d . -f 1) -lt 27 ||
      $(xcrun --sdk macosx --show-sdk-version | cut -d . -f 1) -lt 27 ]]; then
    echo 'Usage (development Mac): build-macos-host.sh SOURCE EMPTY_OUTPUT TRANSPORT_ARCHIVE' >&2; exit 2
fi
: "${PLANK_MACOS_HOST_VERSION:?Explicit branch-qualified version required}"
[[ $PLANK_MACOS_HOST_VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z][a-z0-9.-]*)?$ ]]
source_root=$1; output=$2; archive=$3
mkdir "$output"
cd "$source_root"
xcrun clang -mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror \
    -Ihost/macos/input -Iprotocol/plank-transport/include \
    host/macos/input/input-events.m tests/input/macos-pen-events.m \
    -framework Foundation -framework CoreGraphics -framework Carbon -o "$output/pen-events-test"
# CGEventSourceCreate needs access to WindowServer even though this fixture
# never posts events. SSH from a different account cannot obtain that source.
# Only this non-posting fixture uses the console bootstrap; the build/signing
# remain under the build account. Never skip the test or change TCC to run it.
console_uid=$(/usr/bin/stat -f %u /dev/console)
if [[ $console_uid = 0 ]]; then
    echo 'The non-posting graphics fixture needs a logged-in desktop on the development Mac. Log in, then rebuild.' >&2
    exit 1
fi
if [[ $console_uid = "$(id -u)" ]]; then
    "$output/pen-events-test"
else
    echo "Checking non-posting pen fixture in console bootstrap UID $console_uid"
    sudo -n /bin/launchctl asuser "$console_uid" "$output/pen-events-test"
fi
xcrun clang -std=c11 -mmacosx-version-min=27.0 -Wall -Wextra -Werror \
    -Ihost/macos/session tests/auth/macos-permission-status.c -o "$output/permission-status-test"
"$output/permission-status-test"
xcrun clang -mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror \
    -Ihost/macos/session tests/auth/macos-desktop-provisioning.m host/macos/session/desktop-provisioning.m \
    -framework Foundation -framework Security -o "$output/desktop-provisioning-test"
"$output/desktop-provisioning-test"
xcrun clang -std=c11 -mmacosx-version-min=27.0 -Wall -Wextra -Werror \
    -Ihost/macos/media tests/audio/macos-audio-tap-buffer.c -o "$output/audio-tap-buffer-test"
"$output/audio-tap-buffer-test"
xcrun clang -mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror \
    -Ihost/macos/media tests/audio/macos-audio-tap-lifecycle.m host/macos/media/audio-tap.m \
    -framework Foundation -framework CoreMedia -framework CoreAudio -framework Security -o "$output/audio-tap-lifecycle-test"
"$output/audio-tap-lifecycle-test"
xcrun clang -mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror \
    -Ihost/macos/media tests/audio/macos-opus-encoder.m host/macos/media/opus-encoder.m \
    -framework Foundation -framework CoreMedia -framework AudioToolbox -o "$output/opus-encoder-test"
"$output/opus-encoder-test" "$output/opus-fixture.pao"
xcrun clang -mmacosx-version-min=27.0 -Wall -Wextra -Werror \
    -Ihost/macos/media tests/video/macos-frame-timing.c -o "$output/frame-timing-test"
"$output/frame-timing-test"
xcrun clang -mmacosx-version-min=27.0 -Wall -Wextra -Werror \
    -Ihost/macos/media tests/video/macos-video-recovery.c -o "$output/video-recovery-test"
"$output/video-recovery-test"
common=(-mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror
    -Ihost/macos/auth -Ihost/macos/control -Ihost/macos/media -Ihost/macos/input
    -Ihost/macos/session -Iprotocol/plank-transport/include
    -framework Foundation -framework Security -framework SystemConfiguration -framework CoreFoundation
    -framework CoreGraphics -framework AppKit -framework Network -framework CoreMedia
    -framework CoreVideo -framework ScreenCaptureKit -framework VideoToolbox -framework AudioToolbox -framework CoreAudio
    -framework Carbon -framework ApplicationServices -framework OpenDirectory
    -Wl,-sectcreate,__CGPreLoginApp,__cgpreloginapp,/dev/null)
sources=(host/macos/auth/authentication-session.m host/macos/auth/graphical-authority.m
    host/macos/auth/account-verifier.m host/macos/auth/account-channel.m
    host/macos/control/http-request.m host/macos/control/server-information.m
    host/macos/control/fixed-capture.m host/macos/control/desktop-display.m host/macos/control/https-auth-server.m
    host/macos/media/native-video.m host/macos/media/preview-session.m host/macos/media/screen-capture.m
    host/macos/media/native-audio.m host/macos/media/opus-encoder.m host/macos/media/audio-tap.m
    host/macos/input/input-events.m host/macos/input/native-input.m host/macos/input/quartz-input.m
    host/macos/session/agent-registry.m host/macos/session/agent-connection.m
    host/macos/session/desktop-provisioning.m
    host/macos/session/host-runtime.m host/macos/session/host-main.m)
xcrun clang "${common[@]}" "-DPLANK_MACOS_HOST_VERSION=\"$PLANK_MACOS_HOST_VERSION\"" \
    "${sources[@]}" "$archive" -lpthread -lm -o "$output/plank-host"
# Ad-hoc is only for uninstalled assembly checks. TCC/live capture needs the
# protected Apple-signed application and is NOT qualified by this build.
codesign --force --sign - --identifier la.instinctual.PLANK.Host "$output/plank-host"
codesign --verify --strict "$output/plank-host"
shasum -a 256 "$archive" "$output/plank-host"
if [[ -n ${PLANK_MACOS_SIGNING_IDENTITY:-} ]]; then
    [[ $PLANK_MACOS_SIGNING_IDENTITY =~ ^[[:xdigit:]]{40}$ ]]
    app="$output/PLANK Host.app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$output/plank.iconset"
    xcrun clang -mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror \
        scripts/macos-app-icon.m -framework Foundation -framework CoreGraphics \
        -framework ImageIO -o "$output/macos-app-icon"
    "$output/macos-app-icon" "$source_root/branding/assets/plank-logo.png" "$output/plank.iconset"
    iconutil -c icns "$output/plank.iconset" -o "$app/Contents/Resources/plank.icns"
    test -s "$app/Contents/Resources/plank.icns"
    install -m 0755 "$output/plank-host" "$app/Contents/MacOS/plank-host"
    install -m 0644 packaging/macos/host-info.plist "$app/Contents/Info.plist"
    signing_flags=(--timestamp=none)
    case ${PLANK_MACOS_DISTRIBUTION:-0} in
      0) install -m 0644 scripts/install-macos-host-development.py scripts/uninstall-macos-host-development.py "$app/Contents/Resources/" ;;
      1) signing_flags=(--options runtime --timestamp) ;;
      *) echo 'PLANK_MACOS_DISTRIBUTION must be 0 or 1' >&2; exit 2 ;;
    esac
    /usr/libexec/PlistBuddy -c "Add :PLANKVersion string $PLANK_MACOS_HOST_VERSION" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${PLANK_MACOS_HOST_VERSION%%-*}" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${PLANK_MACOS_HOST_VERSION%%-*}" "$app/Contents/Info.plist"
    codesign --force --sign "$PLANK_MACOS_SIGNING_IDENTITY" "${signing_flags[@]}" \
        --identifier la.instinctual.PLANK.Host "$app"
    codesign --verify --strict "$app"
    shasum -a 256 "$app/Contents/MacOS/plank-host"
fi
