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

## First interactive preview boundary

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

This gate is not Client UI approval, server discovery, profile negotiation or
video playback. See `docs/macos-control-plane.md` for next integration steps.
