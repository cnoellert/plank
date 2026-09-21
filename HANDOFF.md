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

Local combined-source checks: all 56 CI-policy tests, Python syntax, shell
syntax and diff whitespace pass. Hosted candidate builds and live acceptance
are pending. No 1.0.149 package is ready yet.

## Source provenance and previous build evidence

The Client implementation is committed and pushed on its matching
`macos-session-takeover` branch at `9aa65c6beb591940e2b5204d9e1ddcb442380c5d`,
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
remains main-only unless the operator explicitly permits this candidate branch;
a question requesting that narrow temporary permission is outstanding. Ordinary
branch Mac jobs compile/test but produce no signed end-user installers.

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
