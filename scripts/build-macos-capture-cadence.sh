#!/bin/bash
# Standalone metadata-only probe; never linked into the Host.
set -euo pipefail
[[ $# == 2 && $1 == /* && $2 == /* && $(uname -s) == Darwin ]]
[[ $(sw_vers -productVersion | cut -d . -f 1) -ge 27 ]]
[[ $(xcrun --sdk macosx --show-sdk-version | cut -d . -f 1) -ge 27 ]]
: "${PLANK_MACOS_SIGNING_IDENTITY:?Existing Apple signing identity required}"
[[ $PLANK_MACOS_SIGNING_IDENTITY =~ ^[[:xdigit:]]{40}$ ]]
source_root=$1; output=$2
mkdir "$output"
app="$output/PLANK Host Probe.app"
mkdir -p "$app/Contents/MacOS"
install -m 0644 "$source_root/probes/macos/Info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 57' "$app/Contents/Info.plist"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=27.0 \
    "$source_root/probes/macos/capture-cadence.m" -framework AppKit \
    -framework ScreenCaptureKit -framework CoreMedia -framework CoreVideo \
    -framework CoreGraphics -o "$app/Contents/MacOS/plank-host-probe"
codesign --force --sign "$PLANK_MACOS_SIGNING_IDENTITY" --timestamp=none \
    --identifier la.instinctual.PLANK.Host.Probe "$app"
codesign --verify --strict "$app"
shasum -a 256 "$app/Contents/MacOS/plank-host-probe"
