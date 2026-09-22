# PLANK handoff

## Current task: virtual-primary PR repairs

The operator authorized fixing the two Client findings in the coordinated
Client #6 / Linux Host #9 / root #10 series. Work uses branch
`virtual-primary-fixes` in `build/worktrees/virtual-primary-fixes` and its
Client worktree. Root base is `db868b4a8930397628c3fb10949c61c1c9ad6a2d`;
Client base is `280f517c44d4f602eb271e38e620f3863b0c69e0`.
Main and the existing release packages remain unchanged. Do not merge or
install without approval.

- Removed the Host-sized presentation-canvas override and its unused helper;
  primary connector ordering retains the existing aspect-preserving renderer
  and matching input/cursor geometry.
- Bound the optional primary hint to the requested output count and an
  unambiguous horizontal layout. Manual bookmarks omit an unmappable hint
  instead of sending index 2 or rejecting an otherwise valid connection.
- Added unit coverage for 0–4 displays, every primary position, reversed
  enumeration, negative origins, ambiguous layouts, differing Host/Client
  aspect ratios and Retina logical input/cursor round trips.

Client fixes are committed and pushed to Client #6 as
`6580f794141b2073eae1110136d8665605eb3803`. Local CI policy checks pass (60).
Exact-source hosted Client checks are pending. Candidate version is 1.0.152;
mainline 1.0.151 packages remain intact.
Client #7 remains a separate reviewed Wacom-focus proposal with live macOS 27
acceptance outstanding; do not silently include it in this repair.

## Mainline 1.0.151 integration (historical base snapshot)

All four 1.0.151 packages subsequently passed and were collected; see main's
HANDOFF at `652718632be33b355df5e1fce989018c9df49f3a` for completion and exact
package provenance. The following base snapshot predates that completion.

The operator authorized committing, pushing and merging all combined work,
then rebuilding all four Host/Client packages. This supersedes the previous
candidate-only restriction. It does not authorize remote installation or
GitHub release publication. Do not claim new live acceptance from merge approval.

Work uses `build/worktrees/macos-session-takeover`, now checked out on main.
Preserve the unrelated dirty RK3576 plan,
HANDOFF and diagnostic material in the primary checkout. Do not add private
Relay/Wake Agent work or unrelated open PRs to this release.

All committed root feature branches are ancestors of the combined branch.
Client takeover work and its refreshed 1.0.151 changelog are pushed to Client
main. Kymux's bounded asynchronous logging is pushed to its main. The Linux
Host pin already matches its main. Root main is pushed at
`c14704801ffa8c5166961c03db8f4bf6c57b08d5`. All four hosted builds use that
exact source and verified dependency caching:

| Product | Run | Status |
| --- | --- | --- |
| Linux Host RPM | 35672399119 | Blocked by paced-baseline latency gate; no RPM |
| Ubuntu Client DEB | 35672399443 | Passed; collected and checksum verified |
| Signed Mac Host PKG | 35672399113 | Passed; collected and checksum verified |
| Signed Mac Client DMG | 35672399343 | Passed; collected and checksum verified |

Three exact-source packages are collected under
`artifacts/packages/releases/1.0.151/`. Both Mac packages passed signing,
notarization, stapling and package gates. No installation or publication occurred.

Linux Host compilation succeeded, and its selected fast-send policy passed
all three 0/0.5/1/3/5% loss matrices (2,700 frames). The additional paced
baseline comparison recovered all 900 frames but failed the first trial's
0.5% phase: p95 scheduled delivery 51.549 ms exceeds the unchanged 50 ms gate.
Packaging stopped before producing an RPM. This is different from root PR
#10's skipped-frame failure. Do not weaken assertions or retry until green.

Compared with successful 1.0.149 Linux Host job 106541725507 at `df06fd58`,
the Linux Host and Kymux pins, transport source, Host build script and loss
test are unchanged. That build's three baseline 0.5% p95 results were
19.402/26.418/22.138 ms. Current CI saves dependencies before product builds;
this does not prove why latency differed. Runner/timer variability is plausible
but unproven. The operator subsequently authorized ignoring the paced-baseline
comparison for now and finishing the remaining build. Host packaging now gates
only its selected policy, preserving all three fast-send loss matrices, their
unchanged thresholds, unit tests and C ABI checks. Paced transport code remains
intact for later review. No shipping transport, encoder or dependency changed.

Rebuild only the missing Linux Host RPM on main. Retain 1.0.151 because no Host
RPM was produced or collected for that version; do not replace the three
already verified packages. Record the new Host root source separately in the
catalog rather than claiming identical root provenance for all four products.

## Combined scope

- Preserve legal maximum-size QUIC datagrams during MTU recovery. No change
  to MTU selection, FEC, encoder targets or send-queue capacities.
- Disable detailed Mac frame timing unless `PLANK_MACOS_FRAME_TIMING=1`.
- Snapshot QUIC telemetry and write it asynchronously outside connection locks;
  bounded logging drops diagnostics instead of blocking media.
- Separate exact-input dependency caches and save them after successful
  verification/bootstrap, before product tests and signing.
- Enforce 150 Mbps/60 fps throughput, delivery-delay and exact recovery gates
  at 0/0.5/1/3/5% loss, three passes per policy, without retry-until-success.
- Ask Take Over/Cancel before replacing another active session on the same
  Mac account, including while locked. Prepare the replacement display before
  decoder initialization; automatic reconnect cannot silently take over.
- Release the displaced client's ordinary input/media path, retain exact
  stream/account consent and reserve launch briefly for the approved client.
