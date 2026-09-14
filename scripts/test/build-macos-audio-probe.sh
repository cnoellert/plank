#!/bin/bash
# Standalone signed system-audio qualification, never a product package.
set -euo pipefail
if [[ $# != 2 || $1 != /* || $2 != /* ]]; then
    echo "Usage: $0 /absolute/source /absolute/empty-output" >&2; exit 2
fi
if [[ $(uname -s) != Darwin || $(sw_vers -productVersion | cut -d . -f 1) -lt 27 ||
      $(xcrun --sdk macosx --show-sdk-version | cut -d . -f 1) -lt 27 ]]; then
    echo "Requires the dedicated macOS 27/SDK 27 development Mac." >&2; exit 2
fi
: "${PLANK_MACOS_SIGNING_IDENTITY:?Set the existing Apple Development identity SHA-1}"
[[ $PLANK_MACOS_SIGNING_IDENTITY =~ ^[[:xdigit:]]{40}$ ]]
source_root=$1
output=$2
mkdir "$output"
app="$output/PLANK Host Probe.app"
mkdir -p "$app/Contents/MacOS"
install -m 0644 "$source_root/probes/macos/Info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 46' "$app/Contents/Info.plist"
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=27.0 \
    "$source_root/probes/macos/audio-capture.m" -framework AppKit \
    -framework AVFoundation -framework ScreenCaptureKit -framework CoreMedia \
    -framework CoreGraphics -framework AudioToolbox -o "$app/Contents/MacOS/plank-host-probe"
codesign --force --sign "$PLANK_MACOS_SIGNING_IDENTITY" --timestamp=none \
    --identifier la.instinctual.PLANK.Host.Probe "$app"
codesign --verify --strict "$app"
shasum -a 256 "$app/Contents/MacOS/plank-host-probe"
