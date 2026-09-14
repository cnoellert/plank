#!/bin/bash
# Standalone own-process tablet qualification; never replaces the Host.
set -euo pipefail
if [[ $# != 2 || $1 != /* || $2 != /* ]]; then
    echo "Usage: $0 /absolute/source /absolute/new-output" >&2; exit 2
fi
if [[ $(uname -s) != Darwin ||
      $(sw_vers -productVersion | cut -d . -f 1) -lt 27 ||
      $(xcrun --sdk macosx --show-sdk-version | cut -d . -f 1) -lt 27 ]]; then
    echo "Requires dedicated macOS 27/SDK 27 development Mac." >&2; exit 2
fi
: "${PLANK_MACOS_SIGNING_IDENTITY:?Set the existing Apple Development identity SHA-1}"
[[ $PLANK_MACOS_SIGNING_IDENTITY =~ ^[[:xdigit:]]{40}$ ]]
mkdir "$2"
app="$2/PLANK Host Probe.app"
mkdir -p "$app/Contents/MacOS"
cd "$1"
install -m 0644 probes/macos/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 79' "$app/Contents/Info.plist"
xcrun --sdk macosx clang -mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror \
    probes/macos/tablet-pressure.m -framework AppKit -framework ApplicationServices \
    -framework Security -framework SystemConfiguration \
    -o "$app/Contents/MacOS/plank-host-probe"
"$app/Contents/MacOS/plank-host-probe" --inspect
codesign --force --sign "$PLANK_MACOS_SIGNING_IDENTITY" --timestamp=none \
    --identifier la.instinctual.PLANK.Host.Probe "$app"
codesign --verify --strict "$app"
shasum -a 256 probes/macos/tablet-pressure.m probes/macos/session-boundary.h \
    "$app/Contents/MacOS/plank-host-probe"