- Include Ubuntu's separate Qt SVG image plugin for dialog icons.
- Correct Mac login/desktop control-socket handoff, without sharing the port,
  changing TCP timers, changing authentication policy or adding services.

See `docs/releases/1.0.151.md`, the Client's bundled changelog, and
`docs/development/plans/macos-session-takeover.plan` /
`macos-listener-recovery.plan` for contracts and test details.

## Prior qualification retained

Full intermediate build failures, corrections, package hashes and provenance
remain in HANDOFF at `936b3e2ea061840dd35fa0ad4465bb1bae1ada85`; do not
reinterpret earlier candidate artifacts as new mainline packages.

The 1.0.149 combined candidate passed all four package jobs:
Mac Host 35663307341, Mac Client 35664996000, Ubuntu Client 35666009459,
and Linux Host job 106541725507 in run 35662745109. The Linux Host passed
all six strengthened loss matrices: 5,400 frames, zero unrecovered symbols.
The earlier local paced-baseline failure at frame 329 remains unexplained;
a later hosted pass does not erase it or establish WAN/hardware qualification.
No assertion was relaxed to accept these runs.

Read-only investigation of a 1.0.149 login disconnect proved that the kernel
attributed the desktop listener's EADDRINUSE to an accepted socket of the
exited sign-in worker. Listener/process exit was insufficient; recovery took
about 31 seconds. Private machine evidence remains outside Git. The Client
log was not collected, so its exact terminal reconnect path is not proven.

The 1.0.150 correction awaits peer completion of successful Content-Length
replies, immediately cancels retiring/failed connections and waits for actual
listener/connection cancellation. Signed run 35671124869 at
`b0efdd685ab42fd1375b0bd4ab642528a03ee82d` passed three cross-UID handoffs,
concurrent-listener rejection and a negative control that restores graceful
close and reproduces EADDRINUSE. The full Mac suite, signing, notarization,
stapling, Gatekeeper, package permissions and signing cleanup passed too.
The initial test-first failure had an ambiguous temporary-directory fixture;
the later negative control supplies the unambiguous regression evidence.

Candidate packages remain in `artifacts/packages/candidates/`.
The 1.0.150 Mac Host SHA-256 is
`b868107db92961d7e19dff6594c78e3bd6dcaa33ac5946517ff7c081d4cd2614`.
No automatic installation occurred. Temporary signing policies were removed;
the signing environment permits main only, with unchanged secrets/reviewer rules.

## Dependency provenance

| Input | Commit |
| --- | --- |
| Client | `536a2bfeac35a140d12a14403882572dd11d4d9b` |
| Kymux | `158719b67f83e3d83e8bfba1588420ed84a65cab` |
| Linux Host | `cd738510c6588aa086746cf00dca93c17c6bea73` |
| Client common-C | `060f6179f88343327b44d915007f1fb4cede71f1` |
| Host build-deps | `c29c4822cb96f5bfeb8640e72601c5cf4e3c3137` |
| Host libvirtualhid | `a0d3aa0cc4d53daa18bfa2f2fbdf848957b6d294` |
| Host common-C | `3a97a58f215323753cfd1180af760ec7e3253538` |

Use GitHub-hosted builders and the release/hosted runbooks. Reuse only verified
exact-input dependencies; application compilation/tests/signing run fresh.
Retain full CUDA coverage and every privacy/package gate. The new packages
must be rebuilt from main, not renamed candidates, and collected under
`artifacts/packages/releases/1.0.151/` with their actual source and hashes.
The latest published release remains 1.0.143.

## Remaining acceptance and deferred work

Recheck login-screen to desktop, logout, reconnect and same-account takeover
using two clients with different resolutions/scales, locked and unlocked.
Cancel must preserve the original stream; accepting must drain old input/media,
retain the desktop account, apply the replacement geometry and prevent automatic
take-back. Verify different-account denial, clipboard, audio and input cleanup.
Follow `docs/development/acceptance-criteria.md`; hosted builds are not live tests.

Wallpaper/Screen Saver settings hover lag remains deferred. Linux physical
display provenance inconsistency remains unresolved; retain strict validation.
Keyboard-capture preference removal is discussion only. RK3576 research and
private infrastructure are outside this integration.

## Open PR review

The initial four-PR review was read-only. The operator subsequently authorized
repairing the two Client findings (see current task above), but not merging.
All four PRs remain draft; Client #7 and Host #9 have no newer revisions:

- Client #6, Linux Host #9 (`ebf63ac9`) and root #10 form one virtual-primary
  connector-ordering feature. Root #10's `db868b4a` rebase preserves mainline
  takeover fixes and includes the selected-policy Host test gate. Client #6's
  two findings are repaired at `6580f794`; hosted validation remains pending.
- Client #7 (`af659dbc`) independently reconciles raw-Wacom ownership against
  native AppKit focus. No blocking code defect found; macOS 27 live focus,
  local-dialog release, reconnect and pressure checks remain outstanding.
- The exact proposed display-preparation shell test, eight Host topology tests
  and ten session-context tests passed locally. Existing pinned GoogleTest
  source was used; no product package or hardware deployment was performed for
  this review. Client Qt tests were inspected, not run locally.
- Root #10 CI 35672091412 passed Ubuntu Client and both Mac builds, but its
  Linux Host job failed the progressive-loss test at 5% loss (skipped frame).
  Causation by the display changes is not established. Do not equate earlier
  unchanged rerun passes with resolution of this failure.

Recommended order: qualify Client #7 independently; validate repaired Client #6,
then integrate the paired display components with live macOS 27 validation and
explicit merge approval.
