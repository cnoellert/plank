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

## Build and package

Initialize Client, common-c, qmdnsengine and Kymux at their exact gitlinks from
verified local Git bundles/mirrors. Do not initialize the Linux Host to build
this Client. Import Client bundles before root bundles and always fetch with
`--recurse-submodules=no`. The Mac canonical origin may still be an old
bootstrap bundle, so fetching that origin is not a source update.

```bash
bash "$PLANK_SOURCE_ROOT/scripts/build-macos-client.sh" \
  "$PLANK_SOURCE_ROOT" "$PLANK_WORK_ROOT/client-build"
```

For a self-contained drag-to-Applications DMG, in the signing SSH session:

```bash
export PLANK_MACOS_SIGNING_IDENTITY=DEVELOPER_ID_APPLICATION_SHA1
export PLANK_NOTARY_PROFILE=plank-notary
bash "$PLANK_SOURCE_ROOT/scripts/build-macos-client-dmg.sh" \
  "$PLANK_SOURCE_ROOT" "$PLANK_WORK_ROOT/client-package"
```

Output must be a new directory. An optional absolute `PLANK_MAC_CLIENT_BUILD`
may point to a retained build; qmake/make still run, and staging/closure/signing
are fresh. Unlock the signing keychain interactively in that SSH session, not
by putting a password in arguments, environment, scripts or notes. Preserve
the session through signing. DMG must pass notarization, staple and Gatekeeper;
transfer the exact file to `artifacts/packages` and compare SHA256 on both ends.
No installer service/autostart is created; uninstall by quitting and moving
the app to Trash. Host installation/permissions are separate and unchanged.

## Known failure signatures

- Rust1.89 proc macros fail under SDK27 stripping: retain `RUSTFLAGS=-C
  strip=none`, as for the Host. Missing macros here need not mean missing Cargo
  inputs; do not redownload them blindly.
- Private pkgconf filters its own prefix as system flags: require
  `PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1` and `PKG_CONFIG_ALLOW_SYSTEM_LIBS=1`.
- Qt6.10.2/SDK27 Clang21 `__yield` declaration: the Mac arm64 build includes
  `arm_acle.h` explicitly. Do not change Linux compiler flags.
- FreeType's optional zlib pkgconfig dependency is not available from the SDK:
  bootstrap disables that optional compression backend; SDL_ttf fonts work
  through retained FreeType. Do not introduce a moving Homebrew dependency.
- macdeployqt includes unrelated server-database plugins referencing
  `/opt/homebrew` or `/usr/local`: package only SQLite in the SQL plugin
  directory. Every retained Mach-O still passes the external dependency gate.
- Bash3.2 plus nounset rejects an empty feature array: use the guarded array
  expansion in `build-macos-transport.sh`; default Client features are valid.
- Headless version/help checks use `QT_QPA_PLATFORM=offscreen`. A real GUI
  session is needed for functional presentation/input acceptance.
- `macdeployqt` normally ships only Cocoa. Explicitly retain the offscreen
  plugin for the packaged headless gate; do not skip a failed launch check.
- A retained build requires **recursive** `qmake -r` regeneration. Without it,
  subproject Makefiles can retain the previous source path and compiled
  version despite a correct new Info.plist. The independent executable-version
  gate caught this during .94 packaging. Never relabel that older binary;
  regenerate all subprojects and rebuild before signing.
- Qt's SecureTransport backend rejects TLS1.3 with `Failed to set protocol
  version`/network error99. Mac startup must select the bundled OpenSSL backend
  and require TLS1.3 support before opening network requests. A file-closure
  check and a version string alone do not prove authentication works: retain
  the packaged live-connection gate. The unauthenticated
  `tests/video/macos-client-tls.cpp` probe distinguishes backend availability
  from Host reachability without sending credentials. It must run from an app
  bundle when testing bundled OpenSSL lookup (a bare CLI has no Frameworks
  directory for Qt to discover). See the pinned [Qt6.10.2 loader source](https://github.com/qt/qtbase/blob/v6.10.2/src/plugins/tls/openssl/qsslsocket_openssl_symbols.cpp).

Current probes are `tests/video/macos-videotoolbox-decode.mm`,
`macos-hevc444-fixture.m`, and `macos-metal-color.mm`. The last loads the actual
Client Metal shader and shared color uniforms, not a duplicate implementation.
Hardware metadata/GPU math probes do not replace live presentation acceptance.
