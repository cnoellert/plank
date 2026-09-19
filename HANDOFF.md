# PLANK handoff

## Active macOS listener recovery

Work is on `macos-listener-recovery`, based on main `458f1f6`, in the existing
`build/worktrees/mouse-edge-recovery` worktree. Preserve the unrelated dirty
primary `rk3576-client` checkout. Version is `1.0.144-macos-listener-recovery`;
all dependency gitlinks below are unchanged. No new package is installed.

After PLANK sign-in authorization as one account and macOS desktop login as a
different account, the new desktop worker failed binding its control listener
with POSIX EADDRINUSE. The previous sign-in process had exited. launchd deferred
KeepAlive in an on-demand-only Aqua domain, and the coordinator's successful
kickstart was considered final. A targeted, authorized kickstart restored the
existing Host: loopback discovery returned HTTP 200. This establishes recovery,
not the exact socket state at the original conflict. Private machine evidence
stays outside Git.

The fix reuses the existing coordinator. After kernel-observed desktop exit
and exact lease release, re-arm only the current UID/audit session's existing
ten-attempt budget, with 1/2/4/8/16-second capped backoff. Duplicate notifications
cannot replenish it; delayed work from old console sessions is invalidated.
An exit before launchctl completion cannot be lost to a late success callback.
Numeric listener failures now go to the product log. No socket-sharing option,
new service, token transfer, cross-user authority, or Client/Linux change.

