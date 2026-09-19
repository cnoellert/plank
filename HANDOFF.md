# PLANK handoff

## Active unified 1.0.146 build

The operator requested one matching test release combining the Client changelog
and macOS Host listener recovery. Merge both into main and rebuild all four
public Host/Client packages on GitHub-hosted builders. Signing stays main-only.
No installation, GitHub release publication or branch deletion is requested.
Combined package gates are pending at this checkpoint.

Work in `build/worktrees/mouse-edge-recovery`, now on root main. Preserve the
primary checkout's unrelated dirty `rk3576-client` work. Do not relabel the
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
input/audio/clipboard/bundle checks. Two hardware-dependent Rust tests remain
ignored; existing Quinn telemetry dead-code warnings are unchanged.
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
