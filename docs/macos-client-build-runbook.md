# macOS Client build inputs and procedure

Experimental Apple Silicon/macOS27 only. Read the canonical release runbook
first. Linux builder/test roles remain unchanged. Use clean Git worktrees and
verified Git bundles imported dependency-first, with recursive fetch disabled.

The dedicated Mac retains its canonical clone under `~/dev/plank` and private
inputs under `~/Library/Caches/plank-build`. Export these machine-specific
values explicitly; never infer a path from an old candidate directory:

```bash
export PLANK_CANONICAL_ROOT="$HOME/dev/plank"
export PLANK_DEP_ROOT="$HOME/Library/Caches/plank-build"
export PLANK_WORK_ROOT="$PLANK_DEP_ROOT/work"
export PLANK_MAC_CLIENT_DEPS="$PLANK_DEP_ROOT/macos-client-deps"
export PLANK_QT_ROOT="$PLANK_DEP_ROOT/qt-6.10.2/6.10.2/macos"
export PLANK_RUSTUP_ROOT="$PLANK_DEP_ROOT/rustup-1.89.0"
export PLANK_CARGO_ROOT="$PLANK_DEP_ROOT/cargo"
export PLANK_BUILD_BRANCH=macos-client
```

Bootstrap Qt once with a private Python venv and aqtinstall3.3.0:

```bash
python3 -m venv "$PLANK_DEP_ROOT/bootstrap/aqt-3.3.0"
"$PLANK_DEP_ROOT/bootstrap/aqt-3.3.0/bin/pip" install aqtinstall==3.3.0
"$PLANK_DEP_ROOT/bootstrap/aqt-3.3.0/bin/aqt" install-qt mac desktop \
  6.10.2 clang_64 --outputdir "$PLANK_DEP_ROOT/qt-6.10.2" \
  --archives qtbase qtdeclarative qtsvg qttools qtshadertools
```

Official Qt archives contain both architectures; product builds select arm64.
The installer verifies the upstream archive checksums. Retain its installation
log and Python dependency inventory. No Homebrew dependency on moving versions.

Set `PLANK_SOURCE_ROOT` to a complete source checkout with the exact Client
gitlink initialized BEFORE preparing FFmpeg. Then run:

```bash
bash "$PLANK_SOURCE_ROOT/scripts/bootstrap-macos-client-deps.sh"
```

The script pins archive SHA256 values and prepares private OpenSSL3.5.5,
Opus1.5.2, SDL3.4.2, SDL_ttf3.2.2, FreeType2.14.1 and FFmpeg9.0.1. It applies
the same required HEVC identity-GBR patch as Linux (also enables VideoToolbox
format probing). A missing Client checkout is an input-preflight error, not a
compiler failure. `ffmpeg` as the optional argument resumes only that stage.
Candidate builds must independently reverse-dry-run that patch and verify its
hash. Private dylibs must be bundled with relocatable install names, licensed,
signed and closure-checked before any package is offered to a user.

Implementation/qualification is in progress; there is no accepted macOS Client
package yet. Do not use the old upstream setup-deps/prebuilts workflow.
