# macOS development build notes

Status: experimental macOS Host; no installable product package yet. Build only
on the authorized dedicated development Mac. Linux builder roles are unchanged.
Require Apple Silicon, macOS 27, SDK 27 and explicit deployment target 27.0.
Probe signing/installation remains documented in `probes/macos/README.md`.

## Native Host executable and application

For LoginWindow candidates, run
`python3 tests/auth/test-macos-development-install.py` and the Client's
`tests/desktopstage` suite. The development installer now registers a
LoginWindow-only agent as well as the designated user's Aqua agent. It never
logs out or reboots for testing. See `macos-session-lifecycle.md` for its
role-private identity files, restart policy and remaining live acceptance gates.
ABI-13 candidates must rebuild the transport archive; never link an ABI-12
archive to the larger stats header. Preserve accepted .57's
`PLANK_MACOS_SOURCE_FIRST=1` feature selection during that rebuild.

Use `scripts/build-macos-host.sh SOURCE EMPTY_OUTPUT RETAINED_TRANSPORT_ARCHIVE`
on the dedicated Mac. Set `PLANK_MACOS_HOST_VERSION` explicitly, for example
`1.0.64-macos-hevc444`. Use the base packaging version on main and append the
actual feature branch otherwise; do not keep the historical `macos-host`
qualifier on unrelated branches or main. Both build and development install
accept that shared semantic-version/branch shape. The full native Host links with SDK/target 27 and
warnings-as-errors; no probe main or synthetic verifier is linked. The default
uninstalled executable is ad-hoc signed for assembly checks. Supplying the
existing `PLANK_MACOS_SIGNING_IDENTITY` also builds Apple-signed `PLANK Host.app`
with its own `la.instinctual.PLANK.Host` identity. Unlock the signing keychain
in the same SSH TTY. No Rust rebuild, Linux package or persistent service install.

`sudo python3 tests/auth/macos-host-service.py SOURCE BINARY SHA256 DESKTOP_UID`
tests the real executable with temporary system/Aqua jobs, role-private keys,
TLS discovery, unauthenticated topology denial, graceful stop and replacement
on the same desktop. It does not require logout/login, credentials, TCC, capture
or OS input. Temporary shared executable/log parents must be under `/private/tmp`,
not root's inaccessible per-user TMPDIR; graphical logs must belong to the
graphical UID or launchd returns EX_CONFIG before the executable runs.
The fixture canonicalizes the RSA key to PKCS#1 PEM to match its DER; req's
default PKCS#8 PEM must not be mistaken for the same byte representation.
Generated keys and both jobs are removed on exit.
When testing an Apple-signed application executable, keep the whole app bundle
including its Info.plist; a bare extracted Mach-O fails strict signature checks.
The runner detects this case and copies/verifies the complete bundle.

The existing `build-macos-preview.sh` now links `host-runtime.m`; its HTTPS
qualification launcher no longer duplicates stream creation or invents a
one-second cleanup delay. Its synthetic launch/transport tests remain useful
automated coverage of the real runtime, not the next operator milestone.

## Machine/graphical-agent IPC qualification

Build `bash scripts/build-macos-agent-registry.sh SOURCE_ROOT EMPTY_OUTPUT`
on the dedicated Mac, SDK/target 27, warnings as errors. Include both modules
under `host/macos/session`, authentication and graphical-authority sources/headers,
both agent tests, the service
plist and the two build/test scripts in the hash-verified source set. No Rust
rebuild, TCC permission or app replacement. The test executables are ad-hoc
signed to pin their exact code, not as a product distribution policy.

The build runs `agent-registry --synthetic`: 239 checks over real anonymous XPC
with synthetic scope observations. Require a clean process exit, including
autorelease teardown. A previous run printed passing assertions but trapped
when an inactive outgoing XPC object was released; that was a failure, now fixed.
Pending-peer expiry tests must cancel on XPC interruption, not silently reconnect.

