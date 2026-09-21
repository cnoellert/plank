#!/usr/bin/env bash
set -euo pipefail
boost="$PLANK_DEP_ROOT/boost-1.89.0"
if [[ ! -f "$boost/CMakeLists.txt" ]]; then
  archive="$PLANK_DEP_ROOT/boost-1.89.0-cmake.tar.xz"
  curl --fail --location https://github.com/boostorg/boost/releases/download/boost-1.89.0/boost-1.89.0-cmake.tar.xz -o "$archive"
  echo "67acec02d0d118b5de9eb441f5fb707b3a1cdd884be00ca24b9a73c995511f74  $archive" | sha256sum -c -
  mkdir "$boost"
  tar -xJf "$archive" --strip-components=1 -C "$boost"
fi
