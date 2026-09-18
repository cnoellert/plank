#!/usr/bin/env bash
# Standalone read-only Client tablet probe; no Host code or package installation.
set -euo pipefail
[[ $# == 2 && $1 == /* && $2 == /* ]] || {
    echo 'usage: build-macos-client-hid-probe.sh SOURCE NEW_OUTPUT' >&2; exit 2;
}
source_root=$1
output=$2
source "$source_root/scripts/build/macos-client-target.sh"
plank_macos_client_target
umask 077
mkdir "$output"
xcrun --sdk macosx clang -fobjc-arc -Wall -Wextra -Werror -arch arm64 \
    -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" \
    "$source_root/probes/wacom/macos-client-hid.m" \
    -framework Foundation -framework IOKit -o "$output/macos-client-hid"
codesign --force --sign - "$output/macos-client-hid"
codesign --verify --strict "$output/macos-client-hid"
python3 "$source_root/scripts/test/check-macos-client-target.py" \
    "$output" --target "$PLANK_MAC_CLIENT_MIN_MACOS" > "$output/targets.json"
echo 'client_hid_probe_build=pass live_capture=untested'
