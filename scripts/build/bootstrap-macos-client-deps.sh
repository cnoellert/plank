#!/usr/bin/env bash
# Private, pinned Apple Silicon inputs; never installs into /usr or /Applications.
set -euo pipefail
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || exit 2
: "${PLANK_MAC_CLIENT_DEPS:?Set the private dependency root}"
: "${PLANK_SOURCE_ROOT:?Set the source checkout}"
export MACOSX_DEPLOYMENT_TARGET=27.0
export SDKROOT
SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
[[ $(xcrun --sdk macosx --show-sdk-version) == 27* ]] || exit 2
prefix="$PLANK_MAC_CLIENT_DEPS/install"
mkdir -p "$PLANK_MAC_CLIENT_DEPS/downloads" "$PLANK_MAC_CLIENT_DEPS/src" "$prefix"
export PATH="$prefix/bin:/Applications/CMake.app/Contents/bin:$PATH"
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"
jobs=${PLANK_BUILD_JOBS:-8}
[[ $jobs =~ ^[1-9][0-9]*$ ]] || exit 2
source "$PLANK_SOURCE_ROOT/scripts/build/build-paths.sh"
plank_build_path_flags "$PLANK_SOURCE_ROOT" "$PLANK_MAC_CLIENT_DEPS"

fetch() {
    local url=$1 hash=$2 name=${1##*/}
    local archive="$PLANK_MAC_CLIENT_DEPS/downloads/$name"
    [[ -f $archive ]] || curl --fail --location --output "$archive" "$url"
    printf '%s  %s\n' "$hash" "$archive" | shasum -a 256 -c -
    tar -xf "$archive" -C "$PLANK_MAC_CLIENT_DEPS/src"
}
cmake_build() {
    local name=$1
    shift
    cmake -S "$PLANK_MAC_CLIENT_DEPS/src/$name" -B "$PLANK_MAC_CLIENT_DEPS/build-$name" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
        "-DCMAKE_C_FLAGS=$PLANK_C_FILE_FLAGS" "-DCMAKE_CXX_FLAGS=$PLANK_C_FILE_FLAGS" \
        -DCMAKE_PREFIX_PATH="$prefix" -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=27.0 -DBUILD_SHARED_LIBS=ON "$@"
    cmake --build "$PLANK_MAC_CLIENT_DEPS/build-$name" --parallel "$jobs"
    cmake --install "$PLANK_MAC_CLIENT_DEPS/build-$name"
}

if [[ ${1:-all} == all ]]; then
fetch https://distfiles.ariadne.space/pkgconf/pkgconf-2.5.1.tar.xz cd05c9589b9f86ecf044c10a2269822bc9eb001eced2582cfffd658b0a50c243
(
    cd "$PLANK_MAC_CLIENT_DEPS/src/pkgconf-2.5.1"
    ./configure --prefix="$prefix" --disable-shared
    make -j"$jobs"
    make install
    ln -sf pkgconf "$prefix/bin/pkg-config"
)
fetch https://github.com/openssl/openssl/releases/download/openssl-3.5.5/openssl-3.5.5.tar.gz b28c91532a8b65a1f983b4c28b7488174e4a01008e29ce8e69bd789f28bc2a89
(
    cd "$PLANK_MAC_CLIENT_DEPS/src/openssl-3.5.5"
    # Runtime defaults must never point into a builder's writable home. Stage
    # the conventional install tree, then relocate only development link/pc
    # metadata. Do not bundle config, engines or optional provider modules.
    openssl_prefix=/usr/local/lib/plank-client
    openssl_stage="$PLANK_MAC_CLIENT_DEPS/openssl-stage"
    ./Configure darwin64-arm64-cc --prefix="$openssl_prefix" \
        --openssldir=/etc/plank/openssl shared no-tests
    make -j"$jobs"
    make install_sw DESTDIR="$openssl_stage"
    cp -R "$openssl_stage$openssl_prefix/." "$prefix/"
    python3 "$PLANK_SOURCE_ROOT/scripts/build/relocate-openssl-pc.py" "$prefix" "$openssl_prefix"
    for library in libcrypto.3.dylib libssl.3.dylib; do
        install_name_tool -id "$prefix/lib/$library" "$prefix/lib/$library"
    done
    install_name_tool -change "$openssl_prefix/lib/libcrypto.3.dylib" \
        "$prefix/lib/libcrypto.3.dylib" "$prefix/lib/libssl.3.dylib"
)
fetch https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz 65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1
cmake_build opus-1.5.2 -DOPUS_BUILD_TESTING=OFF -DOPUS_BUILD_PROGRAMS=OFF
fetch https://libsdl.org/release/SDL3-3.4.2.tar.gz ef39a2e3f9a8a78296c40da701967dd1b0d0d6e267e483863ce70f8a03b4050c
cmake_build SDL3-3.4.2 -DSDL_TESTS=OFF -DSDL_TEST_LIBRARY=OFF -DSDL_SHARED=ON -DSDL_STATIC=OFF
fetch https://download.savannah.gnu.org/releases/freetype/freetype-2.14.1.tar.xz 32427e8c471ac095853212a37aef816c60b42052d4d9e48230bab3bdf2936ccc
cmake_build freetype-2.14.1 -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_PNG=ON -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_ZLIB=ON
fetch https://github.com/libsdl-org/SDL_ttf/releases/download/release-3.2.2/SDL3_ttf-3.2.2.tar.gz 63547d58d0185c833213885b635a2c0548201cc8f301e6587c0be1a67e1e045d
cmake_build SDL3_ttf-3.2.2 -DSDLTTF_VENDORED=OFF -DSDLTTF_HARFBUZZ=OFF -DSDLTTF_SAMPLES=OFF
elif [[ $1 != ffmpeg ]]; then
    echo 'usage: bootstrap-macos-client-deps.sh [all|ffmpeg]' >&2
    exit 2
fi
fetch https://ffmpeg.org/releases/ffmpeg-9.0.1.tar.xz cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635
ffmpeg_source="$PLANK_MAC_CLIENT_DEPS/src/ffmpeg-9.0.1"
identity_patch="$PLANK_SOURCE_ROOT/apps/client/app/deploy/linux/ffmpeg-patches/0001-hevc-enable-hwaccel-for-identity-gbr.patch"
printf '%s  %s\n' 059cc9c0d585d71e292cd7421a43f239b1e7ce94e8598d0a7427dfe48e55847e "$identity_patch" | shasum -a 256 -c -
patch --batch --forward -d "$ffmpeg_source" -p1 < "$identity_patch"
patch --batch --reverse --dry-run -d "$ffmpeg_source" -p1 < "$identity_patch"
mkdir -p "$PLANK_MAC_CLIENT_DEPS/build-ffmpeg"
(
    cd "$PLANK_MAC_CLIENT_DEPS/build-ffmpeg"
    "$ffmpeg_source/configure" --prefix="$prefix" --enable-shared --disable-static \
        --disable-doc --disable-debug --disable-autodetect --enable-videotoolbox \
        --enable-audiotoolbox --enable-neon --arch=arm64 --target-os=darwin \
        --extra-cflags="$PLANK_C_FILE_FLAGS"
    python3 "$PLANK_SOURCE_ROOT/scripts/build/sanitize-ffmpeg-build-info.py" \
        config.h "$PLANK_MAC_CLIENT_DEPS" "$PLANK_SOURCE_ROOT" "$HOME"
    make -j"$jobs"
    make install
)
pkg-config --modversion sdl3 sdl3-ttf openssl opus libavcodec libavutil
