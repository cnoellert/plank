# PLANK handoff

## Accepted merge and release preparation: 1.0.143

The operator accepted the combined fixes, reports no further “Waiting for
Workstation” popup during the latest observation, and explicitly requested
merge to main, rebuild and release. Wallpaper/Screen Saver settings hover lag
is deferred, not repaired. Do not continue that investigation or add speculative
queue changes during this release. No installation or new live hardware test
is requested.

Prepare all four public products from the exact new mainline source on
GitHub-hosted builders. Use 1.0.143, not relabeled .141/.142 feature packages.
Both Mac products require Developer ID signing, notarization and stapling.
Verified exact-input dependency caches are allowed; application and transport
objects build fresh. No pending unrelated PR, dependency update, RK3576 work
or private Relay/Wake Agent product belongs in this release.

Merge dependencies before the parent: Client common-C into `plank/client`,
shared Client and Linux Host into their `main` branches, then this parent.
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
Package-source commit, hosted runs, checksums and publication are pending;
do not describe this release as built or published yet. Previous public release
is [1.0.137](https://github.com/instinctual/plank/releases/tag/v1.0.137).
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
- Make Mac system logs administrator-readable: root:admin, directories0750,
  files0640. Per-user desktop logs and secrets remain private.
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
transport tests and approximately150-Mbps receiver-side loss fixtures passed;
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
Client logs contain a complete223-second session with no spontaneous reconnect.
Client toolbar Disconnect explains the final generic input-receiver failure.

All5,675 transmitted input events reached the Host. Maximum owner-queue wait
was70.010ms and delivery17.939ms. Client uses Intel VA-API HEVC Rext10-bit444,
not software; decode/queue/render-call maxima are61/28/53ms. First120-second
Host traces show capture-to-submission max223.725ms and sender-work max33.859ms.
Final sampled RTT935us; zero receive-queue drops,21missing/6unrecovered video
source symbols out of33,381. Final rolling loss0% is not whole-session zero loss.
Capture gaps and20-FPS session averages include idle content and do not prove
a capture cap. No measured stage explains the reported1–2second lag.

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

- Identical Mac Client package on macOS15/27; pressure/unplug/focus/reconnect
  and release recovery.
- Permission startup/denial/revocation, capture release, local emergency
  shortcuts, logout/user switch and disconnect/menu/Dock cleanup.
- Toolbar updates/drag/hide-reveal; transient menu-bar line remains unattributed.
- Clipboard immediate-paste, interruption, ownership and large-transfer stress.
  No applied-write acknowledgment establishes atomic immediate paste.
- Exact-format/color hardware paths, packet loss and long-session cleanup;
  final macOS27 OS revalidation.

Linux physical-display lease/provenance inconsistency remains unresolved:
requested virtual layout can disagree with realized physical XRandR inventory
after GDM handoff. Client rejects invalid composite provenance. Do not weaken
that guard or claim an operator reboot repaired the underlying cause.
Unmerged physical-mode/Retina dropdown PRs and Mac Host pre27 support are excluded.

## Workspace and build policy

Work in `build/worktrees/mouse-edge-recovery`, moving it to main for release.
The primary checkout is unrelated dirty `rk3576-client` research; preserve it.
Other retained review/candidate worktrees are not authorization for broad cleanup.

Read the canonical release and hosted runbooks before builds. Use hosted
builders, not the development Mac. Keep full CUDA architectures, exact pins,
dependency patch/runtime/package gates and signed Mac temporary-key cleanup.
Main-only signing authorization needs no reviewer approval. Never broaden it.

Collect exact bytes with `scripts/package/collect-package.py` into
`artifacts/packages/releases/1.0.143/`, retain source provenance, and tag the
package-source commit after gates pass, not a later documentation-only commit.
Published SHA256SUMS uses flat download names; local checksums use OS paths.
No package deployment is part of this task.

Treat tracked documents and commit messages as public. Machine details,
credentials and raw logs remain in the external private-notes location.
Do not restore ENet/GameStream, private infrastructure or historical build inputs.
