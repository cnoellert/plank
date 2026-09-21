#!/usr/bin/env bash
set -euo pipefail
if [[ ! -x "$PLANK_DEP_ROOT/qt/6.10.2/macos/bin/qmake" ]]; then
  python3 -m venv "$PLANK_DEP_ROOT/aqt"
  "$PLANK_DEP_ROOT/aqt/bin/pip" install aqtinstall==3.3.0
  "$PLANK_DEP_ROOT/aqt/bin/aqt" install-qt mac desktop 6.10.2 clang_64 \
    --outputdir "$PLANK_DEP_ROOT/qt" --archives qtbase qtdeclarative qtsvg qttools qtshadertools
fi