To check actual graphical identity, run the uninstalled `agent-registry` binary
through the existing graphical runner with no explicit mode argument. Use root
for LoginWindow or the actual desktop user for Aqua. Default mode requires a
positive graphical scope; `--synthetic` does not.
Native mode includes seven admission-snapshot checks (254 total): phase,
generation, OS account, and nil/foreign/revoked lease denial.

For cross-process qualification, run as root on the dedicated Mac:

```bash
sudo bash scripts/test-macos-agent-service.sh SOURCE_ROOT \
  /absolute/output/agent-peer VERIFIED_SHA256 ALLOWED_DESKTOP_UID
```

Discover the UID; never assume 501. The runner hash-verifies a root-owned
temporary executable, boots a uniquely named system Mach service, proves
rejection of a signed Background peer, then launches the actual graphical agent.
Expected: `agent_service_cross_process_pass=1 persistent_install=0 media=0 input=0`.
Require `agent_service_admission=1 synthetic_verification=1` and
`agent_service_admission_revoked=1` too. The test links a synthetic verifier to
the production conversation/stream-lease owner; no account password is supplied.
Require `graphical_agent_bound_scope=1` for the graphical authority plus admission
view. The agent uses the production explicit-role authority, not the older
probe-only session helper. The control build also produces
`graphical-authority-test`: run it with no arguments through the graphical runner
(16 checks) and directly with `--background` from SSH (13 denial checks).
Root Background must deny local graphical authority too. No TCC or input involved.
An EXIT trap removes both exact jobs and all generated files. No persistent
installation, app replacement, capture, input, credentials or network listener.
See `macos-session-lifecycle.md` for what these tests do and do not prove.

## Native keyboard/mouse qualification

Use the dedicated Mac only. For the non-posting component tests:

```bash
bash "$source_root/scripts/build-macos-input.sh" "$source_root" \
  "$PLANK_WORK_ROOT/input-candidate" \
  "$PLANK_WORK_ROOT/transport-build-e451f24/release/libplank_transport.a"
```

Output must not exist; UDP 47494 must be unused. Reuse the retained ABI-12
transport archive (hash in HANDOFF), not a new Rust/dependency build. Expected:
1826 event checks and 129 native input checks/seven scenarios. Both suites post
zero OS events. Include **`protocol/plank-transport/include/plank_transport_input.h`**
in a standalone copied qualification source set; earlier audio sets did not need
that header. The input runner now checks for it before compilation. Standalone
copied inputs are not a clean release checkout; record their verified hashes.

For actual delivery, first have the operator unlock the desktop. A logged-in
console owner alone does **not** mean the screen is unlocked. Do not enter
credentials, change lock settings, or weaken the owned-window focus guard.
Build the focused signed test in the **same SSH TTY** as keychain unlock:

```bash
security unlock-keychain "$HOME/Library/Keychains/login.keychain-db"
# Enter the password interactively. Export the existing signing identity.
bash "$source_root/scripts/build-macos-input-delivery.sh" "$source_root" \
  "$PLANK_WORK_ROOT/input-delivery-candidate"
```

The current delivery app is Probe **56**, with separate `--input` and
`--login-pointer` modes, and is not the authenticated A/V app. The ordinary
owned-window input mode remains non-root/Aqua-only. Preserve/hash-verify the installed A/V app and its signed
backup before temporarily replacing it at the approved application path.
Verify installed ownership root/755, signature and executable hash, then run as
the actual desktop UID (never assume 501):

```bash
bash "$source_root/probes/macos/run-graphical-probe.sh" "gui/$(id -u)" \
  "/Applications/PLANK Host Probe.app/Contents/MacOS/plank-host-probe" \
  "$source_root/probes/macos/probe-agent.plist" --input
```

The expected base mask is 1023 with `position_match=1`, modifier down/up masks
255/255, Shift-key/click true, held=true, cleanup_received=7 and released=true,
result/exit zero. Focus denial
is a safety refusal, not proof the OS rejected input. Restore and hash-verify
the tested A/V app after the test; ensure the temporary agent is gone.
Request test-window activation from `NSApplicationDidFinishLaunchingNotification`,
not before `[NSApp run]`. Probe 51 still failed focus on an unlocked desktop;
moving that one activation to the launch notification produced two fresh Probe
52 passes with no mapper/source/permission changes. Do not replace the guard
with repeated activation attempts or inject input into another app.
The input test link retains the qualified `__CGPreLoginApp/__cgpreloginapp`
Mach-O marker. Carry that gate into any later app that incorporates input; the
current A/V/input Probe 54 includes it too. The marker does not bypass TCC
or qualify LoginWindow delivery. See `macos-input.md` for remaining gates.

