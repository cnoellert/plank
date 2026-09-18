#!/usr/bin/env bash
# Source from Mac Client entrypoints. Host deployment policy is independent.
plank_macos_client_target() {
    # Deployment floor is independent of the SDK: retain modern APIs in one
    # binary, with runtime availability checks for anything newer than macOS15.
    PLANK_MAC_CLIENT_MIN_MACOS=${PLANK_MAC_CLIENT_MIN_MACOS:-15.0}
    [[ $PLANK_MAC_CLIENT_MIN_MACOS == 15.0 ]] || {
        echo 'PLANK Client deployment target must be 15.0' >&2; return 2;
    }
    [[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || {
        echo 'The Mac Client requires an Apple Silicon builder' >&2; return 2;
    }
    local sdk_version
    sdk_version=$(xcrun --sdk macosx --show-sdk-version) || return
    [[ $sdk_version =~ ^[0-9]+(\.[0-9]+)*$ ]] || {
        echo 'Cannot determine macOS SDK version' >&2; return 2;
    }
    [[ ${sdk_version%%.*} -ge 27 ]] || {
        echo "PLANK Client requires SDK27 or newer, found $sdk_version" >&2
        return 2
    }
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path) || return
    MACOSX_DEPLOYMENT_TARGET=$PLANK_MAC_CLIENT_MIN_MACOS
    export PLANK_MAC_CLIENT_MIN_MACOS MACOSX_DEPLOYMENT_TARGET SDKROOT
}
