# PLANK handoff

## Branch cleanup and Vulkan follow-up

The operator authorized cleanup of redundant branches. Removed 21 remote branch
references across the six affected public repositories and 30 fully merged local
branches, including old `stationconnect/main` aliases in build-deps/libvirtualhid.
Every removed tip was first proven reachable from its maintained branch. Clean
attached worktrees were detached at their existing commit; source files, build
artifacts and commit history were not removed. The primary `rk3576-client`
checkout and its uncommitted research remain untouched. Open-PR branches,
maintained defaults/product branches, PLANK2 and private repositories are retained.
Ten stale `macos-signing` deployment branch policies were removed; only `main`
currently has signing authorization. This does not add manual approval or change
the protected secrets.

The operator authorized the Vulkan follow-up. Integration is on
`vulkan-preflight` in `build/worktrees/pr-integration`. The actual Loader repair
is already present in build-deps pin
`c29c4822cb96f5bfeb8640e72601c5cf4e3c3137`; no runtime code or dependency pin
changes are needed. The parent now independently checks the required Loader
patch alongside FFmpeg/x265, permits only deliberately omitted Loader test-file
deletions, and parses NUL-delimited Git filenames. Twelve regression cases and
CTest registration cover missing/conflicting patches, empty groups, unexpected
modifications, Unicode paths, and the narrow deletion exception.

The integration retains old root branch history but selectively restores only
the verification changes and qualification notes, not its superseded package
version or Host gitlink. The old Linux Host branch contains only an earlier
build-deps pin, already superseded by current main. See
[the qualification record](docs/development/reviews/vulkan-loader-qualification.md).
Local/hosted validation and retirement of those old references remain pending;
no release or installation is implied by this build-only follow-up.

## Accepted clipboard changes: merged, not yet released

The operator reported that the clipboard changes work, accepted them and
authorized merge. Mac Host ↔ Mac Client plain-text clipboard, the shared
512 KiB limit, outgoing validation and queue-pressure repairs are now merged
into main. Common-C changes were fast-forwarded into its maintained
`plank/client` and `plank/host` branches first, followed by Client, Linux Host
and the parent repository. No tested code or gitlink changed during merging.
The accepted merge is on main, not the unrelated primary
`rk3576-client` checkout. This merge does not publish a release or deploy software.
See [the plan](docs/development/plans/macos-host-clipboard.plan).

Implementation adds a desktop-worker-only native pasteboard backend and Mac
launch schema3 with explicit clipboard opt-in/result. LoginWindow and Linux
Clients negotiate no clipboard. The existing encrypted types/ports are reused.
Mac Host framing and UTF-8 validation share the portable protocol helper;
Linux Host and Mac Client use that validator too. Transient queue pressure
retains unsent chunks rather than restarting a copy or disconnecting video.
Clipboard contents never enter logs; teardown preserves newer local copies.

Candidate package-source root is `16c5b99817747ab76d25741fbce37d3399907366`.
The accepted feature tip is `a949440792afa978d1172b8a906a8306243e614f`;
it and the following recursive pins are now on their maintained branches.
Later acceptance-only notes do not change candidate package provenance.
Changed recursive pins:

| Input | Commit |
| --- | --- |
| Client | `6663d5692ecf9eaa12f401b3d3a7781103ae2f1b` |
| Linux Host | `b8abf72c2b41c96edab4c62303a97bd3464de9ea` |
| Client common-C | `ef8ac14c87ce3dc6fa2bc1f4a08f6e61371739d1` |
| Host header-only common-C | `3a97a58f215323753cfd1180af760ec7e3253538` |

Other dependencies remain at the release pins below. Portable wire tests passed
under ASan/UBSan, C11/C++17 ABI checks passed, as did 43 CI-policy tests and six
portable CTest suites.

| Gate | Hosted run | State |
| --- | --- | --- |
| Four-product ordinary build | 35355443932 | Passed |
| Signed/notarized Mac Host | 35355443904 | Passed |
| Signed/notarized Mac Client | 35355447200 | Passed |
| Privacy checks | 35355443955 | Passed |
| Clipboard regressions | 35355443952 | Passed |

The signed Client passed all 156 native Qt results, including 23 clipboard
results. The Mac Host passed its named-pasteboard tests (bidirectional data,
queue pressure, generations, ownership and denied authority). The Linux Xvfb
suite passed 13 backend cases and five negative controls, including exact 512 KiB,
cumulative overflow and timeout recovery. Shared wire validation passed under
ASan/UBSan. Both signed Mac jobs passed notarization, stapling, package checks
and temporary-key cleanup. These are not live hardware acceptance claims.

Verified packages are in
`artifacts/packages/candidates/1.0.136-macos-host-clipboard/`; the manifest
records source, target OS, checksums and package-only validation. Mac Host PKG
SHA256 is `e90bae689aaaa6b034355626c9da01b157962aac3687200eee69356ed2c0fa3d`;
Mac Client DMG is `e356a68e6be2d3d7417682772d656e6a70fa7b90343264ed8757bd1a4c0c45ef`;
Linux Client DEB is `4719c2b2cafe66b1bbe3112c7fc488565bd5620d9cf6cc6db474d1d0c6a32e72`;
Linux Host RPM is `ebc73b52dfb55a2e4ced0cb66b0525681ff057c0955deeefd22dcfab328eeed9`.
The agent did not install packages or modify a production machine. The operator
tested and accepted the candidate; individual stress cases were not enumerated.

