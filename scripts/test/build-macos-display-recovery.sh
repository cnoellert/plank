#!/usr/bin/env bash
# Synthetic-only recovery gates. Suitable for a hosted macOS runner.
set -euo pipefail
source_root=${1:?absolute source required}
output=${2:?new absolute output required}
[[ $source_root = /* && $output = /* && $(uname -s) = Darwin ]]
mkdir "$output"
common=(-mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror
    -I"$source_root/apps/host/macos/control" -I"$source_root/apps/host/macos/auth"
    -framework Foundation -framework AppKit -framework CoreGraphics -framework Security
    -framework SystemConfiguration -framework Network -framework IOKit)
# Only the test object redirects virtual-class lookup; production compilation
# always uses the real framework classes. CG/IOKit stubs are test-link-only.
xcrun clang -mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror \
    -DNSClassFromString=PLANKTestClassFromString \
    -I"$source_root/apps/host/macos/control" \
    -c "$source_root/apps/host/macos/control/desktop-display.m" -o "$output/display.o"
xcrun clang "${common[@]}" "$output/display.o" \
    "$source_root/tests/auth/macos-display-recovery.m" -o "$output/display-recovery-test"
"$output/display-recovery-test"
xcrun clang "${common[@]}" -DPLANK_SYNTHETIC_AUTH_TEST \
    "$source_root/apps/host/macos/control/http-request.m" \
    "$source_root/apps/host/macos/control/server-information.m" \
    "$source_root/apps/host/macos/control/fixed-capture.m" \
    "$source_root/apps/host/macos/control/https-auth-server.m" \
    "$source_root/apps/host/macos/auth/authentication-session.m" \
    "$source_root/apps/host/macos/auth/graphical-authority.m" \
    "$source_root/probes/macos/https-auth.m" -o "$output/https-auth-synthetic"
python3 "$source_root/tests/auth/macos-topology-recovery.py" \
    "$output/https-auth-synthetic" "$source_root/probes/macos/loopback-cert.cnf"
