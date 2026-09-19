# PLANK handoff

## Active: Quinn MTU-boundary repair, 1.0.147 candidate

Work is on `quinn-mtu-boundary` in `build/worktrees/mouse-edge-recovery`, based
on main `dd6fb04`. Preserve the primary checkout's unrelated dirty RK3576 work.
The operator authorized fixing and testing the Linux Host build blocker. Do not
merge, publish a release, install packages, or alter signing permissions yet.

The failure was reproduced with a trace showing MTU black-hole recovery dropping
254 queued datagrams exactly equal to the unchanged legal maximum (1,306 bytes).
Quinn's `drop_oversized` used `<`, inconsistent with the inclusive send limit.
It now uses `<=`; genuinely oversized packets are still discarded and counted
separately from queue-capacity evictions. This shared transport code affects all
platforms. No encoder/FEC/MTU/queue-capacity/pacing policy changed.

The loss fixture now drains its receiver-side UDP proxy on a dedicated test
thread and reports unintended per-socket Linux kernel drops separately. It
requests a larger proxy-only receive buffer subject to the existing OS cap;
no system tuning or product buffer changes. Original frame-order, byte-for-byte
payload and zero-unrecovered-data assertions remain mandatory. Extra kernel
drops are reported honestly, not represented as exact controlled loss.

Local validation passed: all 272 vendored Quinn unit tests; 26 transport tests
under each sender policy (two opt-in tests run separately); three consecutive
150 Mbps matrices per policy at 0/0.5/1/3/5% loss, each recovering all 300 frames;
and native C ABI video/audio/input/control loopbacks. Both new boundary tests
fail when the original `<` comparison is restored. The final source is `<=`.
CI-policy tests pass (50). Hosted bootstrap fetches the separately locked vendor
test dependencies; Host builds run their boundary/accounting tests first.

Next: commit/push this candidate and build on GitHub-hosted workers. Hosted
results, exact package source and artifact hashes are not recorded yet. No
1.0.147 package or live hardware acceptance is claimed.

## Unified 1.0.146 test packages

The operator requested one matching test release combining the Client changelog
and macOS Host listener recovery. Both are merged and pushed to main. Exact
package source is `00113c59ee2561564c2014808428a2b26457861d`. Builds run only on
GitHub-hosted builders; signing stays main-only. No installation, GitHub release
publication or branch deletion is requested.

