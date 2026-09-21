# PLANK handoff

## Active: logging, dependency-cache and loss-performance review fixes

The operator authorized detailed-frame-tracing cleanup, moving logging outside
the QUIC connection lock, splitting dependency-cache fingerprints, and
strengthening the loss-test performance gate from the read-only code review.
Work is on `macos-frame-tracing` in
`build/worktrees/mouse-edge-recovery`, branched from `quinn-mtu-boundary` at
`1f0a1a63d061734de208c2d0d05ad00f99e0195b`. The earlier MTU changes are retained
in that base, not merged to main. Preserve the primary checkout's dirty RK3576
work. Other review findings are not part of these changes.

The operator authorized commit/push and hosted branch builds, explicitly not a
merge. Candidate `1.0.148-macos-frame-tracing` was committed and pushed at
`ad1a4a40e429e7712a4c01dd1aa4d74e68e5c3bb`. All four ordinary hosted jobs run
from that exact source. Mac jobs remain unsigned compile/test checks under the
main-only signing policy. Do not install or publish a release.

Hosted run [35654558827](https://github.com/instinctual/plank/actions/runs/35654558827)
passed both Mac compile/test jobs. Ubuntu Client passed compilation and package
gates but GitHub artifact finalization failed with an intermediary HTTP 403,
after the upload completed. One same-source, Ubuntu-only recovery build,
[35655809810](https://github.com/instinctual/plank/actions/runs/35655809810), passed
including upload. Its Rust/Cargo/FFmpeg caches restored and independently
verified; restore took 24 seconds and bootstrap two seconds. Application builds
were fresh. This was an upload recovery, not a retry of the loss-performance
failure. Linux Host passed build, transport qualification, RPM gates and upload
on its first hosted attempt. The original all-product run remains red solely
because of the first Ubuntu artifact-finalization failure; the separate Ubuntu
recovery run is green. Both runs are complete; nothing is still building.
Privacy run 35654558749 and clipboard run 35654558815 passed.

The hosted Host passed all six strengthened loss matrices (three per policy):
5,400 frames recovered, zero unrecovered FEC symbols and zero unintended proxy
kernel drops. Across all phases, worst p95 delivery was 33.774 ms, worst
delivery 34.196 ms, worst submission 36.137 ms and worst receive gap 19.311 ms.
No assertion, policy or timeout was changed, and no loss test was retried.
Both policies' 34 ordinary transport tests and four logger tests passed, along
with native/C ABI loopbacks and the vendor boundary/snapshot regressions.
The input suite passed 25 shuffled iterations (13 tests per iteration; three
`/dev/uhid`-dependent cases explicitly skipped). Production RPM retains
`BUILD_TESTS=OFF`, complete CUDA architectures and root-owned `0700` log directory.
Mac Host's opt-in/default-off tracing test passed on SDK27; existing compiler
warnings remain. These are build/portable-test results, not hardware acceptance.

Checksum-verified packages are collected under
`artifacts/packages/candidates/1.0.148-macos-frame-tracing/`:

| Package | Bytes | SHA256 |
| --- | ---: | --- |
| `linux/plank-client_1.0.148-macos-frame-tracing_amd64.deb` | 15453724 | `1c9dbab7405f2b27509bb59814dd4c57e6c6a924a1d2c9fe7f870e30ae816f7a` |
| `linux/plank-host-1.0.148-0.macos_frame_tracing.1.el9.x86_64.rpm` | 8599335 | `9bfc46ea8f96ee3a1415f735df743f269419e53be87d096a24bfa0737a50dd18` |

The adjacent manifest records the exact root and product gitlinks. Package
validation passed; functional validation remains `not-recorded`. There are no
signed Mac installers from this branch build. Neither local builders nor
hardware targets were used, and nothing was merged, installed or released.

### Strict loss-test performance gate

The test-only matrix now sends 900 exact payloads at 150 Mbps/60 fps, with
180 frames (three seconds) at each 0/0.5/1/3/5% loss level. One continuous
availability schedule prevents backpressure from lowering the offered load or
resetting latency at phase boundaries. Every phase requires at least 142.5 Mbps
submitted/received payload throughput, p95 delivery <=50 ms, maximum scheduled
submission/delivery <=100 ms and receive gaps <=100 ms. Absolute timeouts and
measured completion times both enforce the bounds. Original exact bytes, PTS
order and zero unrecovered FEC assertions remain. The loopback runner defaults
to release mode; three required passes stop on the first failure, not retries.
The release runbook documents measurement semantics and loopback limitations.
No product sender, FEC, buffer, MTU or system settings changed for this work.

Validation: eight deterministic metric tests cover slow senders, catch-up stalls,
per-phase tail latency, boundary gaps, incomplete/invalid samples, delayed send
completion, exact limits and nominal load. All 34 ordinary transport tests pass
with telemetry disabled and with each telemetry-enabled sender policy; four
logger tests pass with each enabled policy.
Both real all-lane loopbacks pass. Linux fast-send passed all three strengthened
matrices: 2,700 frames recovered, zero unrecovered symbols and zero proxy kernel
drops. Every phase sustained 150 Mbps/60 fps; worst per-phase p95 delivery was
12.224 ms, worst delivery 17.323 ms and worst receive gap 26.219 ms.

**The paced baseline failed the first strengthened matrix.** Frame 329 missed
its 100 ms scheduled submission deadline, about 5.59 seconds into the matrix
(0.5% phase). The preceding zero-loss phase already finished 51 ms late; proxy
cleanup reported zero kernel drops. The failure is retained, not retried or
waived. It demonstrates a schedule/backpressure failure that the earlier short,
recovery-only test could pass; it does not by itself establish the root cause.
The later authorized hosted build passed both policies without changing the
test, as recorded above. That qualifies those package gates on the hosted
builder; it does not explain or erase this first local failure. Preserve both
results and investigate the environment/performance difference before claiming
portable timing reliability. Do not silently skip either policy or relax the
bounds. Live hardware performance qualification has not been performed.
All 56 CI-policy tests, runner shell syntax and whitespace checks pass.

### Independent dependency-cache fingerprints

Hosted jobs now restore/verify and seal/save independent v2 groups for Rust,
Cargo downloads, Linux FFmpeg, Boost, Mac native libraries and Qt, as applicable
to each product. Cargo manifest/lock changes no longer invalidate FFmpeg/Boost;
Mac FFmpeg patches no longer invalidate Qt. Rust changes also invalidate Cargo.
The Linux Host's jointly built codec tree and the Mac native libraries' shared
install prefix remain coupled groups; independent archives never overlap.
Mac Client now caches Rust/Cargo downloads too, not only native libraries/Qt.

Existing bootstrap commands were extracted, without version or build-flag
changes, into independently hashed `scripts/ci/dependencies/` recipes. Shared
bootstrap only sequences them. One local composite action handles all four
products and skips saves for individual exact hits. The old Mac-only cache
helper was removed in favor of the common implementation. Narrow allowlists,
exact receipts, required patch checks, pristine Client FFmpeg archive, fresh app
builds, clean-bootstrap bypass, public-PR no-save and signing-cleanup-before-save
rules are preserved. No fallback restore keys or signing-policy changes.

Validation: all 55 CI-policy tests pass, including per-input invalidation,
mixed hits/misses, CLI prepare/seal/verify, corrupt/incomplete restore rejection,
non-overlapping cache paths and deployment/signing boundaries. Bootstrap and
all recipe shell syntax checks pass; workflow/composite YAML parse and diff
whitespace checks pass. No platform dependencies were compiled/downloaded for
these local tests. The subsequent hosted builds above passed cold population
for all four products and warm restore/verification for Ubuntu Client. Warm
qualification of the other products and mixed-hit hosted builds remain gates.
New v2 namespaces needed one initial cold population;
old v1 caches are not restored or deleted. The build runbook documents the
groups and labels previous v1 timings as historical evidence only.

### QUIC logging outside the connection lock

Vendored Quinn's `stats()` now only copies an owned telemetry snapshot under
the connection lock. The Kynet adapter enqueues it after Quinn returns and
releases the guard. One process-wide writer formats and writes the unchanged
log line off the media task, using an eight-snapshot bounded queue. Producers
never wait for queue space or perform fallback I/O; slow/full/failed logging
drops diagnostic samples. Teardown never joins the writer, so final diagnostic
samples are best-effort. RTT/loss statistics, counter values, wire format, FEC,
MTU, pacing and queue-capacity policy are unchanged. Feature-disabled builds
have no snapshot fields or writer. The vendor patch notes document the paired
Quinn/Kynet dependency and tests.

Validation: 273 vendored Quinn tests; 26 transport tests with telemetry disabled
and under each telemetry-enabled sender policy; four logger tests under each
enabled policy (blocked sink, bounded queue, failed sink, preserved format and
bounded arithmetic); native Rust/C ABI loopbacks; and three consecutive 150 Mbps
loss matrices per sender policy at 0/0.5/1/3/5% before the gate was strengthened.
Each earlier matrix recovered all 300
frames with zero unrecovered symbols and zero unintended proxy kernel drops.
The two normally ignored live transport tests were explicitly run by the
loopback runner. CI-policy tests pass (51). Host package preflight now also runs
the vendor snapshot regression; ordinary transport tests exercise the real
adapter logger through the product lockfile. No new dependencies or lockfile
changes. These are local portable tests, not platform-package/hardware acceptance.

Kynet changes are committed and pushed on `macos-frame-tracing` at
`158719b67f83e3d83e8bfba1588420ed84a65cab`, before the parent gitlink.
Client `270a55cdf5af2f5308fb23537ea3e196e81fda0a` and Linux Host
`cd738510c6588aa086746cf00dca93c17c6bea73` pins are unchanged. Keep the new
adapter logger and root integration test with the vendor snapshot change.

### Opt-in macOS capture frame tracing

`PLANK_MACOS_FRAME_TIMING=1` in the capture worker's runtime environment is now
required to allocate the bounded trace. Unset/empty/other values disable it.
The setting is read once per capture session. Default capture skips trace-only
timestamp sampling and the detailed shutdown dump; normal capture summary and
error logs remain unchanged. Enabled format, 8,192-record/120-second bounds and
post-callback-drain lifetime are preserved. No encoder, transport, audio or
Client policy changes. The macOS build runbook documents activation/removal.

The existing portable frame-timing test now covers default-off, ten disabled
values, exact opt-in, silent disabled output, per-session lifetime, limits and
the original dump format. GCC C11 warnings-as-errors and Clang ASan/UBSan runs
pass locally. The regular macOS Host build already runs this test. No macOS
Objective-C build or live capture test has run for this change yet.
All four fixes are committed and pushed for the authorized branch build:
`bf526c3` (frame tracing), `85a3e1f` (QUIC logging), `d2f5960` (dependency caches),
and `e70ef7b` (loss-performance gate). Candidate source and build results are
above; there is no merge, installation or signing-policy change. The existing
1.0.147 artifacts below do not contain these fixes. The local paced-baseline
performance failure remains unexplained despite the hosted pass; it is not
permission to relax assertions or bypass that comparison. Next: authorized
hardware acceptance, investigation of that timing difference, and separate
approval if signed Mac candidates or a merge are desired.

## Pending: Quinn MTU-boundary repair, 1.0.147 candidate

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

Candidate source `9afebe0ca7905259fd114a8423fc46aa733f235b` is committed and
pushed. Hosted run [35474124195](https://github.com/instinctual/plank/actions/runs/35474124195)
passed all four products on its first attempt. Build policy, privacy
run 35474124177 and clipboard run 35474124191 also passed. The Linux Host passed
all six 150 Mbps matrices with all 300 frames recovered each time, zero
unrecovered source symbols and zero unintended proxy kernel drops. The hosted
proxy's effective receive buffer was 2,097,152 bytes. No retries or relaxed
assertions. Native C ABI tests, RPM gates and 25 shuffled input-suite iterations
passed (13 tests per iteration; three `/dev/uhid`-dependent tests explicitly
skipped). Production RPM remains `BUILD_TESTS=OFF`.

Mac checks were unsigned compile/test qualification, not distribution installers
or hardware acceptance. Existing compiler warnings remain. No signing policy,
machine settings or installed products changed. All four dependency caches were
rebuilt for the changed pinned test inputs and saved after success.

Checksum-verified packages and manifest are collected under
`artifacts/packages/candidates/1.0.147-quinn-mtu-boundary/`:

| Package | Bytes | SHA256 |
| --- | ---: | --- |
| `linux/plank-host-1.0.147-0.quinn_mtu_boundary.1.el9.x86_64.rpm` | 8579573 | `30cd5f08a5f30fc6c863763616451ff50a657d84596d900dabfc4b7ac6de8c43` |
| `linux/plank-client_1.0.147-quinn-mtu-boundary_amd64.deb` | 15453156 | `971e050cf747b6438e679161f40179ec1bab8fe69f924f83b20320570c69cf30` |

The RPM version/branch and root-owned `0700` log directory were independently
verified after download. Candidate is ready for authorized hardware testing;
it is not merged, installed or published. A later mainline release must be
rebuilt from main, never relabeled.

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
