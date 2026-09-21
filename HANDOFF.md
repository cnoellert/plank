# PLANK handoff

## Active combined candidate: 1.0.149-macos-session-takeover

The operator requested a fix for connecting from a second client while an
existing Mac session is locked, and explicitly requested combining it with all
unmerged 1.0.148 review-hardening work. Work is in
`build/worktrees/macos-session-takeover`, branch `macos-session-takeover`.
Its base is the complete `macos-frame-tracing` branch at
`23db130d087e81b8f853b42cf3716ccacc996ae0`, descended from main `dd6fb04`.
Main is unchanged; do not merge until the operator accepts the candidate.
Preserve unrelated dirty RK3576 research in the primary checkout.

The unified source includes:

- Quinn's inclusive MTU-boundary correction: legal maximum-size datagrams are
  not discarded when the path recovers. No MTU/FEC/buffer policy change.
- Default-off detailed Mac frame timing, enabled only by
  `PLANK_MACOS_FRAME_TIMING=1` in the capture worker environment.
- Owned QUIC telemetry snapshots and bounded asynchronous logging outside the
  connection lock. Full/failed logging drops samples, never blocks transport.
- Independent verified dependency caches for Rust, Cargo, FFmpeg, Boost,
  Mac native libraries and Qt, as applicable. No application/signing cache.
- Strict 150 Mbps/60 fps loss gates at 0/0.5/1/3/5%, three passes per policy,
  fixed throughput/latency/recovery assertions, no retries after a failure.
- Explicit same-account Mac takeover before display preparation, with a
  responsive Client confirmation and normal old-stream input/media teardown.

## Takeover implementation and qualification

The diagnosed Host was still actively streaming at the lock screen; the
second connection hit the existing active-stream HTTP 409 before display
preparation. It was not a stale token or a proven unsupported resolution.
Private evidence remains outside Git. No machine was restarted or upgraded.

The Client must prepare its final display size before decoder initialization.
A typed conflict carries a random per-stream UUID, not account/host identity.
Fresh GUI sign-in asks Take Over/Cancel. Consent waits only on the worker for
at most two minutes. CLI and automatic reconnect never implicitly take over.
The Host validates the same verified UID/UUID, peer, current graphical scope
and exact existing stream UUID. It drains the ordinary stop path before
changing geometry, with a fifteen-second replacement reservation to stop
reconnect races, including shared-NAT setup-token supersession. Matching Host
and Client are required by the synchronized feature-mask fixture.

See [plan](docs/development/plans/macos-session-takeover.plan) and
[release notes](docs/releases/1.0.149.md). New tests cover authentication denial,
reservation expiry/revocation, exact-session consent, a real TLS/QUIC transfer
with a synthetic display, and Qt accept/cancel/Escape/timeout responsiveness.
These tests must pass on the appropriate hosted builders; local syntax checks
are not Mac execution or hardware acceptance.

Local combined-source checks: all 59 CI-policy tests, Python syntax, shell
syntax and diff whitespace pass. Initial hosted runs 35662191961 and
35662506372 were superseded/cancelled before completing product qualification
to include final Client shutdown and authenticated-bookmark routing guards.
Privacy and clipboard checks also passed at combined source `df06fd5`.
Its unsigned Mac Host job in run 35662745109 passed 520 authentication checks
and the real TLS/QUIC synthetic-display takeover scenario. The first Client
attempts exposed a changelog false positive in the Linux source gate and an
outdated Mac topology assertion; both are corrected. The added source-gate
tests require ripgrep explicitly in the policy job (35663778957 caught the
missing test prerequisite). No test was disabled or assertion relaxed.

Signed Mac Host run 35663307341 passed signing, notarization, stapling and
package validation. Its exact package is collected under
`artifacts/packages/candidates/1.0.149-macos-session-takeover/macos/`.
SHA-256: `58f91ddd57f2ee80c4a6726fb35c5a459c466d0adb1d8044e7c35e62c2e6176e`.
Linux Host job 106541725507 in run 35662745109 passed package/input-lifecycle
gates and all six strict loss matrices: 5,400 frames, zero unrecovered symbols.
Its RPM is collected in the matching `linux/` directory.
SHA-256: `41622a46da5fe201c0e6da874551bf8a6d3b2edeaca3e51396cb350e5f4f5d3a`.
The matching Client packages remain in progress; do not call the combined
candidate ready or claim live acceptance yet.

## Source provenance and previous build evidence

Host builds use root `df06fd58cd0fe3c81c264fc37c0543c91e2672f7`.
Client attempts at root `b4d5ba6a2e8800e63eb026bf291ff1c3323f49cc` (Ubuntu run
35664009589, signed Mac run 35664012122) compiled and passed the topology suites.
The consent test performed accept/cancel/Escape correctly but failed its
zero-warning gate because its fixture lacked the dialog icons and used native
Mac controls instead of the product's Material style. Those test inputs are now
corrected; replacement builds are pending. Since `df06fd5`, changes only affect
test inputs, source-gate prerequisites and release-note prose exclusion; no Host
or Client product implementation changed. Record each package's actual source
commit, not a rewritten common provenance.

