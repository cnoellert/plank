#!/usr/bin/env bash
# Required pinned SDL source patch, used by bootstrap and independent preflight.
set -euo pipefail
[[ $# == 3 && ( $1 == apply || $1 == verify ) ]] || exit 2
operation=$1
source_root=$2
dependency_root=$3
sdl_source="$dependency_root/src/SDL3-3.4.2"
patch_file="$source_root/apps/client/app/deploy/macos/sdl-patches/0001-cocoa-opt-in-full-display-content-size.patch"
test -f "$sdl_source/src/video/cocoa/SDL_cocoawindow.m"
test -s "$patch_file"
if [[ $operation == apply ]]; then
    if patch --batch --forward --dry-run --fuzz=0 -d "$sdl_source" -p1 < "$patch_file"; then
        patch --batch --forward --fuzz=0 -d "$sdl_source" -p1 < "$patch_file"
    else
        # Only an exact already-applied patch is acceptable; never ignore a mismatch.
        patch --batch --reverse --dry-run --fuzz=0 -d "$sdl_source" -p1 < "$patch_file"
    fi
fi
patch --batch --reverse --dry-run --fuzz=0 -d "$sdl_source" -p1 < "$patch_file"
if [[ $operation == verify ]]; then
    # Also reject old installed libraries beside a newly patched source tree.
    LC_ALL=C grep -a -q 'PLANK native fullscreen content:' "$dependency_root/install/lib/libSDL3.dylib"
fi