Merge is complete. A new mainline package/release build is a separate next step;
do not relabel the accepted branch artifacts. Keep large/interrupted transfers,
Spaces/focus and login/logout/reconnect ownership in the qualification matrix.
Use matching peers because Mac launch schema 3 is a coordinated change.
Immediate-paste ordering remains an explicit stress gate:
native pasteboard writes are asynchronous and no applied-write acknowledgment
exists; queue-retry tests alone do not establish an atomic paste guarantee.

## Current release: 1.0.135

The operator accepted the macOS Spaces-return shortcut fix and requested a full
release. Root, Client and Linux Host changes are merged/pushed to main.
[v1.0.135](https://github.com/instinctual/plank/releases/tag/v1.0.135) is published
with all four freshly built packages, manifest and SHA256SUMS. Its annotated tag
identifies exact package-source root
`af74d8b8fdf9bb58cf096eeb10fb5aaba01a19d4`, not the later evidence-only notes
commit. Every package was built on GitHub-hosted runners; no branch package was
relabeled. No deployment was performed. Remaining open PRs are excluded.

1.0.134 was withheld before publication because of the live Spaces-return defect.
Its successful packages are historical evidence, not the current release.
See [1.0.135 release notes](docs/releases/1.0.135.md) for the complete change list
since the previous published release, v1.0.124.

| Gate | Hosted run | Current state |
| --- | --- | --- |
| Four-product ordinary build | 35330999876 | Passed |
| Signed/notarized Mac Host | 35331000308 | Passed |
| Signed/notarized Mac Client | 35331003759 | Passed |
| Privacy checks | 35330999945 | Passed |
| Clipboard regressions | 35331000013 | Passed |

Local validation passed: 43 CI-policy tests, six portable CTest suites, five
keyboard-capture guards, two Metal-overlay guards, three Quit-lifecycle guards,
seven fullscreen guards, 14 reconnect guards, release-version contract and
whitespace checks. These are not new native hardware tests.

Both Mac packages passed signing, notarization, stapling and temporary-key
cleanup. The signed Mac Client passed all153 native Qt results and five Metal
overlay groups. Dependency caches restored and were independently verified.
Linux package/dependency/private-FFmpeg/version/payload gates passed, including
Host log-directory ownership and Client no-autostart checks. Package manifests
correctly keep functional validation separate from build acceptance.

All four packages are checksum-verified under
`artifacts/packages/releases/1.0.135/`. GitHub's server-side SHA256 digests match
the packages, manifest and flat-filename release checksum file.

| Package (relative to the catalog) | Bytes | SHA256 |
| --- | --- | --- |
| `linux/plank-host-1.0.135-1.el9.x86_64.rpm` | 8579937 | `198ef27454243d9300c1b11cdd861540f4defef906797cdf561996bd614800bd` |
| `linux/plank-client_1.0.135_amd64.deb` | 15451432 | `910a7030ed68cd68172fbf22a45d0276024419a9ca1f92fe2853c0de2d782f49` |
| `macos/plank-host_1.0.135_arm64.pkg` | 6613304 | `811452516a1688b685216e0abcdccb497bf0dc67b2c91915545bc03e49599245` |
| `macos/plank-client_1.0.135_arm64.dmg` | 86618191 | `e910f0b39573ea0cfba5f45c4d42a651d6dfe9879fed2d05bedd703060601803` |

The published release remains unchanged; the accepted clipboard merge is above. Remaining
qualification items below are not claims of failed acceptance or authority to
disrupt a live machine. Branch cleanup is recorded above; no pending PR was merged.

## Accepted fix and integration scope

The operator confirms the 1.0.135-macos-hotkey-focus candidate works after
swiping away from and back to the fullscreen stream. Earlier clicking inside
the stream did not recover capture.

The authorized public CGEvent tap remains registered through ordinary focus
loss; background keys pass through before their key data is inspected.
Returning re-arms forwarding on the first eligible key, using native AppKit
application/key-window/active-Space state rather than cached SDL focus or a
later timer tick. Explicit capture release and revoked permission still block
re-arm. Revocation/teardown remove the tap; the existing silent timer handles
authorization and disabled-tap recovery. No Linux or Host behavior changed.

Candidate source was root `42e2d835d0effdcb31a83d39d5e87d0f878afdd1`,
Client `d2532825b99edb3237d50d0773dab6ab352d4d2f`. Ordinary four-product
run35329265662 and signed Client run35329265614 passed. The signed job passed
153 native Qt results (27 keyboard-capture results, including suite setup/
cleanup), five Metal-overlay groups, dependency verification, package gates,
signing, notarization, stapling and temporary-key cleanup. Candidate DMG:
`artifacts/packages/candidates/1.0.135-macos-hotkey-focus/macos/plank-client_1.0.135-macos-hotkey-focus_arm64.dmg`;
SHA256 `03824969ca2319aae9c65ef5a87cb29469d4c2c6579be6f6518c624aaa92e69d`.
The operator installed/tested it; the agent did not deploy it.

The release also contains reviewed integration work since1.0.124:

- Plain UTF-8 clipboard synchronization is macOS Client ↔ Linux X11 Host only,
  operator-accepted after both peers were upgraded. No Mac Host or Linux
  Client backend, files or images. Large-transfer/ownership/reconnect stress
  remains separate from that acceptance.
- Mac system shortcuts obey the existing capture preference and stream focus.
  Accessibility permission is requested in the ordinary launcher at startup
  or idle Settings, never behind an active stream. CLI autoconnect requires
  prior launcher authorization. Captured Command-Q and explicit menu/Dock Quit
  retain their separate tested lifecycle. No private CGS grab path.
- Network RTT reuses the existing once-per-second statistic in the compact
  toolbar. Metal overlays retain the complete old texture until replacement
  is uploaded and exchanged under lock; allocation failure preserves it.
- Mac multi-display Metal presentation and allowlisted raw Wacom forwarding,
  including bounded timeout-release recovery, are merged. One Apple Silicon
  Client targets macOS15+ using SDK27; runtime checks retain newer APIs. Mac
  Host remains27+. Linux input queue ordering/release and virtual-HID Pause-key
  release fixes are included.
- Reviewed dependency updates include x264, Vulkan with allocation-failure
  repair/reproducible patch tests, Rustls0.23.45, mDNS and CI Actions/maintenance.
  NVIDIA headers remain compatible with the hard driver ceiling595.91.07.
  Kymux's new pin is maintenance-only; no application datagram pacer returns.

Focused details:
[clipboard follow-up](docs/development/clipboard-review-followup.md),
[Mac integration](docs/development/macos15-integration-review.md),
[dependency maintenance](docs/development/dependency-maintenance.md),
[Mac Client runbook](docs/development/build/macos-client-build-runbook.md).

## Published 1.0.135 source pins

Package root `af74d8b8fdf9bb58cf096eeb10fb5aaba01a19d4` and these immutable
gitlinks identify the complete recursive source; no dependency is selected by a
moving branch at build time. Builders initialize exact product inputs. Locally
uninitialized dependencies are not missing release inputs.

| Input | Commit |
| --- | --- |
| Shared Client | `d2532825b99edb3237d50d0773dab6ab352d4d2f` |
| Linux Host | `f3ab763a31288f392fb94743cb47ee580d9cc01e` |
| Kymux | `6f3df8e2c9eac41d4bc0ec9d3f1fc9cbf8d1a804` |
| Client common-C | `16a7a503b2cfafad12faeedbc67257f7a1c0deb8` |
| Client qmdnsengine | `920c097ffa742e2968290f15d4dde6693aec02e5` |
| Host build-deps | `c29c4822cb96f5bfeb8640e72601c5cf4e3c3137` |
| Host libvirtualhid | `a0d3aa0cc4d53daa18bfa2f2fbdf848957b6d294` |
| Host common-C | `88fd5ac594ce9fa8b7e01530a7830aba3fc0b986` |
| Host common tooling | `f9d91e1d29b7473f58e43acde4579da4e56c4abe` |
| Host GoogleTest | `52eb8108c5bdec04579160ae17225d66034bd723` |
| Plasma protocols | `382dfabda886d3f2f5c067b22e5a22376685ba78` |
| Wayland protocols | `819004adb3ab7e46f3fa3caef05b96e20434b244` |
| x264 | `0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee` |
| Vulkan Headers | `ee2ec5fd83dafce291024683b50dc89219333076` |
| Vulkan Loader | `b8b96a2862bff1eed468e602d43f706beae89cf1` |
| NVIDIA codec headers | `e844e5b26f46bb77479f063029595293aa8f812d` |
| Host common-C doxyconfig | `419127bad87f49b2d45fa957ea7302abbb49c01f` |

Other unchanged recursive pins are retained by those Git trees. Previous
candidate/run/hash details remain in Git history and their artifact manifests;
do not interpret historical HANDOFF instructions as current tasks.

## Remaining gates and known issue

Broad operator acceptance is not evidence that every case was individually
tested. Follow [acceptance criteria](docs/development/acceptance-criteria.md):

- Identical Mac Client package on macOS15/27; real Wacom pressure, unplug,
  focus, reconnect and release recovery.
- Permission startup timing, denial/revocation, explicit capture release,
  local emergency shortcuts, disconnect/menu/Dock cleanup.
- Live pinned-toolbar updates/dragging/hide-reveal after the Metal repair.
  The separately reported transient menu-bar line remains unattributed.
- Clipboard interruption/ownership/large-transfer stress, identity color and
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

Release work is in the separate `build/worktrees/pr-integration` directory,
currently on `main`; its directory name is not the branch. The primary
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
