#!/usr/bin/env bash
# Build the real Client; dependencies are separately bootstrapped and retained.
set -euo pipefail
[[ $# == 2 && $1 == /* && $2 == /* ]] || { echo 'usage: build-macos-client.sh SOURCE BUILD' >&2; exit 2; }
source_root=$1
build=$2
: "${PLANK_MAC_CLIENT_DEPS:?}"
: "${PLANK_QT_ROOT:?}"
: "${PLANK_RUSTUP_ROOT:?}"
: "${PLANK_CARGO_ROOT:?}"
: "${PLANK_BUILD_BRANCH:?Detached builds require an explicit branch}"
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || exit 2
export MACOSX_DEPLOYMENT_TARGET=27.0
export SDKROOT
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
[[ $(xcrun --sdk macosx --show-sdk-version) == 27* ]] || exit 2
export CARGO_HOME="$PLANK_CARGO_ROOT" RUSTUP_HOME="$PLANK_RUSTUP_ROOT"
export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }-C strip=none" # SDK27 proc-macro guard.
source "$source_root/scripts/build/build-paths.sh"
plank_build_path_flags "$source_root" "$build"
plank_native_dependency_flags
export PATH="$PLANK_QT_ROOT/bin:$PLANK_MAC_CLIENT_DEPS/install/bin:$CARGO_HOME/bin:$PATH"
export PKG_CONFIG_PATH="$PLANK_MAC_CLIENT_DEPS/install/lib/pkgconfig"
# pkgconf itself lives in this prefix; its compiled-in "system" directories
# are private inputs, not compiler defaults, so they must not be filtered out.
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1 PKG_CONFIG_ALLOW_SYSTEM_LIBS=1
source "$source_root/scripts/package/package-version.sh"
plank_load_package_version "$source_root"
version=$PLANK_PACKAGE_VERSION
client="$source_root/apps/client"
test "$(qmake -query QT_VERSION)" = 6.10.2
test "$(rustc --version | awk '{print $2}')" = 1.89.0
python3 "$source_root/tests/packaging/test-macos-fullscreen.py" "$source_root"
patch_file="$client/app/deploy/linux/ffmpeg-patches/0001-hevc-enable-hwaccel-for-identity-gbr.patch"
printf '%s  %s\n' 059cc9c0d585d71e292cd7421a43f239b1e7ce94e8598d0a7427dfe48e55847e "$patch_file" | shasum -a 256 -c -
patch --batch --reverse --dry-run -d "$PLANK_MAC_CLIENT_DEPS/src/ffmpeg-9.0.1" -p1 < "$patch_file"
pkg-config --modversion sdl3 sdl3-ttf openssl opus libavcodec libavutil
mkdir -p "$build"
cd "$build"
# Recursive generation is mandatory when retaining a build: otherwise existing
# subproject Makefiles may silently retain the previous source/version/flags.
qmake -r "$client/moonlight-qt.pro" CONFIG+=release CONFIG+=disable-prebuilts \
    CONFIG+=plank-transport CONFIG+=disable-libplacebo CONFIG+=disable-wayland \
    CONFIG+=disable-x11 CONFIG+=disable-libva CONFIG+=disable-libdrm \
    QMAKE_MACOSX_DEPLOYMENT_TARGET=27.0 QMAKE_APPLE_DEVICE_ARCHS=arm64 \
    PLANK_VERSION="$version" \
    "QMAKE_CFLAGS+=$PLANK_C_FILE_FLAGS" "QMAKE_CXXFLAGS+=$PLANK_C_FILE_FLAGS"
make -j"${PLANK_BUILD_JOBS:-8}" release
# Run shared topology and toolbar geometry on every Mac Client candidate.
for suite in outputtopology planktoolbarlogic desktopstage macquitshortcut; do
mkdir -p "$build/tests/$suite"
(
    cd "$build/tests/$suite"
    qmake "$client/tests/$suite/$suite.pro" CONFIG+=release CONFIG-=app_bundle \
        QMAKE_MACOSX_DEPLOYMENT_TARGET=27.0 QMAKE_APPLE_DEVICE_ARCHS=arm64 \
        "QMAKE_CXXFLAGS+=-include arm_acle.h"
    make -j"${PLANK_BUILD_JOBS:-8}"
    PLANK_REPO_ROOT="$source_root" QT_QPA_PLATFORM=offscreen "./$suite"
)
done
plist="$build/app/plank-client.app/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :NSPrefersDisplaySafeAreaCompatibilityMode' "$plist")" = false
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $PLANK_BASE_VERSION" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $PLANK_BASE_VERSION" "$plist"
if /usr/libexec/PlistBuddy -c 'Print :PLANKVersion' "$plist" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :PLANKVersion $version" "$plist"
else
    /usr/libexec/PlistBuddy -c "Add :PLANKVersion string $version" "$plist"
fi
