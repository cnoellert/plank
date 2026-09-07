#!/bin/bash
# Signed, loopback-only authenticated capture qualification, not a release.
set -euo pipefail
if [[ $# != 3 || $1 != /* || $2 != /* || $3 != /* ]]; then
    echo "Usage: $0 /absolute/source /absolute/empty-output /absolute/libplank_transport.a" >&2
    exit 2
fi
source_root=$1
preview_build=$2
archive=$3
if [[ $(uname -s) != Darwin || $(sw_vers -productVersion | cut -d . -f 1) -lt 27 ||
    $(xcrun --sdk macosx --show-sdk-version | cut -d . -f 1) -lt 27 ]]; then
    echo "Requires dedicated macOS 27/SDK 27 development Mac." >&2; exit 2
fi
: "${PLANK_MACOS_SIGNING_IDENTITY:?Set the existing Apple Development identity SHA-1}"
[[ $PLANK_MACOS_SIGNING_IDENTITY =~ ^[[:xdigit:]]{40}$ ]]
mkdir -p "$preview_build"
[[ -z $(ls -A "$preview_build") ]]
cd "$source_root"
common=(-mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror
    -Ihost/macos/auth -Ihost/macos/control -Ihost/macos/media -Iprotocol/plank-transport/include
    -framework Foundation -framework Security -framework SystemConfiguration -framework CoreFoundation
    -framework CoreGraphics -framework AppKit -framework Network -framework CoreMedia
    -framework CoreVideo -framework ScreenCaptureKit -framework VideoToolbox)
sources=(host/macos/auth/authentication-session.m host/macos/auth/desktop-authority.m
    host/macos/control/http-request.m host/macos/control/server-information.m
    host/macos/control/fixed-capture.m host/macos/control/https-auth-server.m
    host/macos/media/native-video.m host/macos/media/preview-session.m host/macos/media/screen-capture.m
    probes/macos/https-auth.m)
xcrun clang "${common[@]}" -DPLANK_MAC_PREVIEW_TEST -DPLANK_SYNTHETIC_AUTH_TEST \
    "${sources[@]}" "$archive" -lpthread -lm -o "$preview_build/preview-synthetic"
xcrun clang "${common[@]}" probes/macos/preview-receive.m "$archive" -lpthread -lm \
    -o "$preview_build/preview-receive"
preview_app="$preview_build/PLANK Host Probe.app"
mkdir -p "$preview_app/Contents/MacOS"
install -m 0644 probes/macos/Info.plist "$preview_app/Contents/Info.plist"
xcrun clang "${common[@]}" -DPLANK_MAC_PREVIEW_TEST "${sources[@]}" \
    host/macos/auth/account-verifier.m host/macos/auth/account-channel.m -framework OpenDirectory \
    "$archive" -lpthread -lm -o "$preview_app/Contents/MacOS/plank-host-probe"
codesign --force --sign "$PLANK_MACOS_SIGNING_IDENTITY" --timestamp=none \
    --identifier la.instinctual.PLANK.Host.Probe "$preview_app"
codesign --verify --strict "$preview_app"
shasum -a 256 "$archive" "$preview_app/Contents/MacOS/plank-host-probe" \
    "$preview_build/preview-synthetic" "$preview_build/preview-receive"