### Operator-observed LoginWindow pointer

Probe 56 adds `probes/macos/login-pointer.m` and the existing
`session-boundary.h` to the input-delivery build. Copy/hash-check those plus the
updated build script, entry point and graphical runner. The source still uses
the unchanged production input mapper and private Quartz source. Require positive
LoginWindow identity and existing consent before creating input; recheck session,
display identity, point/pixel geometry and consent before every post. Background
SSH, including root, is not LoginWindow. Never weaken these predicates.

With the operator watching and the Mac actually **logged out**, temporarily
install the verified signed Probe 56 and run:

```bash
sudo bash "$source_root/probes/macos/run-graphical-probe.sh" loginwindow \
  "/Applications/PLANK Host Probe.app/Contents/MacOS/plank-host-probe" \
  "$source_root/probes/macos/probe-agent.plist" --login-pointer
```

It moves to approximately 25%/25%, then 75%/75%, then restores the original
position, with two seconds to observe each. No click, key, capture, login action
or permission request. A session/geometry change stops delivery; it will not
restore into a newly logged-in user's session. Expected: three observed matches,
restored=1, no_held_input=1, result=0. This is numerical event-position evidence;
ask the operator separately whether the cursor was visible. It does not prove
LoginWindow button/keyboard delivery or authenticated cross-session handoff.
Restore/signature/hash-check the retained A/V Probe 54 afterward. Probe 56's
new mode passed numerically on September 7; its unchanged `--input` path was
compiled but not rerun while the operator remained logged out.

## Embedded cursor qualification

Build `bash scripts/build-macos-embedded-cursor.sh SOURCE_ROOT EMPTY_OUTPUT`
on the dedicated Mac, in the same signing/keychain TTY. This produces **Probe
55**, accepting only `--cursor`, not the authenticated A/V entry point. Copy
and hash-check the new source, script and updated graphical runner together.
Temporarily install at the consented app path only after verifying the retained
Probe 54 backup; restore and hash-check that backup after the test.

Run the existing graphical runner in `gui/$(id -u)` with `--cursor`. LoginWindow
is refused. This test requires an unlocked desktop and existing capture/input
consent; it never prompts, logs in or changes TCC. It requests focus once after
AppKit launch, checks owned focus before movement and capture analysis, posts
motion only, and restores pointer/foreground app when still safe. The SCK filter
includes only its own test window; no audio, credentials, saved images, clicks
or keys. It stops after 18 seconds with a 30-second hard process deadline.

Expected: phases 0–4 each report match=1, completed=5 and result=0. The phases
prove cursor-disabled absence, custom shape/hotspot, changed position, changed
shape, and disabled absence again. Two matching samples are required per phase.
The changing gray test background forces fresh capture updates. Coordinates use
the actual display's point/pixel ratio; this is not a qualification of every
display configuration. The check inspects BGRA before encoding; it does not
measure cursor latency, HEVC decoded quality or ordinary Client presentation.
Two independent launches passed on September 7. Exact hashes are in HANDOFF.

## Isolated capture cadence (no transport)

`scripts/build-macos-capture-cadence.sh SOURCE EMPTY_OUTPUT` builds signed
Probe58 on the dedicated Mac, SDK/deployment27, with the existing signing
identity. No Host/Client/runtime library is linked. Preserve the current signed
`PLANK Host Probe.app`, temporarily install this probe at its consented path,
and restore/signature/hash-verify the original afterward. Keep the separate
installed `PLANK Host.app` untouched and require no active stream during tests.

