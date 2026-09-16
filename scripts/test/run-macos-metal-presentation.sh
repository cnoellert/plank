#!/usr/bin/env bash
# Explicit native desktop GPU test; not a headless builder/package gate.
set -euo pipefail
[[ $# -ge 2 && $# -le 3 && $1 == /* && $2 == /* ]] || {
    echo 'usage: run-macos-metal-presentation.sh SOURCE BUILD [--fullscreen]' >&2; exit 2;
}
source_root=$1
build=$2
[[ $# == 2 || $3 == --fullscreen ]] || exit 2
: "${PLANK_QT_ROOT:?}"
: "${PLANK_MAC_CLIENT_DEPS:?}"
source "$source_root/scripts/build/macos-client-target.sh"
plank_macos_client_target
export PATH="$PLANK_QT_ROOT/bin:$PLANK_MAC_CLIENT_DEPS/install/bin:$PATH"
export PKG_CONFIG_PATH="$PLANK_MAC_CLIENT_DEPS/install/lib/pkgconfig"
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1 PKG_CONFIG_ALLOW_SYSTEM_LIBS=1
mkdir -p "$build"
cd "$build"
qmake "$source_root/apps/client/tests/metalpresentation/metalpresentation.pro" \
    CONFIG+=release QMAKE_MACOSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
    QMAKE_APPLE_DEVICE_ARCHS=arm64 'QMAKE_CXXFLAGS+=-include arm_acle.h'
make -j"${PLANK_BUILD_JOBS:-8}"
export PLANK_TEST_DATA_DIR="$source_root/apps/client/app/shaders"
export MTL_DEBUG_LAYER=1
./metalpresentation "${@:3}"