The focused policy and synthetic OS-callback tests cover repeated exits,
completion races, user/audit changes, stop, timeout and finite exhaustion.
Local 48 CI-policy tests, 27 account-policy cases, 23 installer-script checks,
version contract, shell syntax and whitespace checks pass. Hosted Mac build
[35468169313](https://github.com/instinctual/plank/actions/runs/35468169313)
passed at `c19eef4967a41fef19fb6ffb97cf36783fe3fb52`, reusing verified dependencies.
The recovery policy and 98 scheduler checks passed, together with 509
authentication checks, 190 graphical-lifecycle checks, 726 session checks across
24 synthetic-capture/real-QUIC scenarios, and existing input/audio/clipboard and
bundle-permission gates. Two expected hardware-dependent Rust tests were ignored;
unchanged Quinn telemetry dead-code warnings remain. This was an unsigned
build/assembly, not a distributable installer or a live installation test.
The code is committed and pushed on the feature branch, not merged.
Signing authorization remains main-only and must not be broadened.
Before claiming acceptance, test the actual
cross-user sign-in handoff on an authorized signed installation; the Host must
stay available while requiring fresh authorization for the new desktop owner.
See [recovery plan](docs/development/plans/macos-listener-recovery.plan).

## Mainline 1.0.143 release

The operator accepted the combined fixes, reports no further “Waiting for
Workstation” popup during the latest observation, and explicitly requested
merge to main, rebuild and release. Wallpaper/Screen Saver settings hover lag
is deferred, not repaired. Do not continue that investigation or add speculative
queue changes during this release. No installation or new live hardware test
is requested.

All four public products were rebuilt from the exact mainline source on
GitHub-hosted builders as 1.0.143, not relabeled .141/.142 feature packages.
Both Mac products passed Developer ID signing, notarization and stapling.
The Mac Client reused its verified exact-input dependency cache; both Linux
products and Mac Host had cache misses and completed fresh pinned bootstraps.
Application and transport objects built fresh. No unrelated PR, dependency
update, RK3576 work or private Relay/Wake Agent product is included.

Dependencies were fast-forward merged and pushed before the parent: Client
common-C into `plank/client`, shared Client and Linux Host into `main`, then
this parent. Package-source main is
`86c435ed8ba9c5b143048c5a6f8db5d6870606bf`.
The accepted runtime pins are:

| Input | Commit |
| --- | --- |
| Shared Client | `46ae50c2e189e358400ece271be469c1b61c98f4` |
| Client common-C | `060f6179f88343327b44d915007f1fb4cede71f1` |
| Linux Host | `cd738510c6588aa086746cf00dca93c17c6bea73` |
| Kymux | `6f3df8e2c9eac41d4bc0ec9d3f1fc9cbf8d1a804` |
| Host build-deps | `c29c4822cb96f5bfeb8640e72601c5cf4e3c3137` |
| Host libvirtualhid | `a0d3aa0cc4d53daa18bfa2f2fbdf848957b6d294` |
| Host common-C | `3a97a58f215323753cfd1180af760ec7e3253538` |

Other unchanged recursive pins are recorded in these immutable Git trees.
All hosted release gates passed at that exact source:

| Gate | Hosted run | Result |
| --- | --- | --- |
| Ordinary four-product build / Linux packages | 35398040610 | Passed |
| Signed Mac Host | 35398040353, attempt 2 | Passed |
| Signed Mac Client | 35398043071 | Passed |
| Privacy checks | 35398040628 | Passed |
| Clipboard regressions | 35398040481 | Passed |

[PLANK 1.0.143](https://github.com/instinctual/plank/releases/tag/v1.0.143)
is published as the latest release with all four packages, the combined manifest
and flat-download SHA256SUMS. GitHub's six asset digests match the local files.
Annotated tag `v1.0.143` names package source `86c435e`; subsequent documentation
commits do not change the published binaries.
Local release-version contract and all 48 CI-policy tests passed. The signing
environment remains main-only, with no reviewer gate or policy change.
All seven portable CTest suites, 23 Mac installer-script checks and the C
diagnostic-label/timing tests passed locally. An initial ad hoc diagnostic
compile omitted its include directory; the corrected invocation passed.
Hosted privacy and clipboard regression runs passed. Signed Mac Host attempt 1
failed the second C ABI loopback audio receive (five-second timeout, after video
and the fingerprint-trust case passed). No audio runtime change or test relaxation
was made; one unchanged failed-job rerun passed, as did the independent ordinary
Mac Host build. Preserve that failure in release evidence and do not claim its
cause established. Both signed Mac packages passed package checks and
temporary-key cleanup. Ubuntu Client passed its package and exact-linked input
gates. Linux Host passed dependency-patch, RPM runtime/configuration/log-directory
and input lifecycle gates (25 shuffled iterations: 13 passes and three
hardware-dependent UHID skips each). The distributed RPM is BUILD_TESTS=OFF;
test objects were built afterward, without repackaging. Linux Host used GCC
14.2.1, CUDA 13.0.88 and Rust 1.89.0; the pinned Qt 6.10.2 and platform FFmpeg
contracts were unchanged. Mac lifecycle checks passed 190 authority checks and
726 session checks across 24 synthetic-capture, real-QUIC scenarios.

All four exact packages are retained under `artifacts/packages/releases/1.0.143/`,
with a combined manifest and verified SHA256SUMS:

| Package | Bytes | SHA256 |
| --- | ---: | --- |
| `linux/plank-host-1.0.143-1.el9.x86_64.rpm` | 8580365 | `fac019c992b118aa15ecf3e6372657edc20c82b694f5db29604e32b1a0a96379` |
| `linux/plank-client_1.0.143_amd64.deb` | 15452172 | `a229cd37d60608dc521d2687ba78212c050f5f4912ca030d39c2a6e0eeaa1cac` |
| `macos/plank-host_1.0.143_arm64.pkg` | 6619228 | `65534b178aac68908f591298e5f527fd16a397c03b957240aea85a32056c2497` |
| `macos/plank-client_1.0.143_arm64.dmg` | 86611082 | `3907c1e01fab13f143ac235e46a9038b29cf6938574a1bbb6adcb64703e05af5` |

No packages were installed or new live hardware tests performed. Package gates
remain distinct from the accepted candidate observation and remaining gates.
See [1.0.143 release notes](docs/releases/1.0.143.md).

## Included changes

- Clamp Client/common-C absolute mouse positions to the dynamic last pixel.
  Preserve input ordering, press/release barriers and strict Host validation.
- Remove the Linux delayed-left-release/synthetic-right-click workaround while
  retaining held-input cleanup.
- Enable Linux Host fast-send: no application datagram pacing, 1 Gbps minimum
  rate-derived Quinn window budget. Encoder target, FEC and MTU are unchanged.
- Preserve Mac graphical authority through screen-lock notification. Actual
  session resignation, sleep, logout, changed console ownership/audit scope,
  lost permission and expired machine admission still retire authority.
  Unlock never grants authority and macOS still enforces its own OS unlock.
- Make Mac system logs administrator-readable: root:admin, directories 0750,
  files 0640. Per-user desktop logs and secrets remain private.
- Retain privacy-safe first-stop/failure classification and bounded input timing
  diagnostics. No raw transport error, input content or credential is logged.

Details: [mouse diagnosis](docs/development/reviews/mouse-edge-recovery.md)
and [Linux sender plan](docs/development/plans/linux-fast-send.plan).

## Candidate validation before acceptance

The combined .141 package source is
`a3df4b0ed5b327049ad58ea9532712ea0fe25f05`.
Signed Mac Host uses `378dbb4c409c5b1e0bb9668dbda16ba275ab95fd`, whose only
additional change corrects a stale clipboard-Boolean fixture.

| Gate | Hosted run | Result |
| --- | --- | --- |
| .141 Linux Host and Ubuntu Client | 35384037039 | Both passed |
| .141 signed/notarized Mac Host | 35384452065 | Passed |
| .141 signed/notarized Mac Client | 35384039994 | Passed |
| .142 signed/notarized Mac Host | 35390098576 | Passed |

The ordinary .141 run also contains a superseded unsigned Mac fixture failure;
the successful signed rerun is the Host result. Mac session tests passed 726
checks across 24 real-QUIC scenarios with synthetic capture. Mac native log
access checks passed 60 checks. Linux Host input suites passed 25 shuffled
iterations with 13 passes and three hardware-dependent UHID skips per iteration.
The distributed RPM remains BUILD_TESTS=OFF. Fast-send and paced-baseline
transport tests and approximately 150-Mbps receiver-side loss fixtures passed;
these are not WAN or interactive hardware acceptance. Client exact-linked
input-bounds tests and six common-C suites passed, including ASan/UBSan.

Mac .142 source `e6e678f91e05bd9de0259473295ab74de96b4c08` adds lock continuity
and timing diagnostics. Hosted validation passed 190 graphical-authority/lease
checks, existing session tests, diagnostics, package/signing/notary/staple gates
and temporary-key cleanup. All 48 local CI-policy tests passed.
Its retained package is under `artifacts/packages/candidates/1.0.142-mouse-edge-recovery/macos/`,
SHA256 `6c1696a815a9e7b8cd3e52f1b2b1945f236e269e5153c2dc8b98cedf8388dbcc`.
All four .141 packages remain in the corresponding candidate catalog.
Feature signing permission was removed; the protected environment is main-only.

## Deferred mouse lag and acceptance limits

The operator reproduced lag over Mac Wallpaper settings, worse over Screen
Saver settings, without actual saver activation. Matching .142 Host/.141 Ubuntu
Client logs contain a complete 223-second session with no spontaneous reconnect.
Client toolbar Disconnect explains the final generic input-receiver failure.

All 5,675 transmitted input events reached the Host. Maximum owner-queue wait
was 70.010 ms and delivery 17.939 ms. Client uses Intel VA-API HEVC Rext 10-bit
4:4:4, not software; decode/queue/render-call maxima are 61/28/53 ms. First
120-second Host traces show capture-to-submission max 223.725 ms and sender-work
max 33.859 ms. Final sampled RTT 935 us; zero receive-queue drops, 21 missing / 6
unrecovered video source symbols out of 33,381. Final rolling loss 0% is not
whole-session zero loss. Capture gaps and 20-FPS session averages include idle
content and do not prove a capture cap. No measured stage explains the reported
1–2-second lag.

Mac cursor is embedded in captured video. Current counters do not measure
input queue age before dequeue, macOS processing after CGEventPost, or actual
compositor scanout. If this investigation is explicitly resumed, isolate those
stages with bounded measurements; do not blindly change queues or permissions.
Raw logs and machine-specific findings remain outside Git in private notes.

The operator accepted release without further investigation of that edge case.
This is not individual qualification of every screen-lock/unlock, user-switch,
permission, display, Wacom or network scenario. Live lock continuity has not
been separately reported; synthetic notification tests alone do not prove it.

## Remaining gates and known issues

Follow [acceptance criteria](docs/development/acceptance-criteria.md):

- Identical Mac Client package on macOS 15/27; pressure/unplug/focus/reconnect
  and release recovery.
- Permission startup/denial/revocation, capture release, local emergency
  shortcuts, logout/user switch and disconnect/menu/Dock cleanup.
- Toolbar updates/drag/hide-reveal; transient menu-bar line remains unattributed.
- Clipboard immediate-paste, interruption, ownership and large-transfer stress.
  No applied-write acknowledgment establishes atomic immediate paste.
- Exact-format/color hardware paths, packet loss and long-session cleanup;
  final macOS 27 OS revalidation.

Linux physical-display lease/provenance inconsistency remains unresolved:
requested virtual layout can disagree with realized physical XRandR inventory
after GDM handoff. Client rejects invalid composite provenance. Do not weaken
that guard or claim an operator reboot repaired the underlying cause.
Unmerged physical-mode/Retina dropdown PRs and Mac Host pre-27 support are excluded.

## Workspace and build policy

Work in `build/worktrees/mouse-edge-recovery`, now on `macos-listener-recovery`.
The primary checkout is unrelated dirty `rk3576-client` research; preserve it.
Other retained review/candidate worktrees are not authorization for broad cleanup.

Read the canonical release and hosted runbooks before builds. Use hosted
builders, not the development Mac. Keep full CUDA architectures, exact pins,
dependency patch/runtime/package gates and signed Mac temporary-key cleanup.
Main-only signing authorization needs no reviewer approval. Never broaden it.

Exact bytes were collected with `scripts/package/collect-package.py`. The release
tag names the package-source commit, not later documentation-only commits.
Published SHA256SUMS uses flat download names; local checksums use OS paths.
No package deployment is part of this task.

Treat tracked documents and commit messages as public. Machine details,
credentials and raw logs remain in the external private-notes location.
Do not restore ENet/GameStream, private infrastructure or historical build inputs.
