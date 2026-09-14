#!/bin/bash
# Own-window and scoped LoginWindow-motion tests. No login or TCC changes.
set -euo pipefail
if [[ $# != 2 || $1 != /* || $2 != /* ]]; then
    echo "Usage: $0 /absolute/source /absolute/empty-output" >&2; exit 2
fi
if [[ $(uname -s) != Darwin ||
      $(sw_vers -productVersion | cut -d . -f 1) -lt 27 ||
      $(xcrun --sdk macosx --show-sdk-version | cut -d . -f 1) -lt 27 ]]; then
    echo "Requires dedicated macOS 27/SDK 27 development Mac." >&2; exit 2
fi
: "${PLANK_MACOS_SIGNING_IDENTITY:?Set the existing Apple Development identity SHA-1}"
[[ $PLANK_MACOS_SIGNING_IDENTITY =~ ^[[:xdigit:]]{40}$ ]]
source_root=$1
output=$2
mkdir "$output"
cd "$source_root"
app="$output/PLANK Host Probe.app"
mkdir -p "$app/Contents/MacOS"
install -m 0644 probes/macos/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 56' "$app/Contents/Info.plist"
xcrun --sdk macosx clang -mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror \
    -Iapps/host/macos/input -Iprotocol/plank-transport/include \
    apps/host/macos/input/input-events.m probes/macos/native-input-delivery.m probes/macos/login-pointer.m \
    -framework Foundation -framework CoreGraphics -framework Carbon -framework AppKit \
    -framework ApplicationServices -framework Security -framework SystemConfiguration \
    -Wl,-sectcreate,__CGPreLoginApp,__cgpreloginapp,/dev/null \
    -o "$app/Contents/MacOS/plank-host-probe"
codesign --force --sign "$PLANK_MACOS_SIGNING_IDENTITY" --timestamp=none \
    --identifier la.instinctual.PLANK.Host.Probe "$app"
codesign --verify --strict "$app"
shasum -a 256 apps/host/macos/input/input-events.{h,m} probes/macos/native-input-delivery.m \
    probes/macos/login-pointer.m probes/macos/session-boundary.h \
    "$app/Contents/MacOS/plank-host-probe"
