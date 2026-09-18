# PLANK handoff

## Active candidate: immediate Linux mouse buttons

Work is isolated on root `host-input-release`, based on main `51cd817`, in
`build/worktrees/host-input-release`. Linux Host source is
`cd738510c6588aa086746cf00dca93c17c6bea73`, a follow-up to
[Host PR #8](https://github.com/instinctual/plank-host-linux/pull/8).
The operator explicitly chose to remove the inherited absolute-mouse delayed
left-release/synthetic-right-click workaround instead of retaining the timer
and extending its disconnect cleanup. The agreed rationale is posted on the PR.

The candidate removes that timer, sentinel values and pending-release state.
Mouse transitions now reach the platform backend synchronously in their
received order. Held-button disconnect cleanup and the stale connection-lease
check remain. Keyboard, scrolling, normalized pen, raw-HID Wacom, Client and
transport code/pins are unchanged. This does not claim to repair every previous
input issue or all pre-existing concurrency between stream replacement and
cleanup. The unrelated `linux-fast-send` candidate is not included.

Candidate version is `1.0.139-host-input-release`. Hosted Rocky build/test
validation is pending. CI now builds and repeats the fake-backend input suites
25 times with shuffled order after producing the ordinary `BUILD_TESTS=OFF`
RPM. Tests cover immediate releases, right-button holds, rapid clicks, cleanup,
stale leases and reconnects; fixture teardown removes test-owned callbacks and
held input before replacing the fake backend. Missing UHID hardware is a skip.
Local CI-policy tests (43), shell syntax and whitespace checks passed.

No deployment, live mouse/Wacom acceptance, merge or release has occurred.
Obtain the operator's current Host/Client hardware pair and installation window
before interrupting a session. Test mouse clicks, held-button drags, right-click
menus and repeated disconnect/reconnect, then real Wacom tip/buttons/pressure
and tablet margins. Do not substitute the fake backend for those live gates.
The original RK3576 research checkout and Linux fast-send worktree are preserved.

## Current release: 1.0.137

The operator requested rebuilding all public Host/Client packages and publishing
a release. Package-source root is
`41cffcddaf487acd84b293fe1792d3406bfe8d64` on `main`. Runtime changes were
accepted in the 1.0.136 clipboard candidate before merging; this is a fresh
mainline rebuild, not relabeled candidate artifacts. See
[release notes](docs/releases/1.0.137.md).

All packages use GitHub-hosted builders. Both Mac packages require signing,
notarization and stapling. Exact-input dependency caches are independently
verified; application/transport compilation and packaging run fresh. No package
installation, hardware test, dependency upgrade or pending PR is part of this
release operation. All builds and artifact checks passed.
[v1.0.137](https://github.com/instinctual/plank/releases/tag/v1.0.137) is published
as the latest release with four packages, manifest and SHA256SUMS. GitHub's
server-side digests match all six local assets. The annotated tag names the
exact package-source root above, not the subsequent evidence-only notes commits.

| Gate | Hosted run | State |
| --- | --- | --- |
| Four-product ordinary build | 35362841568 | Passed |
| Signed/notarized Mac Host | 35362882541 | Passed |
| Signed/notarized Mac Client | 35362884456 | Passed |
| Privacy checks | 35362841435 | Passed |
| Clipboard regressions | 35362841434 | Passed |

The signed Client passed all 156 native Qt results, including 23 clipboard
results. The Mac Host passed native named-pasteboard tests for bidirectional
data, queue pressure, generations, ownership and denied authority. The Linux
Xvfb suite passed 13 production-backend cases and five negative controls,
including exact 512 KiB, cumulative overflow and timeout recovery. Shared wire
validation passed under ASan/UBSan. Both signed Mac jobs passed notarization,
stapling, package checks and temporary-key cleanup. These are build/test
results, not new live hardware acceptance.

Local validation passed: release-version contract, all seven portable CTest
suites (including twelve dependency-patch cases), 43 CI-policy tests and
whitespace/privacy checks. Linux Client gates include runtime dependency
closure, private FFmpeg, visible version, persistent logging and no autostart.

All four packages are checksum-verified under
`artifacts/packages/releases/1.0.137/`. Exact package names, hashes and target
platforms are in the release notes and catalog manifest. Linux Host completed
a cache-cold dependency bootstrap; all nine required patches passed bootstrap,
package preflight and cache sealing, including the Loader repair. The RPM
log-directory ownership and payload gates passed. Other product dependency
caches restored and were independently verified. No deployment was performed.
Release build, tag, publication and verification are complete. There is no
pending release operation or automatic deployment. The next work is an
operator-selected task or explicitly authorized remaining qualification below.

## Accepted changes and scope

Mac Host ↔ Mac Client plain-text clipboard, the shared 512 KiB limit, outgoing
validation and queue-pressure repairs are merged into maintained branches.
Common-C was merged first, then Client/Linux Host and the parent gitlinks.
The accepted candidate package-source root was
`16c5b99817747ab76d25741fbce37d3399907366`; its tested runtime code and pins are
unchanged by release preparation. The operator reported successful use, but did
not enumerate every stress case. See
[the clipboard plan](docs/development/plans/macos-host-clipboard.plan).

Clipboard is desktop-worker-only on Mac Host. Mac launch schema 3 explicitly
negotiates it; upgrade Host and Client together. LoginWindow and Linux Clients
negotiate no clipboard. Existing encrypted message types/ports are reused.
Mac Host, Linux Host and Mac Client share framing/UTF-8 validation. Transient
queue pressure retains unsent chunks. Teardown preserves newer locally copied
text; clipboard contents never enter logs. Files/images/rich text are excluded.
Mac Client ↔ Linux X11 Host support remains intact.

Immediate-paste ordering is still a stress gate: native pasteboard writes are
asynchronous and no applied-write acknowledgment exists. Queue-retry tests
alone do not establish an atomic paste guarantee.

The actual Vulkan Loader repair was already in the build-deps pin and release
1.0.135. New parent verification independently proves that required patch during
bootstrap, cache validation and package preflight. Only deliberately omitted
Loader test-file deletions are allowed; Git filenames are parsed NUL-delimited.
Twelve regression cases cover missing/conflicting patches, empty groups,
unexpected changes, Unicode paths and the narrow deletion exception. No runtime
graphics code, driver or dependency pin changed in this follow-up.
See [qualification evidence](docs/development/reviews/vulkan-loader-qualification.md).
The earlier cache-cold Host run 35360266594 passed all nine required patches,
fresh compilation, RPM gates and cache sealing; it was not a new hardware test.

Already released behavior remains: Mac hotkey capture re-arms after a Spaces
return, Accessibility prompts occur outside streams, toolbar RTT uses shared
telemetry, and Metal overlay replacement preserves the old texture until the
new one is ready. Prior release detail is in
[1.0.135 notes](docs/releases/1.0.135.md), not a pending task list.

Completed branch cleanup removed fully integrated branches, including the root
and Linux Host Vulkan repair branches. The parent preserved relevant history
and integrated verification without restoring superseded pins/version changes.
Old worktrees remain detached and recoverable. No worktree source or artifacts
were deleted. Do not repeat cleanup from historical HANDOFF instructions.

## Exact 1.0.137 source pins

Package root `41cffcddaf487acd84b293fe1792d3406bfe8d64` and immutable gitlinks
identify the recursive source. Builders initialize exact product inputs;
locally uninitialized dependencies are not missing release inputs.

| Input | Commit |
| --- | --- |
| Shared Client | `6663d5692ecf9eaa12f401b3d3a7781103ae2f1b` |
| Linux Host | `b8abf72c2b41c96edab4c62303a97bd3464de9ea` |
| Kymux | `6f3df8e2c9eac41d4bc0ec9d3f1fc9cbf8d1a804` |
| Client common-C | `ef8ac14c87ce3dc6fa2bc1f4a08f6e61371739d1` |
| Client qmdnsengine | `920c097ffa742e2968290f15d4dde6693aec02e5` |
| Host build-deps | `c29c4822cb96f5bfeb8640e72601c5cf4e3c3137` |
| Host libvirtualhid | `a0d3aa0cc4d53daa18bfa2f2fbdf848957b6d294` |
| Host common-C | `3a97a58f215323753cfd1180af760ec7e3253538` |
| Host common tooling | `f9d91e1d29b7473f58e43acde4579da4e56c4abe` |
| Host GoogleTest | `52eb8108c5bdec04579160ae17225d66034bd723` |
| Plasma protocols | `382dfabda886d3f2f5c067b22e5a22376685ba78` |
| Wayland protocols | `819004adb3ab7e46f3fa3caef05b96e20434b244` |
| x264 | `0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee` |
| Vulkan Headers | `ee2ec5fd83dafce291024683b50dc89219333076` |
| Vulkan Loader | `b8b96a2862bff1eed468e602d43f706beae89cf1` |
| NVIDIA codec headers | `e844e5b26f46bb77479f063029595293aa8f812d` |
| Host common-C doxyconfig | `419127bad87f49b2d45fa957ea7302abbb49c01f` |


Other unchanged recursive pins remain in those Git trees. NVIDIA driver
qualification stays capped at 595.91.07. Kymux maintenance does not restore
application datagram pacing. Historical candidate evidence remains in Git,
release notes and package manifests.

## Remaining gates and known issue

Broad operator acceptance is not evidence that every case was individually
tested. Follow [acceptance criteria](docs/development/acceptance-criteria.md):

- Identical Mac Client package on macOS15/27; real Wacom pressure, unplug,
  focus, reconnect and release recovery.
- Permission startup timing, denial/revocation, explicit capture release,
  local emergency shortcuts, disconnect/menu/Dock cleanup.
- Live pinned-toolbar updates/dragging/hide-reveal after the Metal repair.
  The separately reported transient menu-bar line remains unattributed.
- Clipboard interruption/ownership/large-transfer/immediate-paste stress, identity color and
  profile-specific hardware paths, packet loss and long-session cleanup.
- Final macOS27 release revalidation; hosted builders cannot establish live
  hardware, permissions, display or network acceptance.

A Linux physical-display lease inconsistency remains open. Runtime state
claimed one virtual1920x1080 output while XRandR showed two physical outputs
spanning5120x2160. This state crossed GDM→desktop; topology combined the requested
virtual layout with the real two-output inventory. Client provenance validation
correctly rejected it. Relevant Host lease and Client validation code is unchanged
from1.0.124; an upgrade/restart exposing an older defect remains possible.
Unused outputs are omitted from the temporary MetaMode and apply checks command
success rather than realized geometry. The exact reactivation cause is unproven.
The operator elected a manual reboot; no permanent repair was implemented or
verified. Investigate realized topology/handoff when authorized; do not weaken
the Client guard or claim that the reboot fixed the underlying problem.

Physical-monitor mode-change PRs and the pending Retina bookmark dropdown remain
excluded. Do not confuse already-accepted native Retina Match Client behavior
with that unmerged preference. Mac Host support below27 is discussion only.

## Workspace and build policy

The earlier release used `build/worktrees/pr-integration`, now occupied by
the independent `linux-fast-send` candidate; its directory name is not the branch. The primary
checkout remains unrelated `rk3576-client` research with uncommitted notes and
diagnostics. Preserve it. Do not clean or switch that checkout during release.
Other review worktrees/branches are not permission for a broad cleanup.

Use GitHub-hosted builders for these releases, not the development Mac or an
ordinary runtime machine. Read the canonical release and hosted build runbooks
before each build. Exact-input dependency caches are allowed and independently
verified; application/Rust objects and packages always build fresh. A full
release rebuild is not a new dependency-bootstrap qualification unless requested.
Retain full CUDA architectures and all patch/private-FFmpeg/package gates.

Signed Mac builds are explicitly dispatched from an allowed branch through
`macos-signing`, with no manual reviewer/wait timer at the operator's request.
Public push/PR jobs receive no signing authority. Certificates/notarization
credentials remain protected environment secrets; temporary runner keychains
must be cleaned on success/failure. Never repair signing by copying personal
keychains, broadening branch access, or relaxing package checks.

Package manifests separate package checks from functional acceptance. Collect
exact bytes/provenance using `scripts/package/collect-package.py`; tag the
package-source root, not a later evidence-only documentation commit. Published
SHA256SUMS uses flat download names, local catalog checksums use platform paths.

Treat tracked files and commit messages as public. Machine details, credentials
and raw captures stay in the private notes locations documented by AGENTS.
Read their local README before machine-specific work. Do not restore retired
ENet/nanors/GameStream code, private infrastructure or historical build inputs.
PLANK2 and private Relay/Wake Agent projects remain separate.
