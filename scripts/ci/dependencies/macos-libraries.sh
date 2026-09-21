#!/usr/bin/env bash
# These libraries share one install prefix and are cached together, without Qt.
set -euo pipefail
export PLANK_MAC_CLIENT_DEPS="$PLANK_DEP_ROOT/macos-client"
if [[ ! -f "$PLANK_MAC_CLIENT_DEPS/install/lib/libavcodec.dylib" ]]; then
  bash "$PLANK_SOURCE_ROOT/scripts/build/bootstrap-macos-client-deps.sh"
fi
