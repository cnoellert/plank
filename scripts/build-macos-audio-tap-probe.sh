#!/bin/bash
# Standalone feasibility app. Never replaces PLANK Host or its approved Probe.
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
mkdir "$2"
app="$2/PLANK Audio Tap Probe.app"
mkdir -p "$app/Contents/MacOS"
install -m 0644 "$1/probes/macos/Info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier la.instinctual.PLANK.AudioTapProbe' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName PLANK Audio Tap Probe' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName PLANK Audio Tap Probe' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 2' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSAudioCaptureUsageDescription string Test streaming system audio while suppressing local speaker playback. No microphone or audio recordings.' "$app/Contents/Info.plist"
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=27.0 \
    -I"$1/host/macos/media" "$1/probes/macos/audio-tap.m" \
    "$1/host/macos/media/opus-encoder.m" -framework AppKit -framework CoreAudio \
    -framework CoreMedia -framework AudioToolbox \
    -o "$app/Contents/MacOS/plank-host-probe"
codesign --force --sign "$PLANK_MACOS_SIGNING_IDENTITY" --timestamp=none "$app"
codesign --verify --strict "$app"
shasum -a 256 "$app/Contents/MacOS/plank-host-probe"