Run through `probes/macos/run-graphical-probe.sh gui/UID ...` with
`--cadence-60` or `--cadence-native`. Both inspect the current main display at
its real pixel dimensions using the Host's xf20 full-range capture format,
SDR/sRGB and three surfaces. Only the minimum frame interval differs:1/60 or0.
No encoder, network, audio, pixel mapping, retained samples, focus/input events
or permission requests. Require existing capture consent. Count all
sample statuses, not just complete frames. Record numeric callback/PTS/status
rows in bounded memory; flush only after stop. Each run captures25seconds with
a35second process alarm and the runner's40second outer deadline. Alternate
both modes twice on the same unchanged moving desktop. This is capture cadence,
not proof of encoder, network, Client presentation or A/V-sync performance.

For continuous source updates independent of browser content, use
`--cadence-pattern-60` / `--cadence-pattern-native`. These temporarily cover the
current display with a nonactivating, input-transparent panel whose bar is
animated by Core Animation, not a CPU timer. The panel is hidden at completion
and disappears if the bounded probe exits. Do not assume a logged-in console
owner implies an unlocked desktop; verify scope and lock state before testing.
Report actual display geometry: restarting the Host can destroy its virtual
display and return the Mac to the1080p fallback. A probe of that fallback does
not qualify5120x2160 streaming. Discard the first2seconds of callback records
when comparing rates; use timestamp spans, not row-count divided by25 (sample
delivery can precede the asynchronous start acknowledgement).

## Transport qualification

The rejected .54/.55 submission-batching implementation, feature and extra
Quinn wrapper vendor tree have been removed. Historical source commits and
measurements remain in the sender-drain investigation; do not reuse their build
commands for a current candidate. The qualified source-first path below retains
ordinary single-datagram submission and the tested Mac application-pacer bypass.

For .53 source-first FEC qualification, use `PLANK_MACOS_SOURCE_FIRST=1`.
This includes the .51 fast-send/timing experiment and enables source-first
packet submission only on macOS. The wire format, repair count and library's
repair encoder remain unchanged. The runner additionally checks byte-identical
source packets against the retained RaptorQ library, multi-block/sub-block
padding, recovery at 0/5/10/20% omitted sources, and preparation timing. The
timing test is synthetic CPU preparation, not a network/performance gate.
Keep the .51 archive and signed app for comparison; Client .52 stays unchanged.

For the user-authorized combined sender experiment (.51), use
`PLANK_MACOS_FAST_SEND=1` instead. This selects `macos-fast-send`, which includes
sender timing. On macOS only, it passes no application datagram pacer to either
server path and floors the rate-derived Quinn window budget at 1 Gbps. This is
not an encoder bitrate, a measured link capacity, or a strict wire-rate cap;
Quinn still schedules transmission. Encoder settings, FEC and queue capacities
are unchanged. Keep this archive separate from the baseline. The feature is
off by default and must not become a release default without live acceptance.
Check receiver loss as well as sender drain: immediate submission can move
drops downstream. This experiment does not qualify the Linux sender.

For the explicitly authorized sender-drain diagnostic only, set
`PLANK_MACOS_SENDER_TIMING=1` before `build-macos-transport.sh`. It selects the
compile-time `sender-timing` feature (off by default), retaining ABI12 and the
same wire/pacing/FEC policy. Build a separate verified archive; do not overwrite
the retained baseline archive. Numeric measurements are future-local, capped at
8192 frames/120seconds, and flushed only after worker join into existing stderr
product logging. No runtime preference, extra listener, Client change or live
per-frame log output. Normal feature-disabled builds remain the release default.
Run the feature's bounded-window/context-isolation tests plus both C loopbacks,
and check the feature-disabled build. See HANDOFF for exact diagnostic artifacts.

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

The optional fourth argument `--low-latency` adds specialized RTVC qualification
at3840x2160 and5120x2160. This is a paused experiment, not the .50 live encoder
configuration or a routine-build gate. See HANDOFF for the unpaced frame-drop
observation; the updated60Hz paced test has not yet been run. Do not enable
RTVC in the production Host merely because session creation succeeds.