Replacement Client builds use root `60b16b9a1744d9706e616f9c46f6535cee8484a9`:
signed Mac run 35664996000 remains active. Ubuntu run 35664993625 exposed a
missing SVG reader plugin: `qt6-svg-dev` does not provide the separate
`qt6-svg-plugins` runtime with no-recommends installation. The CI/bootstrap
dependency list, DEB Depends and finished-package gate now explicitly require
that plugin. No product logic or test assertion changed for this correction.

The operator requested fixing cache-save ordering while builds continue. New
workflow code saves independently verified dependencies immediately after a
successful bootstrap, before product build/tests/signing. Signed Mac bootstrap
and cache-save are separate credential-free steps; the signing helper no longer
repeats bootstrap. Failure/PR/clean-bootstrap restrictions and exact fingerprints
remain intact, with no product/signing caches. Existing running jobs use their
original committed workflow and are not cancelled for this CI-only change.

The Client implementation is committed and pushed on its matching
`macos-session-takeover` branch at `a29dad91987f1989dbcbfab11166879459d938f8`,
based on `270a55cdf5af2f5308fb23537ea3e196e81fda0a`, before its parent gitlink.
Current retained dependencies:

| Input | Commit |
| --- | --- |
| Kymux | `158719b67f83e3d83e8bfba1588420ed84a65cab` |
| Linux Host | `cd738510c6588aa086746cf00dca93c17c6bea73` |
| Client common-C | `060f6179f88343327b44d915007f1fb4cede71f1` |
| Host build-deps | `c29c4822cb96f5bfeb8640e72601c5cf4e3c3137` |
| Host libvirtualhid | `a0d3aa0cc4d53daa18bfa2f2fbdf848957b6d294` |
| Host common-C | `3a97a58f215323753cfd1180af760ec7e3253538` |

The full prior validation record is retained in HANDOFF at `23db130`, not
duplicated here. 1.0.148 source `ad1a4a4` passed both unsigned Mac jobs and Linux
Host packaging in [35654558827](https://github.com/instinctual/plank/actions/runs/35654558827).
Ubuntu compiled/packaged there but artifact upload returned HTTP 403; the
same-source Ubuntu-only [35655809810](https://github.com/instinctual/plank/actions/runs/35655809810)
passed including upload. Packages and provenance remain under
`artifacts/packages/candidates/1.0.148-macos-frame-tracing/linux/`.
Those bytes do not contain this takeover work.

All six hosted strengthened loss matrices passed: 5,400 recovered frames,
zero unrecovered symbols and zero unintended proxy drops. Preserve the earlier
local paced-baseline failure (frame 329 missed its 100 ms submission deadline):
the hosted pass does not explain or erase it. Do not relax bounds, rerun until
green or claim portable timing reliability. Live WAN/hardware remains untested.

Main's 1.0.146 Mac pair and Ubuntu DEB are in
`artifacts/packages/releases/1.0.146/`. Its Linux Host packaging failed the
old loss gate; the MTU fix in this combined branch addresses the reproduced
boundary drop. The latest published release remains 1.0.143.

## Build and release boundary

Use GitHub-hosted builders and read the release/hosted runbooks. No installation,
release publication or main merge is authorized for this candidate. Retain full
CUDA coverage, exact dependency patches and all package/privacy gates. Signing
was explicitly authorized for this candidate only. Temporary branch policy
`60637043` in the `macos-signing` environment permits `macos-session-takeover`;
delete that exact policy after the signed builds finish, preserving the main
policy. No environment secrets or reviewer rules were changed. Ordinary branch
Mac jobs compile/test but produce no signed end-user installers.

Collect exact package bytes with hashes/provenance in the versioned catalog;
never relabel earlier packages. Feature package/visible versions include
`macos-session-takeover`. Do not remove unrelated branches or worktrees.

## Remaining acceptance and deferred work

Test two clients with different resolutions/scales while the Mac is locked and
unlocked. Cancel must leave the first session unchanged; accepted takeover must
stop old input, retain the logged-in account, show the requested new dimensions
and prevent the displaced client's automatic return. Recheck normal reconnect,
login/logout, different-account denial, clipboard, audio and input cleanup.
Follow the remaining [release gates](docs/development/acceptance-criteria.md).

Wallpaper/Screen Saver settings hover lag remains deferred, not fixed. Linux
physical-display provenance inconsistency remains unresolved; retain strict
validation. Keyboard-capture preference removal is discussion only. Unrelated
RK3576 research and private Relay/Wake Agent work are not part of this candidate.
Keep private deployment information, credentials and raw captures outside Git.
