#!/usr/bin/env bash
# Bootstrap only pinned inputs, then use the normal product build entrypoints.
set -euo pipefail
role=${1:?linux-host, linux-client, macos-host or macos-client}
: "${PLANK_SOURCE_ROOT:?}" "${PLANK_DEP_ROOT:?}" "${PLANK_WORK_ROOT:?}"
mkdir -p "$PLANK_DEP_ROOT" "$PLANK_WORK_ROOT"
case $role in
  linux-host) product=apps/host/linux; target=x86_64-unknown-linux-gnu ;;
  linux-client) product=apps/client; target=x86_64-unknown-linux-gnu ;;
  macos-host) product=; target=aarch64-apple-darwin ;;
  macos-client) product=apps/client; target=aarch64-apple-darwin ;;
  *) exit 2 ;;
esac
git -C "$PLANK_SOURCE_ROOT" submodule update --init third_party/kyber-kymux
if [[ -n $product ]]; then
  git -C "$PLANK_SOURCE_ROOT" submodule update --init --recursive "$product"
fi
export CARGO_HOME="$PLANK_CARGO_ROOT" RUSTUP_HOME="$PLANK_RUSTUP_ROOT"
export PATH="$CARGO_HOME/bin:$PATH"
if [[ ! -x "$CARGO_HOME/bin/rustup" ]]; then
  installer="$PLANK_DEP_ROOT/rustup-bootstrap"
  mkdir -p "$installer"
  curl --fail --location "https://static.rust-lang.org/rustup/archive/1.28.2/$target/rustup-init" -o "$installer/rustup-init"
  curl --fail --location "https://static.rust-lang.org/rustup/archive/1.28.2/$target/rustup-init.sha256" -o "$installer/rustup-init.sha256"
  if [[ $target == *linux* ]]; then
    (cd "$installer"; sha256sum -c rustup-init.sha256)
  else
    (cd "$installer"; shasum -a 256 -c rustup-init.sha256)
  fi
  chmod 0755 "$installer/rustup-init"
  RUSTUP_INIT_SKIP_PATH_CHECK=yes "$installer/rustup-init" -y --no-modify-path --profile minimal --default-toolchain 1.89.0
fi
test "$(rustc --version)" = 'rustc 1.89.0 (29483883e 2025-08-04)'
test "$(cargo --version)" = 'cargo 1.89.0 (c24e10642 2025-06-23)'
cargo fetch --locked --target "$target" --manifest-path "$PLANK_SOURCE_ROOT/protocol/plank-transport/Cargo.toml"
if [[ $role == linux-host ]]; then
  # Standalone vendor unit tests have their own pinned test-only dependencies.
  cargo fetch --locked --target "$target" --manifest-path "$PLANK_SOURCE_ROOT/third_party/quinn-proto-0.11.17/Cargo.toml"
fi
case $role in
  linux-host)
    boost="$PLANK_DEP_ROOT/boost-1.89.0"
    if [[ ! -f "$boost/CMakeLists.txt" ]]; then
      archive="$PLANK_DEP_ROOT/boost-1.89.0-cmake.tar.xz"
      curl --fail --location https://github.com/boostorg/boost/releases/download/boost-1.89.0/boost-1.89.0-cmake.tar.xz -o "$archive"
      echo "67acec02d0d118b5de9eb441f5fb707b3a1cdd884be00ca24b9a73c995511f74  $archive" | sha256sum -c -
      mkdir "$boost"
      tar -xJf "$archive" --strip-components=1 -C "$boost"
    fi
    deps="$PLANK_SOURCE_ROOT/apps/host/linux/third-party/build-deps"
    ffmpeg="$PLANK_DEP_ROOT/host-ffmpeg"
    if [[ ! -f "$ffmpeg/lib/libavcodec.a" ]]; then
      cmake -S "$deps" -B "$deps/build" -DBUILD_ALL=OFF -DBUILD_FFMPEG=ON \
        -DBUILD_FFMPEG_SVT_AV1=OFF -DCMAKE_C_COMPILER=/opt/rh/gcc-toolset-14/root/usr/bin/gcc \
        -DCMAKE_CXX_COMPILER=/opt/rh/gcc-toolset-14/root/usr/bin/g++ \
        -DCMAKE_INSTALL_LIBDIR=lib -DFFMPEG_INSTALL_PREFIX="$ffmpeg" \
        -DPARALLEL_BUILDS="${PLANK_BUILD_JOBS:-4}"
      cmake --build "$deps/build" --parallel "${PLANK_BUILD_JOBS:-4}"
      cmake --install "$deps/build"
    fi
    bash "$PLANK_SOURCE_ROOT/scripts/build/verify-host-dependency-patches.sh" "$deps/build"
    ;;
  linux-client)
    if [[ ! -f "$PLANK_DEP_ROOT/client-ffmpeg/install/lib/libavcodec.so" ]]; then
      bash "$PLANK_SOURCE_ROOT/scripts/build/build-client-ffmpeg.sh" "$PLANK_WORK_ROOT/ffmpeg-stage" "$PLANK_DEP_ROOT/client-ffmpeg"
    fi
    ;;
  macos-*)
    test "$(uname -m)" = arm64
    test "$(sw_vers -productVersion | cut -d . -f 1)" -ge 27
    test "$(xcrun --sdk macosx --show-sdk-version | cut -d . -f 1)" -ge 27
    if [[ $role = macos-client ]]; then
      export PLANK_MAC_CLIENT_DEPS="$PLANK_DEP_ROOT/macos-client"
      if [[ ! -f "$PLANK_MAC_CLIENT_DEPS/install/lib/libavcodec.dylib" ]]; then
        bash "$PLANK_SOURCE_ROOT/scripts/build/bootstrap-macos-client-deps.sh"
      fi
      if [[ ! -x "$PLANK_DEP_ROOT/qt/6.10.2/macos/bin/qmake" ]]; then
        python3 -m venv "$PLANK_DEP_ROOT/aqt"
        "$PLANK_DEP_ROOT/aqt/bin/pip" install aqtinstall==3.3.0
        "$PLANK_DEP_ROOT/aqt/bin/aqt" install-qt mac desktop 6.10.2 clang_64 \
          --outputdir "$PLANK_DEP_ROOT/qt" --archives qtbase qtdeclarative qtsvg qttools qtshadertools
      fi
    fi
    ;;
esac
test -z "$(git -C "$PLANK_SOURCE_ROOT" status --porcelain)"
echo 'hosted_bootstrap_gate=pass'
