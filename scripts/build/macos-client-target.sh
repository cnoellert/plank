#!/usr/bin/env bash
# Source from Mac Client entrypoints. Host deployment policy is independent.
plank_macos_client_target() {
    PLANK_MAC_CLIENT_MIN_MACOS=${PLANK_MAC_CLIENT_MIN_MACOS:-27.0}
    case "$PLANK_MAC_CLIENT_MIN_MACOS" in
        15.0|27.0) ;;
        *) echo 'PLANK_MAC_CLIENT_MIN_MACOS must be 15.0 or 27.0' >&2; return 2 ;;
    esac
    [[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || {
        echo 'The Mac Client requires an Apple Silicon builder' >&2; return 2;
    }
    local sdk_version
    sdk_version=$(xcrun --sdk macosx --show-sdk-version) || return
    [[ $sdk_version =~ ^[0-9]+(\.[0-9]+)*$ ]] || {
        echo 'Cannot determine macOS SDK version' >&2; return 2;
    }
    [[ ${sdk_version%%.*} -ge ${PLANK_MAC_CLIENT_MIN_MACOS%%.*} ]] || {
        echo "SDK $sdk_version is older than the Client target $PLANK_MAC_CLIENT_MIN_MACOS" >&2
        return 2
    }
    SDKROOT=$(xcrun --sdk macosx --show-sdk-path) || return
    MACOSX_DEPLOYMENT_TARGET=$PLANK_MAC_CLIENT_MIN_MACOS
    export PLANK_MAC_CLIENT_MIN_MACOS MACOSX_DEPLOYMENT_TARGET SDKROOT
}
