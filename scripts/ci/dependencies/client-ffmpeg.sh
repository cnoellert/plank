#!/usr/bin/env bash
set -euo pipefail
if [[ ! -f "$PLANK_DEP_ROOT/client-ffmpeg/install/lib/libavcodec.so" ]]; then
  bash "$PLANK_SOURCE_ROOT/scripts/build/build-client-ffmpeg.sh" "$PLANK_WORK_ROOT/ffmpeg-stage" "$PLANK_DEP_ROOT/client-ffmpeg"
fi
