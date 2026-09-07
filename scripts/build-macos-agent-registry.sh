#!/bin/bash
# Compile real machine-side ownership component and non-media XPC tests.
set -euo pipefail
if [[ $# != 2 || $1 != /* || $2 != /* ]]; then
    echo "Usage: $0 /absolute/source /absolute/empty-output" >&2; exit 2
fi
if [[ $(uname -s) != Darwin ||
      $(sw_vers -productVersion | cut -d . -f 1) -lt 27 ||
      $(xcrun --sdk macosx --show-sdk-version | cut -d . -f 1) -lt 27 ]]; then
    echo "Requires dedicated macOS 27/SDK 27 development Mac." >&2; exit 2
fi
source_root=$1
output=$2
mkdir "$output"
cd "$source_root"
xcrun --sdk macosx clang -mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror \
    -Ihost/macos/session host/macos/session/agent-registry.m host/macos/session/agent-connection.m \
    tests/auth/macos-agent-registry.m \
    -framework Foundation -framework Security -framework SystemConfiguration \
    -o "$output/agent-registry"
codesign --force --sign - --identifier la.instinctual.PLANK.AgentRegistryTest "$output/agent-registry"
codesign --verify --strict "$output/agent-registry"
"$output/agent-registry" --synthetic
xcrun --sdk macosx clang -mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror \
    -Ihost/macos/session -Iprobes/macos host/macos/session/agent-registry.m \
    host/macos/session/agent-connection.m tests/auth/macos-agent-service.m \
    -framework Foundation -framework Security -framework SystemConfiguration -framework CoreGraphics \
    -o "$output/agent-peer"
codesign --force --sign - --identifier la.instinctual.PLANK.AgentServiceTest "$output/agent-peer"
codesign --verify --strict "$output/agent-peer"
shasum -a 256 host/macos/session/agent-registry.{h,m} host/macos/session/agent-connection.{h,m} \
    tests/auth/macos-agent-registry.m tests/auth/macos-agent-service.m "$output/agent-registry" "$output/agent-peer"
