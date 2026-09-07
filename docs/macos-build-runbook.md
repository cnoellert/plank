# macOS development build notes

Status: experimental macOS Host; no installable product package yet. Build only
on the authorized dedicated development Mac. Linux builder roles are unchanged.
Require Apple Silicon, macOS 27, SDK 27 and explicit deployment target 27.0.
Probe signing/installation remains documented in `probes/macos/README.md`.

## Transport qualification

The first integration build reuses `protocol/plank-transport` and its exact
Kymux/Quinn sources, Cargo lockfile and Rust 1.89.0. No networking policy change
or macOS-specific transport replacement is implied. Passing this build is not
proof of an authenticated Client connection or media playback.

Use a canonical Git clone and clean worktree, not an archive or copied prepared
source tree. Only initialize `third_party/kyber-kymux` for this gate; neither the
Linux Host nor Client submodule is a transport build input. Seed private commits
using SHA-256-verified Git bundles; do not copy repository credentials to the Mac.
Keep the qualification script outside the clean worktree if it is not committed
yet, and record its hash separately from the source commit.
When cloning the root bundle, pass `--branch macos-host`: a branch-only bundle
does not necessarily carry a usable remote HEAD. Check the actual nested Git
commit against the root gitlink, not just directory presence or registration.

Dedicated-Mac path contract (operator account home is discovered on the Mac):

```bash
export PLANK_CANONICAL_ROOT="$HOME/dev/plank"
export PLANK_DEP_ROOT="$HOME/Library/Caches/plank-build"
export PLANK_WORK_ROOT="$PLANK_DEP_ROOT/work"
export PLANK_CARGO_ROOT="$PLANK_DEP_ROOT/cargo"
export PLANK_RUSTUP_ROOT="$PLANK_DEP_ROOT/rustup-1.89.0"
```