The signed Mac Host [35470297121](https://github.com/instinctual/plank/actions/runs/35470297121)
and Mac Client [35470298554](https://github.com/instinctual/plank/actions/runs/35470298554)
passed build/tests, package, Developer ID, notarization, stapling and signing-key
cleanup gates. Ubuntu Client and both unsigned Mac jobs also passed in ordinary
run [35470297050](https://github.com/instinctual/plank/actions/runs/35470297050).
Privacy run 35470297027 and clipboard run 35470297054 passed. All four product
dependency caches restored and independently verified. Existing compiler warnings
remain; no claim of warning-free compilation or live hardware acceptance.

Linux Host compiled, but both ordinary attempts failed the strict transport loss
test at 5% induced loss. Attempt 1 expected PTS 390000 and received 391500
(frame 260/261); the single unchanged rerun expected 438000 and received 439500
(frame 292/293). Both passed the preceding 0/0.5/1/3% phases and failed
`native.rs:954` in
`native_raptorq_survives_progressive_transport_loss_at_150_mbps`, before RPM
assembly. These are timestamp sequence failures, not frame-size mismatches.
Transport code, test and dependency pin were unchanged from 1.0.143. The focused
investigation and candidate repair are above. Do not call it a runner flake,
bypass the test or keep rerunning unchanged code until green. These 1.0.146
attempts did not produce a Linux Host package.

Three packages are checksum-verified and collected with source provenance under
`artifacts/packages/releases/1.0.146/`; no 1.0.146 Linux Host RPM was produced:

| Package | Bytes | SHA256 |
| --- | ---: | --- |
| `linux/plank-client_1.0.146_amd64.deb` | 15453276 | `7e6a50bda1485ee4f94e5504d0c5d9025538cef17f8ff506824465a1ab59696f` |
| `macos/plank-host_1.0.146_arm64.pkg` | 6621783 | `c76120659b216c921260725c904cd255e2d1fb4401a008762b025b514cd03b5f` |
| `macos/plank-client_1.0.146_arm64.dmg` | 84584642 | `88a7544314bb6fa6e19d7d3278a4c07370f005723b916af67efe41b82883ae4f` |

The operator has been told the signed Mac pair and Ubuntu DEB are ready to test.
The manifest distinguishes passing package gates from functional acceptance.

Preserve the primary checkout's unrelated dirty `rk3576-client` work. Do not relabel the
separately built 1.0.144/1.0.145 feature candidates as a mainline release.

### Client changelog

The main-window version opens an offline, modal, scrollable dialog. Each release
groups short plain-language bullets under Client and Host, omitting empty
sections. Notes come from Client `app/res/changelog.md`, not network requests or
Git messages. The installed version remains dynamic, including branch qualifiers.
Both Client build paths exercise click/keyboard/Close/Escape, focus return,
scrolling, narrow windows, modal isolation and missing-note fallback.
The bundled 1.0.146 notes now include the combined Mac recovery fix.

Feature root `31d353def56c15c5edc39084da46b28587459cc3` and Client
`4c6a3cdb6be60c08082baac3deddb4842e0ce3a6` passed Ubuntu run
[35469086452](https://github.com/instinctual/plank/actions/runs/35469086452)
and unsigned Mac Client run
[35469087970](https://github.com/instinctual/plank/actions/runs/35469087970).
Initial runs 35468917799/35468919210 failed a test comparing raw Markdown with
Qt-normalized text. The corrected assertion compares the rendered document
before/after typing; no runtime workaround or guard relaxation was added.
The old DEB is retained under `candidates/1.0.145-client-changelog/linux/` with
SHA256 `3818e338d1162847eae02a830d02f9f6aff1c0d8fd2e2c7c869e693264b15bfa`.

Keyboard-capture simplification remains discussion only. Off/Fullscreen/Always
still governs the Accessibility event tap and focused-stream ownership, with
preferences copied at connection start. Do not remove or change it without
approval; permission does not supersede capture policy.

### macOS listener recovery

After PLANK authorization as one account and macOS login as another, the new
desktop worker failed binding its control listener with POSIX EADDRINUSE. The
old sign-in process had exited; launchd deferred KeepAlive and the coordinator
treated a successful kickstart as final. An authorized kickstart restored the
old installed Host without an upgrade/reboot. Exact socket state at failure is
unknown; do not present TIME_WAIT as proven. Machine evidence remains private.

The fix reuses the coordinator. After kernel-observed admitted desktop exit
and exact lease release, re-arm only that UID/audit session's ten-attempt budget,
with 1/2/4/8/16-second capped backoff. Duplicate notifications do not replenish
it. Old-session retries are invalidated; late launchctl success cannot erase
an earlier worker exit. Numeric listener failures go to the product log.
No new service, overlapping listener option, token transfer or authority bypass.

Runtime source `c19eef4967a41fef19fb6ffb97cf36783fe3fb52` passed unsigned Mac run
[35468169313](https://github.com/instinctual/plank/actions/runs/35468169313):
recovery policy, 98 callback checks, 509 auth checks, 190 authority checks and
726 session checks across 24 synthetic-capture/real-QUIC scenarios, plus existing
input/audio/clipboard/bundle checks. Two opt-in native transport tests are
excluded from the default Rust unit invocation; they are not hardware tests.
Existing Quinn telemetry dead-code warnings are unchanged.
See [recovery plan](docs/development/plans/macos-listener-recovery.plan).

Live acceptance is still needed after installing the signed combined build:
authorize as one account, then log into macOS as a different account. The Host
must remain reachable while requiring fresh authorization for the new desktop
owner. Also check normal login/logout/reconnect and the grouped Client dialog.

## Last published release and unchanged dependencies

[1.0.143](https://github.com/instinctual/plank/releases/tag/v1.0.143) remains the
latest published release. Exact package root/tag source is
`86c435ed8ba9c5b143048c5a6f8db5d6870606bf`; its four packages, hashes and combined
manifest are retained under `artifacts/packages/releases/1.0.143/`.
See [release notes](docs/releases/1.0.143.md) and prior handoff commit `458f1f6`
for the complete validation history. Its signed Mac Host first run timed out
on a C ABI audio receive; an unchanged rerun and independent ordinary build
passed. The cause remains unconfirmed; no test was weakened.

The combined Client is `270a55cdf5af2f5308fb23537ea3e196e81fda0a`, merged and
pushed to Client main before the parent. Only this gitlink changes for 1.0.146.
Local CI-policy (48 tests), version contract, shell syntax and privacy checks
pass. Other exact runtime pins:

| Input | Commit |
| --- | --- |
| Client common-C | `060f6179f88343327b44d915007f1fb4cede71f1` |
| Linux Host | `cd738510c6588aa086746cf00dca93c17c6bea73` |
| Kymux | `6f3df8e2c9eac41d4bc0ec9d3f1fc9cbf8d1a804` |
| Host build-deps | `c29c4822cb96f5bfeb8640e72601c5cf4e3c3137` |
| Host libvirtualhid | `a0d3aa0cc4d53daa18bfa2f2fbdf848957b6d294` |
| Host common-C | `3a97a58f215323753cfd1180af760ec7e3253538` |

Remaining recursive pins are recorded in the immutable Git trees and manifests.

## Remaining gates and deferred work

Follow [acceptance criteria](docs/development/acceptance-criteria.md): identical
Mac Client bytes on macOS15/27; permissions and revocation; login/logout/user
switch and lock continuity; local emergency shortcuts; toolbar/monitor/input/
Wacom cleanup; exact-format/color hardware paths; packet loss; clipboard immediate
paste and interruption; long-session cleanup; final macOS27 revalidation.

Wallpaper/Screen Saver settings hover lag is deferred, not fixed. Earlier
matching logs showed all 5,675 input events delivered, no spontaneous reconnect,
and hardware HEVC Rext decode, but did not explain the reported 1–2-second lag.
Current metrics do not measure compositor scanout or all pre-dequeue input age.
Do not add speculative queue/permission changes without renewed authorization.

Linux physical-display lease/provenance inconsistency remains unresolved:
requested virtual layout can disagree with realized XRandR inventory after GDM
handoff. Preserve strict composite validation. Unmerged physical-mode/Retina
dropdown PRs, Mac Host pre-27 support and unrelated RK3576 research are excluded.

## Build and workspace policy

Read the canonical release and hosted runbooks before builds. Use hosted
builders, not the development Mac. Keep full CUDA architectures, exact pins,
dependency patch/runtime/package gates and signed Mac temporary-key cleanup.
Main-only signing requires no reviewer approval; never broaden its policy.

Collect exact package bytes using `scripts/package/collect-package.py` with
independent hashes and source provenance. Build success is not live acceptance.
Do not remove unrelated worktrees. Private deployment notes, credentials and
raw machine evidence stay outside Git. Do not restore ENet/GameStream or
private Relay/Wake Agent build inputs.
