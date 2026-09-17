# Dependency Patch Inventory

PLANK treats dependency patches as versioned source inputs. A candidate build
must not depend on an old builder directory having been modified manually.
For every active patch, bootstrap applies it explicitly and package preflight
independently proves that the prepared source contains it.

## Active Linux product patches

### Client private FFmpeg

`apps/client/app/deploy/linux/ffmpeg-patches/0001-hevc-enable-hwaccel-for-identity-gbr.patch`
allows FFmpeg's HEVC hardware decoder selection to retain VA-API for PLANK's
identity-matrix GBR/GBR10 streams. It is required for the qualified HEVC Rext
10-bit 4:4:4 Y410/XR30 path.

- `scripts/build/build-client-ffmpeg.sh` checksum-verifies and applies it. A patch
  that is neither applicable nor already applied is fatal.
- `scripts/build/build-client-package-binaries.sh` checksum-verifies it again and
  proves it reverses cleanly from the prepared FFmpeg source before qmake.
  Both stages reject patch backup (`*.orig`) and reject (`*.rej`) residue.
  Package preflight also compares the complete prepared source against the
  checksum-pinned FFmpeg archive, permits only the patched `hevcdec.c`, and
  verifies the exact expected post-patch hash of that file.

### Host build-deps FFmpeg family

`apps/host/linux/third-party/build-deps/patches/` contains the patches
selected by the retained Host FFmpeg dependency configuration. Its
`APPLY_GIT_PATCH` helper performs a forward check and application, or proves
the exact patch is already present with a reverse check. Any other result is
fatal. `scripts/build/build-host-package-binaries.sh` independently requires this
fail-closed contract before configuring a package build.
`scripts/build/verify-host-dependency-patches.sh` also proves that the generated
dependency worktrees contain exactly the tracked files named by those patches,
with no additional tracked source modifications or patch residue.
The Loader source copy intentionally omits its upstream `tests/` directory;
the verifier allows only tracked deletions there, not modified tests or deleted
production source.

The Vulkan Loader 1.4.362 candidate also requires
`patches/FFmpeg/Vulkan-Loader/01-handle-id-filter-allocation-failure.patch`.
It propagates ID-filter allocation failure as `VK_ERROR_OUT_OF_HOST_MEMORY`
through both physical-device enumeration APIs and their cleanup paths. It is
applied even when optional FFmpeg patches are disabled. Bootstrap/cache/package
preflight independently verifies the generated Loader source; the separate
upstream-framework test patch is not applied to production dependency sources.
Run `tests/packaging/test-host-dependency-patches.py` to check that stale,
unpatched, incompatible or unexpectedly modified prepared sources are rejected.

The active selection is controlled by the pinned build-deps CMake options and
therefore may include patches for FFmpeg CBS, AMF, Vulkan, x264 integration,
x265 integration/source, NV codec headers, libva, or SVT-AV1. The PLANK Host
bootstrap configuration is the authority for which members are selected; no
selected member may be silently skipped.

## Present but inactive for qualified RPM/DEB packages

- `apps/client/app/deploy/linux/appimage/` contains an AppImage
  libplacebo patch. PLANK does not build or publish AppImages; the Ubuntu DEB
  uses its qualified system libplacebo.
- `apps/host/linux/packaging/linux/patches/{aarch64,x86_64}/` contains CUDA
  compatibility patches for inherited generic/COPR packaging. The canonical
  PLANK RPM build does not invoke those packaging paths.
- Patch files embedded inside third-party source repositories, such as
  SVT-AV1's own CI/plugin examples, are upstream project content and are not
  PLANK build inputs unless the pinned build-deps configuration selects them.

If any currently inactive packaging path becomes supported, move its patches
into the active inventory and add both an application check and an independent
package preflight before shipping it.

## Pinned dependencies without PLANK patches

- Boost 1.89.0 is extracted from its SHA-256-pinned release archive and is not
  patched. The 2026-09-02 audit compared the retained source recursively with
  a fresh extraction and found no differences.
- Rust dependencies resolve from committed lockfiles and the retained Cargo
  cache with `--locked --offline`; there is no post-fetch source mutation.
- Kymux, common-c, qmdnsengine, and Host recursive dependencies are exact Git
  links. Candidate setup seeds those commits from canonical repositories or
  verified bundles and requires clean worktrees.
- Qt, SDL3, libplacebo, and the remaining Client development/runtime inputs
  are qualified Ubuntu packages. Their versions and runtime closure are
  package gates; PLANK does not patch their installed files.

The absence of a patch does not permit a manually modified prepared source.
If a dependency needs a product change, add a tracked patch (or a maintained
fork commit), document it here, and add an independent package gate in the
same change.