Bootstrap Rust once using the official `rustup-init` Apple Silicon binary and
its SHA-256 file, verifying the digest before execution. Use rustup 1.28.2,
`--profile minimal --default-toolchain 1.89.0 --no-modify-path -y` with the above
Cargo/Rustup directories. Do not edit shell startup files or install as root.
Official source/verification procedure:
[Rustup manual installation](https://rust-lang.github.io/rustup/installation/other.html).
Retain downloads, caches and exact build provenance; do not redownload them for
each build. Do not compile while collecting capture/encoder performance data.

### macOS 27 compiler-plugin loading failure

`can't find crate for tokio_macros` (or `thiserror_impl`/`serde_derive`) can mean
the dylib exists but dyld rejects its stripped LINKEDIT string pool. On the
dedicated Mac, direct dlopen confirmed `mis-aligned LINKEDIT string pool` despite
a valid code signature. This matches
[Rust issue 157750](https://github.com/rust-lang/rust/issues/157750).
The macOS runner sets `RUSTFLAGS=-C strip=none` (appended to any caller flags)
to keep compiler-plugin metadata intact. Do not lower the 27.0 deployment target,
disable signing/security, upgrade dependency versions or redownload caches to
hide this error. Revalidate whether this workaround is needed with a future
qualified toolchain; it does not change the shared Linux build.

Invoke `scripts/build-macos-transport.sh SOURCE_WORKTREE BUILD_DIRECTORY` with
the environment above. It runs locked release build and tests, requires the
pinned Rust version and prints the archive hash. It also compiles the shared
native C ABI loopback test with Apple frameworks and runs exact-fingerprint and
explicit certificate-approval/setup-promotion cases on loopback ports 47489/47490.
Ephemeral certificates/private keys and the loopback executable are removed on
exit. No non-loopback listener, product service or user-installable Host is
created. The test's internal token is synthetic, not a production credential.

The certificate fixture `probes/macos/loopback-cert.cnf` explicitly generates
X.509 v3; macOS LibreSSL otherwise generated v1, correctly rejected by Rustls.
Do not weaken certificate validation. The C test retains exact payload/counter
checks but waits up to two seconds for asynchronous sender completion: receiving
reconstructed media does not imply all repair symbols have finished sending.

For unpublished qualification inputs kept outside the clean worktree, set
`PLANK_MACOS_LOOPBACK_SOURCE` to the exact C test and
`PLANK_MACOS_LOOPBACK_CERT_CONFIG` to the fixture. Copy these alongside the runner
in the bootstrap directory and SHA-256-check all three against local files.
Do not claim the worktree commit includes these uncommitted test inputs.

First qualification on the dedicated Mac: root `e451f24e88ea67ebcd97d1984a39d10c0b4d23b2`,
Kymux `2ccf810609cb87fe6bdc7c0686195ab56e91465e`; release build passes,
16 enabled Rust tests pass, 2 integration/loss tests intentionally remain ignored.
Both C loopbacks pass, with about 30 ms sender-counter settling each. Two
unused Quinn telemetry warnings remain in the default-feature build. This is
not a packet-loss matrix, performance test, account-authentication test or
existing Client interoperability qualification. Exact hashes are in HANDOFF.

## Host-first audio qualification

The Host-first direction in `macos-host.plan` supersedes the older preview-first
order below. No new Client package is required for these component gates.

Use `scripts/build-macos-audio-probe.sh SOURCE_ROOT EMPTY_OUTPUT` on the dedicated
Mac with the existing signing identity. It builds the standalone **audio** entry
point at Probe build 46; it is not the HTTPS entry point of Probe 44 or the old
multi-mode CLI. Preserve the installed app before replacing it, verify signature
and installed executable SHA-256, and use the existing consented app location.
Unlock/sign within the same SSH TTY as described below; no keychain ACL change.

Run the installed probe in the existing user's Aqua domain:

```bash
bash probes/macos/run-graphical-probe.sh "gui/$(id -u)" \
  "/Applications/PLANK Host Probe.app/Contents/MacOS/plank-host-probe" \
  probes/macos/probe-agent.plist --audio
```

This explicitly plays a quiet two-second generated tone and captures system
audio for eight seconds. No microphone, recorded samples, display changes or
new listener. The runner removes its temporary job. Do not start this on an
unrelated user's session. SDK 27 requires AVAudioEngine's
`connect:to:format:error:` and AVAudioPlayerNode's `playAndReturnError:`; their
old counterparts cause deprecated-API errors with warnings-as-errors. Use the
modern APIs and check their errors, not warning suppression or old-OS paths.

For native delivery without live capture/playback, run:

```bash
bash scripts/build-macos-native-audio.sh SOURCE_ROOT EMPTY_OUTPUT \
  RETAINED_VERIFIED_LIBPLANK_TRANSPORT_ARCHIVE GENERATED_OPUS_FIXTURE
```

All arguments must be absolute. Generate the PAO1 fixture with `audio-encode.c`
as described in `macos-audio.md`; never use recorded user audio. The runner binds
loopback UDP 47493 only, uses ephemeral pinned TLS and test-only authentication,
checks exact packets/timestamps/revocation, and removes its private TLS material.
No Rust rebuild is needed: reuse the qualified native ABI-12 archive. These
copied/hash-verified standalone sources are not clean release-package snapshots.

The same runner also compiles the production `media/opus-encoder.m` and runs
`tests/audio/macos-opus-encoder.m`, producing `streaming.pao` (400 packets,
deliberately no stop-time EOF flush). Transfer/hash-check that synthetic fixture
on linux-client-builder and run `macos-opus-compatibility streaming.pao --measure-priming`.
This uses the unchanged system libopus decoder, not new Client functionality.

SDK-27 buffer-list qualification detail: pass exactly `sizeof(AudioBufferList)`
for interleaved stereo, and the two-buffer list size for planar stereo.
Passing the larger two-buffer capacity for interleaved PCM returned
`kCMSampleBufferError_ArrayTooSmall` even though the queried requirement was
only 24 bytes. Both formats now have a production-module test. Do not paper
over this with an unbounded allocation or assume all CoreMedia audio is planar.

## Historical first interactive preview boundary (superseded by Host first)

After this portability gate, implement in this order:

1. macOS account verification and session ownership behind a narrow privileged
   boundary; keep existing certificate approval and pre-session authorization.
2. Explicit ScreenCaptureKit/VideoToolbox capability tuples and synchronized
   Client profiles. Never label Apple HEVC Main10 4:2:0 as Linux NVENC 4:4:4.
3. Feed complete VideoToolbox Annex-B frames into the existing native transport;
   preserve timestamps, bounded submission, bitrate changes and keyframe recovery.
4. Wire keyboard/mouse and cursor handling, initially on an already logged-in
   desktop. This is a preview, not acceptance of the required login-screen flow.
5. Replace temporary probe orchestration with authenticated machine-service and
   graphical-agent lifecycle, then qualify LoginWindow → desktop → logout.

Audio, Wacom and notarized release packaging can follow the first interactive
preview. Authentication, exact-format negotiation and cleanup cannot be skipped
to obtain an earlier demo. Linux behavior must remain unchanged.

## Hardware encoder/native media qualification

Run `bash scripts/build-macos-native-video.sh SOURCE_ROOT EMPTY_OUTPUT ARCHIVE`
on the dedicated Mac. `ARCHIVE` is the exact retained, SHA-256-verified
`libplank_transport.a` from the transport gate; do not rebuild/download Rust for
Objective-C-only edits. Source inputs include `host/macos/auth`, the new
`host/macos/media`, `protocol/plank-transport/include/plank_transport.h`,
`tests/auth/macos-native-video.m` and `probes/macos/loopback-cert.cnf`.
Include and hash those explicitly when copying unpublished standalone inputs;
an older control-only staging directory does not contain the transport header.

The runner requires a free UDP 47491 and binds loopback only. It performs
hardware-required 1080p and 2160p synthetic HEVC tests through native QUIC,
including forced keyframe recovery. It creates and removes private ephemeral
TLS material, leaving the binary and synthetic first-frame HEVC files. It
does not request TCC, install an app or capture the desktop. The synthetic
account backend is linked only into the test executable. Preserve source,
archive and binary hashes separately; this is not a clean release build.

Inspect the synthetic files with the pinned Client FFmpeg on linux-client-builder,
using its private `LD_LIBRARY_PATH`. Expect HEVC Main10, `yuv420p10le`, limited
range, BT.709 matrix/primaries and sRGB transfer. This is a component gate;
actual Client hardware decode and presentation still require a hardware target.

The native-video runner also compiles `preview-session.m`/`screen-capture.m`
and runs the synthetic-capture lifecycle suite on loopback UDP 47492. Include
`plank_transport_control.h`, both new modules and
`tests/protocol/macos-preview-launch-v1.json` in standalone staged inputs.
This is not a new transport-library build. Each lifecycle test remains bounded.

## Authenticated live preview qualification

`bash scripts/build-macos-preview.sh SOURCE_ROOT EMPTY_OUTPUT ARCHIVE` builds
the loopback synthetic launch server, native receiver, and a signed **PLANK Host
Probe.app** with real account verification and capture. It requires the existing
`PLANK_MACOS_SIGNING_IDENTITY` certificate fingerprint, SDK/minimum macOS 27
and the retained archive. This app entry point is the authenticated HTTPS probe,
not the older command-line chart/input probe. Preserve the previously installed
probe app before replacing it on the dedicated Mac. Do not install on the
read-only reference Mac or change TCC/keychain trust policy to make it work.

Current output is **Probe 49**, the authenticated combined audio/video entry
point. Its source list includes `native-audio.m` and `opus-encoder.m`, linked
with AudioToolbox. The older standalone audio-only Probe 46 does not accept the
HTTPS runner's arguments; do not confuse installed app versions. Public product
discovery remains gated. The qualification launch's audio service is now true.

If signing fails with `errSecInternalComponent` despite a valid identity,
unlock the login keychain interactively and run signing/build **within the same
SSH TTY session**. A separate unlock-only SSH session may succeed, yet signing
in a later SSH session still lacks access. Never pass the keychain password in
arguments, environment or files, or change key ACL/partition policy as a shortcut.
After compilation has already passed, retry only codesign/verification in that
same unlocked session; no new dependency bootstrap or clean compilation is needed.

First run the synthetic endpoint (no capture even if TCC is granted):

```bash
python3 tests/auth/macos-https-auth.py \
  --server /absolute/preview-output/preview-synthetic \
  --config probes/macos/https-cert.cnf \
  --preview-receiver /absolute/preview-output/preview-receive
```

Then, from a TTY as the desktop user, run the signed app installed at its
consented location using `--aqua` and the same receiver/config. The runner asks
for the password without echo, boots a temporary Aqua job, approves its exact
TLS fixture and exchanges the transport secret only over TLS and receiver stdin.
TCP and UDP share the same ephemeral loopback port and leaf certificate. It
receives live HEVC in memory for three seconds, tests the existing bitrate
acknowledgement, and sends a native disconnect. No desktop image is written.
Finally it removes its exact Aqua job and temporary TLS material. Do not use
Screen Sharing to launch this test or modify login state.

The receiver now drains audio alongside video (bounded nonblocking batches),
checking 240-frame packet sizes, continuous millisecond PTS and a shared source
clock. `--preview-seconds 30` runs a bounded 30-second qualification; values
3–30 are accepted. This is not a Client playback or multi-hour sync soak.
Failure reporting copies only allowlisted stage/numeric capture diagnostics,
never the full Host stderr or credential-bearing requests. Do not compile while
collecting timing measurements. Keep unexplained stops in the qualification
record even if a later run passes.

A successful receiver checks framing, codec identifier, timestamps and clean
disconnect; it does **not** decode or present those live frames. The independent
synthetic bitstream tests remain the color/format evidence. Existing-Client
hardware decoding/presentation and longer live tests are still required.

## Native account-backend qualification

`scripts/build-macos-auth.sh SOURCE_ROOT EMPTY_OUTPUT_DIRECTORY` builds the
portable ownership test and a short-lived Open Directory verifier harness.
It also builds the private-channel and authentication-conversation tests.
It requires SDK/macOS 27 and sets a 27.0 deployment target. It does not install
anything, grant permissions, modify accounts or expose a network listener.
The harness and native backend compile with warnings as errors. Current
uncommitted files are qualification inputs only, not a release snapshot; record
their hashes when using the existing standalone-probe staging area on the Mac.

The build runs ownership, malformed-input/root-denial, private-channel and
conversation-state cases automatically. The latter two use synthetic verifier
implementations linked only into test executables; they never try bad passwords
against a real account. There are no product failure-injection switches. Tests
must retain their ad-hoc code signatures because the channel checks running
peer code identity. Do not disable code validation to run an unsigned test.
The separate `account-verification --verify-current-account` mode verifies only
the invoking non-root development account. Run over an actual terminal: it
uses `readpassphrase` with echo disabled and refuses a non-TTY credential source.
Never pass the password through arguments, environment, a file or a logged
command. The one-shot process disables core dumps and has a 20-second deadline.
It reports booleans, not the account identity or password. Success does not
grant desktop access. Do not automate wrong-password attempts against the
development account until its lockout policy is qualified.

Use `account-verification --verify-isolated-current-account` for the real
end-to-end private-channel test. It has the same TTY-only password input but
re-execs its verifier, sends credentials over the checked inherited socket,
requires a clean child exit and clears the parent's mutable secret. The worker
has a four-second deadline beneath the Client's five-second auth-request wait.
The outer interactive harness still allows 20 seconds for operator input.
The helper mode is internal; invoking it directly without its protected channel
must fail. Do not install a standalone public authentication socket.

The portable policy test is also registered in the root Linux qualification
CMake test suite. The macOS verifier itself is not a Linux package dependency.

## Native HTTPS/Aqua qualification

`scripts/build-macos-control.sh SOURCE_ROOT EMPTY_OUTPUT_DIRECTORY` first runs
the auth build/tests, then compiles the Network.framework adapter, HTTP parser,
live Aqua authority, a real qualification executable and a separate synthetic
test executable. All use SDK/minimum 27, warnings as errors and Apple frameworks.
The qualification flag is present only in `https-auth-synthetic`; it is not
linked into `https-auth` or a product binary. The normal executable dispatches
its private verifier argument before initializing any graphical/network code.

The runner also builds the native fixed-capture serializer/provider and verifies
`tests/protocol/fixed-capture-v13.json`. The encrypted synthetic and real Aqua
tests now exercise authorized topology, repeated geometry, and invalid/missing
Bearer rejection. The real query reads existing geometry only; it must never
start a stream, change a display or grant input as part of this control gate.
For Client validation on linux-client-builder, run the existing
`client/moonlight-qt-fork/tests/outputtopology/outputtopology.pro` suite with
`PLANK_REPO_ROOT` identifying both the Linux and fixed-capture JSON fixtures.
Keep `QT_QPA_PLATFORM=offscreen`. Unpublished standalone module/test inputs must
be SHA-256-verified separately; this is not a substitute for the required clean
worktree and full Client DEB/decoder gates before deploying a candidate.

The no-argument `https-auth` probe reports authority and immediately revokes it.
Over SSH it must print `active=0 revocation_pass=1`; use the existing temporary
graphical-probe runner in the user's `gui/UID` domain to verify `active=1` and
latched revocation. It does not request TCC, capture, input or display changes.

Run the synthetic encrypted exchange on the dedicated Mac:

```bash
python3 tests/auth/macos-https-auth.py \
  --server /absolute/control-output/https-auth-synthetic \
  --config probes/macos/https-cert.cnf
```

For real account verification in Aqua, run over an interactive SSH TTY as the
desktop user, never root:

```bash
python3 tests/auth/macos-https-auth.py --aqua \
  --server /absolute/control-output/https-auth \
  --config probes/macos/https-cert.cnf
```

The runner reads the password with terminal echo disabled, creates an ephemeral
loopback certificate/key in a mode-0700 directory, registers a unique one-shot
Aqua job, and submits the existing HTTPS start/respond exchange. It checks
live desktop ownership and replay denial. Finally it bootouts that exact job
and removes its own fixtures/output; no password/token enters files or arguments.
Do not rerun a failed real-password test blindly if failure could count against
the account's lockout policy. The listener is loopback-only, expires after 60
seconds, and does not expose any desktop/capture endpoint.

Known tool constraints, not product TLS failures:

- Xcode's bundled Python links LibreSSL 2.8.3 without TLS 1.3. Use the runner's
  OS `openssl s_client -tls1_3` path with certificate verification enabled;
  do not downgrade TLS or install an extra Python just to bypass that limitation.
- LibreSSL PKCS#12 fixtures failed Apple's importer (authentication/decode
  statuses). There is no importer workaround in the code: `SecCertificateCreateWithData`,
  `SecKeyCreateWithData` and `SecIdentityCreate` construct the identity directly
  in memory and verify that certificate/private key match. No keychain import.
- Use `https-cert.cnf`, which matches the product certificate's self-signed
  CA/key-signing attributes. Do not reuse the Rust transport's non-CA loopback
  fixture as an OpenSSL trust anchor; leave that separately qualified fixture
  unchanged. No trust-store change or insecure flag is needed.

The suite now also exercises public server discovery before and after
authentication. It is not Client UI approval, profile negotiation or video
playback. See `docs/macos-control-plane.md` for next integration steps.

## Existing Client discovery parser qualification

Run this only on linux-client-builder with Qt 6.10.2, not on the Mac or linux-host-builder. Reuse a
verified clean Client worktree at the root gitlink and its exact common-c
checkout. This is a small uninstalled parser harness, not a Client DEB build;
neither FFmpeg compilation nor a GUI/test session is required. The harness
compiles the real `NvHTTP`/`NvComputer` implementation and discards unrelated
unused operations at link time; it contains no replacement discovery parser.

```bash
source ~/.config/plank-builder/paths.env
# Set these to verified exact-commit worktrees, not inferred old candidates:
test -f "$PLANK_CLIENT_SOURCE/app/backend/nvhttp.cpp"
test -f "$PLANK_COMMON_SOURCE/src/Limelight.h"
discovery_build=$(mktemp -d "$PLANK_WORK_ROOT/macos-client-discovery.XXXXXX")
cd "$discovery_build"
qmake6 "$PLANK_SOURCE_ROOT/tests/protocol/macos-client-discovery.pro" \
  PLANK_CLIENT_SOURCE="$PLANK_CLIENT_SOURCE" \
  PLANK_COMMON_SOURCE="$PLANK_COMMON_SOURCE"
make -j4
QT_QPA_PLATFORM=offscreen ./macos-client-discovery \
  "$PLANK_SOURCE_ROOT/tests/protocol/macos-server-information.xml"
```

Record Client/common-c commits, harness/fixture hashes and output binary hash.
For unpublished qualification files, copy only the three test files into the
temporary test build directory and SHA-256-check them; use its `.pro` and XML
paths instead of pretending they belong to the clean source commit. The native
Mac metadata test consumes the same fixture. No builder package installation
or test-target deployment is part of this check. Remove the exact temporary
test build after its source checkpoint and qualification record are retained.

## Apple profile component qualification — linux-client-builder

Run the Client `tests/plankbitrate/plankbitrate.pro` and
`tests/applevideoprofile/applevideoprofile.pro` in separate shadow build
directories. The former uses Qt 6.10.2; the latter uses the retained private
FFmpeg. Set `PKG_CONFIG_PATH=$PLANK_CLIENT_FFMPEG_WORK/install/lib/pkgconfig`
before qmake, and `LD_LIBRARY_PATH=$PLANK_CLIENT_FFMPEG_WORK/install/lib` when
running the decoder test. Its `.pro` includes libswresample for private
libavcodec's transitive link requirement. Never link a distro FFmpeg instead.

The embedded fixture is a synthetic VideoToolbox Main10 chart, not a desktop
capture or generic HDR HEVC sample. Its Client test README records provenance
and SHA-256. Passing proves software decode and strict format validation only;
hardware decode, renderer output and stream integration are separate gates.
Keep partial copied standalone qualification inputs explicitly identified;
full Client builds still require exact committed, clean worktrees and bundles.

For `tests/outputtopology/outputtopology.pro`, set `PLANK_REPO_ROOT` to the exact
root source worktree when running its binary. Without that environment value,
the fixture-dependent tests fail to open JSON vectors; that is a runner error,
not a topology or compiler regression.

### Native optional services and typed preview launch

On linux-client-builder, import a verified unpublished **common-c bundle before Client,
then Client before root**, always using `--recurse-submodules=no`. Create clean
detached worktrees and run:

```bash
bash "$root_worktree/scripts/test-client-native-services.sh" \
  "$root_worktree" "$client_worktree" "$common_worktree" \
  "$PLANK_WORK_ROOT/native-services-candidate"
```

The output must not already exist. This compiles actual common-c Connection.c
with test-only device/network boundaries and the real Qt typed manifest parser.
It starts no service, media stream, input device or network listener. Current
expectation: 291 state-machine checks and 110 manifest checks. Full Client
link qualification remains separate; these are not hardware acceptance tests.
Do not run an old Client against a new common-c header/library: service flags
are an explicit internal struct contract, with no old-ABI inference.

For an uninstalled full-GUI startup diagnostic on linux-client-builder, keep isolated
XDG config/state/cache/runtime directories and use both
`QT_QPA_PLATFORM=offscreen` and `SDL_VIDEODRIVER=offscreen`. The SDL `dummy`
driver is not a substitute: both the unchanged 1.0.34 binary and the Mac-profile
build crash at `PlVkRenderer::initialize` when its Vulkan loader is unavailable.
The ordinary package `--version` check does not enter that renderer path.
Bound full-GUI probes with `timeout --kill-after=2s 8s` because the application's
SDL signal handler can consume SIGTERM without exiting its idle Qt main loop.
This diagnostic does not qualify compositor behavior, decoder hardware, visual
layout or session teardown; those need the actual hardware-test target.
