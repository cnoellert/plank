#!/bin/bash
# Standalone development probes only; never produces a release package.
set -euo pipefail
if [[ $# != 1 || $1 != /* ]]; then
    echo "Usage: bash $0 /absolute/empty-output-directory" >&2
    exit 2
fi
probe_sources=$(cd "$(dirname "$0")" && pwd)
: "${PLANK_MACOS_SIGNING_IDENTITY:?Set the Apple Development identity SHA-1 from security find-identity -v -p codesigning}"
if [[ ! $PLANK_MACOS_SIGNING_IDENTITY =~ ^[[:xdigit:]]{40}$ ]]; then
    echo "An exact certificate identity SHA-1 is required; ad-hoc signing is not allowed." >&2
    exit 2
fi
if ! security find-identity -v -p codesigning | grep -Fq "$PLANK_MACOS_SIGNING_IDENTITY"; then
    echo "Requested signing identity is not valid/available in the current keychain." >&2
    exit 2
fi
if [[ $(sw_vers -productVersion | cut -d . -f 1) -lt 27 ||
      $(xcrun --sdk macosx --show-sdk-version | cut -d . -f 1) -lt 27 ]]; then
    echo "PLANK macOS probes require macOS 27 and SDK 27 or newer." >&2
    exit 2
fi
probe_output=$1
mkdir -p "$probe_output"
if [[ -n $(ls -A "$probe_output") ]]; then
    echo "Refusing to replace existing probe output." >&2
    exit 2
fi
for probe_name in desktop-inventory virtual-display-api virtual-display-lifecycle display-mode-lifecycle display-owner-lifecycle display-initial-mode; do
    xcrun clang -mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror \
        -framework Foundation -framework CoreGraphics \
        "$probe_sources/$probe_name.m" -o "$probe_output/$probe_name"
done
xcrun clang -mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror \
    -framework Foundation -framework CoreGraphics -framework SystemConfiguration -framework Security \
    "$probe_sources/session-observer.m" -o "$probe_output/session-observer"
xcrun clang -mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror \
    -framework Foundation -framework VideoToolbox -framework CoreMedia -framework CoreVideo \
    "$probe_sources/hardware-encode.m" -o "$probe_output/hardware-encode"
probe_app="$probe_output/PLANK Host Probe.app"
mkdir -p "$probe_app/Contents/MacOS"
install -m 0644 "$probe_sources/Info.plist" "$probe_app/Contents/Info.plist"
xcrun clang -mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror \
    -Wl,-sectcreate,__CGPreLoginApp,__cgpreloginapp,/dev/null \
    -framework Foundation -framework AppKit -framework ApplicationServices -framework CoreGraphics -framework SystemConfiguration -framework Security \
    -framework CoreMedia -framework CoreVideo -framework ScreenCaptureKit -framework VideoToolbox -framework QuartzCore \
    "$probe_sources/screen-capture.m" "$probe_sources/input-delivery.m" "$probe_sources/capture-encode.m" \
    "$probe_sources/pattern-validation.m" "$probe_sources/display-owner-probe.m" \
    -o "$probe_app/Contents/MacOS/plank-host-probe"
# Apple IOHIDFamily's tools use this pre-login WindowServer declaration.
# Keep it explicit and qualified: it is not a TCC grant or a private entitlement.
otool -l "$probe_app/Contents/MacOS/plank-host-probe" | awk '
    /sectname __cgpreloginapp/ { section = 1 }
    /segname __CGPreLoginApp/ { segment = 1 }
    END { exit !(section && segment) }
'
codesign --force --sign "$PLANK_MACOS_SIGNING_IDENTITY" --timestamp=none \
    --identifier la.instinctual.PLANK.Host.Probe "$probe_app"
codesign --verify --strict "$probe_app"
plutil -lint "$probe_app/Contents/Info.plist" "$probe_sources/probe-agent.plist"
bash -n "$probe_sources/run-graphical-probe.sh"
