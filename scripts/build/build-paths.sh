#!/usr/bin/env bash
# Source before compilation. Map diagnostics, not live filesystem accesses.
plank_build_path_flags() {
    local source_root=$1 build_root=$2 mapping path label
    local maps=()
    # Broad roots first: both GCC/Clang and rustc give later mappings priority.
    maps+=("${HOME:?}=/build/user")
    [[ -z ${PLANK_DEP_ROOT:-} ]] || maps+=("$PLANK_DEP_ROOT=/build/dependencies")
    [[ -z ${PLANK_MAC_CLIENT_DEPS:-} ]] || maps+=("$PLANK_MAC_CLIENT_DEPS=/build/dependencies")
    [[ -z ${CARGO_HOME:-} ]] || maps+=("$CARGO_HOME=/build/cargo")
    [[ -z ${RUSTUP_HOME:-} ]] || maps+=("$RUSTUP_HOME=/build/rustup")
    maps+=("$source_root=/build/plank/source" "$build_root=/build/plank/work")
    PLANK_FILE_FLAGS=()
    [[ -z ${CARGO_ENCODED_RUSTFLAGS:-} ]] || {
        echo 'CARGO_ENCODED_RUSTFLAGS overrides the required path mappings; use RUSTFLAGS instead' >&2
        return 1
    }
    for mapping in "${maps[@]}"; do
        path=${mapping%=*}; label=${mapping##*=}
        # qmake/Cargo flag strings cannot safely represent arbitrary shell paths.
        [[ $path == /* && $path != / && $path != *[[:space:]\"\'\=]* ]] || {
            echo 'Build roots must be absolute, non-root paths without whitespace, quotes or equals signs' >&2
            return 1
        }
        PLANK_FILE_FLAGS+=("-ffile-prefix-map=$path=$label")
        RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }--remap-path-prefix=$path=$label"
    done
    PLANK_C_FILE_FLAGS="${PLANK_FILE_FLAGS[*]}"
    export RUSTFLAGS
}

# Cargo's cc-rs native dependencies do not consume RUSTFLAGS. Apply the same
# diagnostic mapping to their C/C++ objects; do not change optimization flags.
plank_native_dependency_flags() {
    # Never export plain CFLAGS/CXXFLAGS: Make would export qmake's replacement
    # values into Cargo too, including C-only forced headers on assembly files.
    export HOST_CFLAGS="${HOST_CFLAGS:+$HOST_CFLAGS }$PLANK_C_FILE_FLAGS"
    export TARGET_CFLAGS="${TARGET_CFLAGS:+$TARGET_CFLAGS }$PLANK_C_FILE_FLAGS"
    export HOST_CXXFLAGS="${HOST_CXXFLAGS:+$HOST_CXXFLAGS }$PLANK_C_FILE_FLAGS"
    export TARGET_CXXFLAGS="${TARGET_CXXFLAGS:+$TARGET_CXXFLAGS }$PLANK_C_FILE_FLAGS"
}