Inspect the synthetic files with the pinned Client FFmpeg on linux-client-builder,
using its private `LD_LIBRARY_PATH`. Expect HEVC Main10, `yuv420p10le`, limited
range, BT.709 matrix/primaries and sRGB transfer. This is a component gate;
actual Client hardware decode and presentation still require a hardware target.

The native-video runner also compiles `preview-session.m`/`screen-capture.m`
and runs the synthetic-capture/input lifecycle suite on loopback UDP 47492.
Current expectation is 403 checks/15 scenarios. Include `host/macos/session`
sources as well as the `host/macos/input`
headers/sources, `tests/input/macos-fake-input.{h,m}`, `plank_transport_input.h`,
`plank_transport_control.h`, both media modules and
`tests/protocol/macos-preview-launch-v1.json` in standalone staged inputs.
This is not a new transport-library build. Each lifecycle test remains bounded.

The four added scenarios connect real anonymous XPC admission to the actual
authentication and native-stream owners: revoke, service loss, a stalled IPC
queue, and replacement of the local generation. Delayed capture drain must
precede agent retirement. Capture and input remain synthetic; no OS events are
posted. The fixture still constructs genuine Quartz event objects. While development-mac
is logged out, the ordinary SSH user cannot create a private CGEventSource; an
unchanged `input-events` binary then fails `source != NULL` too. Do not interpret
that as a media regression or alter the production input guard. Prefer running
as the logged-in development user. While logged out, the same synthetic build/
test command was qualified with operator-authorized sudo on the dedicated Mac;
all outputs stayed in a new explicit temporary directory, with no installation.
That root Background synthetic run is not proof of LoginWindow capture/input.

## Authenticated live preview qualification

`bash scripts/build-macos-preview.sh SOURCE_ROOT EMPTY_OUTPUT ARCHIVE` builds
the loopback synthetic launch server, native receiver, and a signed **PLANK Host
Probe.app** with real account verification and capture. It requires the existing
`PLANK_MACOS_SIGNING_IDENTITY` certificate fingerprint, SDK/minimum macOS 27
and the retained archive. This app entry point is the authenticated HTTPS probe,
not the older command-line chart/input probe. Preserve the previously installed
probe app before replacing it on the dedicated Mac. Do not install on the
read-only reference Mac or change TCC/keychain trust policy to make it work.

Current output is **Probe 54**, the authenticated combined audio/video/input
entry point. Its source list includes the native input adapters and public
Quartz device, linked with Carbon/ApplicationServices and the qualified pre-login
marker, alongside `native-audio.m`/`opus-encoder.m` and AudioToolbox. The fake
input device is linked only into the synthetic executable, never the signed
real-account app. The older standalone audio-only Probe 46 does not accept the
HTTPS runner's arguments; do not confuse installed app versions. Public product
discovery remains gated. The qualification launch's audio and input services
are true; its cursor remains embedded. Live receiver qualification sends no
mouse/key input, so it can validate A/V without acting on the desktop.

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

The embedded fixtures are PLANK-owned VideoToolbox Main10 and RExt10 charts,
not user desktop content or generic HDR HEVC samples. The Client test README records provenance
and SHA-256. Passing proves software decode and strict format validation only;
hardware decode, renderer output and stream integration are separate gates.
Keep partial copied standalone qualification inputs explicitly identified;
full Client builds still require exact committed, clean worktrees and bundles.

The existing `macos-installed-client` integration harness takes explicit
`ADDRESS PORT USER WIDTHxHEIGHT ENCODING_MODE`, with the account password only
on stdin from a no-echo prompt. Both Apple modes use authenticated display
schema2. On GPU-less builders, append `--sample-keyframes` for format-only
qualification: receive/audio/control drain promptly; at most eight keyframes
and64MiB remain in memory and are decoded after disconnect. This is not a
real-time decoder, full reference-chain, or graphical presentation test.
The default synchronous full-frame software decode can fall behind a5K444
stream and overflow its receive queue; do not diagnose this test bottleneck as
an actual graphical Client transport regression. Static SCK content can
produce only one keyframe in15seconds; that validates format but not bitrate
response under motion. Keep failures and this limitation in the test record.

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
