# PLANK handoff

Read AGENTS.md and the platform build runbook before work. Read the private
notes' README before machine-specific work; deployment information stays outside Git.

## Current state

- Preparing 1.0.111: dynamic Mac Match Client dimensions (even 2–8192 per
  axis) use the same native-pixel lookup before authentication and streaming.
  Host mode registration keeps presets plus one requested custom 60 Hz mode;
  offline settings mutation remains forbidden. Linux EDID selection is unchanged.
  Shared topology fixtures now run during hosted Mac Client builds.
  Live 1.0.110 woke the desktop but exposed a subsequent capture-reconfiguration
  race; 1.0.111 adds a bounded, authorized geometry-settle wait without repeating
  authentication. Synthetic TLS tests cover delayed readiness and permanent
  unavailability. Not yet built or accepted; full Client retry-lifecycle work
  remains outstanding.

- 1.0.110 passed hosted run 35060603472 at
  `fe2996c567aab27c210ff6087648adcb362f2c7c`, including 18 display recovery checks.
  Collected and installed with matching payload hash and signature checks.
  Package SHA256 `0c41d5e08b652b570ae5bf2af76e04cddd2e34ab11b0f8392794f26af89b90ba`;
  installed binary `8b18176d60fab53c57331ece2f5e6a1b6afdc1261d088dcad90514c1abbda9b0`.
  Authentication passed; topology still returned HTTP503 because geometry was
  queried immediately after wake during display reconfiguration. Not accepted.
  Authenticated topology recovery now also wakes the current
  desktop before the first virtual-display preparation. Previously a fresh
  desktop worker required topology before preparation, but only recovered an
  already-created owned output. Bootstrap recovery is wake-only, bounded and
  cancellation/ownership checked; no physical modes or sleep settings change.
  Synthetic coverage adds bootstrap wake, authorization loss, concurrent
  admission, wake failure and missing-display timeout.
  Next requested work: dynamic native-pixel Match Client modes for Mac Hosts;
  retain manual presets and Linux EDID behavior. Keep changes separately tested.

- 1.0.109 passed hosted run 35059613856 at
  `7608a4b75c343e00935da40747669c8edd7b6779`; 19 isolated-channel cases,
  509 auth-session checks, topology recovery and existing package/signing gates.
  Collected `candidates/1.0.109-macos-auth-recovery/macos/`, size 6,608,164,
  SHA256 `3bb9aff9d594ba49f8bc20153e5a01252241e9ec4afc863611188a39e725b14f`.
  Transferred/verified but NOT installed; affected Host still runs 1.0.108.
  Operator stopped the retrying Client: connections and diagnostic growth stopped;
  isolated real PLANK authentication then succeeded in 0.174 seconds.
  The remaining topology failure is HTTP503 after successful authentication;
  Client displays Qt network enum403, NOT HTTP403/permission denial.
  Endpoint discovery remains HTTP200. Client retry-lifecycle simplification is
  still outstanding; do not claim it was fixed by Host-only cooldown changes.

- Follow-up candidate 1.0.108 is built and installed on `macos-auth-recovery`.
  After the token-capacity correction, native directory verification passed
  but PLANK still returned denied on the affected Mac. Diagnostics subsequently
  identified retry cooldown. Helper unavailability maps to busy, not bad credentials;
  bounded fixed-stage diagnostics distinguish directory, private-channel and
  desktop-authority failures without account/credential/token logging.
  Full isolated-helper tests join the hosted Host package gates. No security
  check was removed; no Client/Linux or display-power change. Do not describe
  this diagnostic candidate as an accepted login fix before live testing.
  Hosted run 35059051412 passed from e7fa9cec2d44af880ec55c9e5fc5d52d477928fa:
  509 session checks, 18 isolated-channel cases, 27 account-policy cases,
  seven negative verifier cases, 32 topology failure/relogin cycles, existing
  package gates and signing/notarization. Initial run 35058870303 failed on a
  new enum/class name collision; corrected before successful build/install.
  Package SHA256 `7f78c8e7547bd1dc1e23b15820046e3aee13ce7448b0e129402438c6aa3a9235`,
  size 6,608,276; catalog `candidates/1.0.108-macos-auth-recovery/macos/`.
  Installed executable matches payload SHA256
  `9529409b8d338292e4e99a38d190004a04b5399f5dd0a51dfac52be99ee97b28`.
  Live failures now identify retry-cooldown, without observed directory rejection.
  Operator requested to quit the reconnecting Client for an isolated test.
  Candidate 1.0.109 clears cooldown after successful verification only; failed
  attempts retain backoff and all verification remains serialized/bounded.
  This fixes legitimate logins competing with successful reconnect attempts,
  not the separate inactive-display issue or full reconnect lifecycle yet.

- Active fix: `macos-auth-recovery`, isolated worktree, candidate 1.0.107.
  Fixes abandoned macOS setup-token capacity exhaustion; see
  `docs/development/plans/macos-auth-recovery.plan`. No Client/Linux changes.
  Source/package commit `b7407097fef78f10952f9969d6711d92ed454890` is pushed.
  Signed hosted run [35057106376](https://github.com/instinctual/plank/actions/runs/35057106376)
  passed: 504 authentication checks, 32 real-TLS failed topology/relogin cycles,
  success/revocation/timeout recovery, 11 synthetic display checks, existing
  audio/pen/installer gates, signing/notarization/stapling/Gatekeeper.
  Collected `artifacts/packages/candidates/1.0.107-macos-auth-recovery/macos/plank-host_1.0.107-macos-auth-recovery_arm64.pkg`;
  6,607,323 bytes; SHA-256
  `f32a23094dabc1df8d0f2468c0694c12853f5a770c6d6fae3a232e20827c5fe2`.
  Source/manifest and transferred checksum match. Functional validation remains
  not-recorded; next is operator reconnect testing. No new
  Client is required. Display wake failure is separate and not fixed here.
  Protected signing now also permits this exact candidate branch, without
  widening access for other branches or public PRs. Known unchanged Quinn
  dead-code warnings do not affect the passing package gates.
  Operator-authorized upgrade on the affected Mac succeeded. Installer signature,
  notarization and transferred package hash passed; installed executable matches
  the extracted payload (`67970b312c8e5665b34bc9dda43ec1831e8549f6432771abaf66a3a82085a264`).
  Installed version and deep/strict signature verified; coordinator and desktop
  worker restarted and the control listener is active. Capture still reports an
  inactive display; no power settings or desktop session were changed. This is
  installation/startup validation, not successful reconnect acceptance.
  The separate `rk3576-client` research
  branch and its uncommitted notes remain untouched in the primary worktree.

- Working branch: `main`. Accepted macOS media recovery is merged/pushed at
  `4b634071d0aa96c5568e90068f5f42b7cd953365`.
  Host-only 1.0.106 removes offline virtual-display settings
  reapplication, adds recoverable audio overruns/bounded audio restart and
  follows default-output volume/mute. See
  `docs/development/plans/macos-media-recovery.plan`.
  Code is committed/pushed at `9af28c1356adada0dc70a1513d80551b37c5479d`.
  Signed hosted run [35032611418](https://github.com/instinctual/plank/actions/runs/35032611418)
  passed and its installer is collected under
  `artifacts/packages/candidates/1.0.106-macos-media-recovery/macos/`.
  Package: `plank-host_1.0.106-macos-media-recovery_arm64.pkg`, 6,606,315 bytes;
  SHA-256: `46fc5bbb8501dee80028bbf284507e476103f318cce866c76d7c8c5767e369dc`.
  Transfer hash and source manifest match the runner. The operator confirmed
  volume/mute works, reported good behavior so far and approved merge/rebuild.
  This is not an exhaustive long-duration or sleep/recovery qualification.
  Mainline signed rebuild passed at that exact merge commit in
  [35035036281](https://github.com/instinctual/plank/actions/runs/35035036281).
  Collected: `artifacts/packages/releases/1.0.106/macos/plank-host_1.0.106_arm64.pkg`,
  6,606,256 bytes; SHA-256:
  `bdb59fb5ddf2df0afb4704920684b83d81c9b8975602e3d643bed5dd1c8d3e49`.
  Runner provenance and transferred checksum match. Audio/display/pen/installer
  tests, signing, notarization, stapling and Gatekeeper passed again on main.
  Package validation is `passed`; functional validation remains `not-recorded`
  for this exact mainline installer. Release notes: `docs/releases/1.0.106.md`.
  Published [v1.0.106](https://github.com/instinctual/plank/releases/tag/v1.0.106)
  with the signed Host PKG, manifest and checksums. The annotated tag identifies
  the exact merge/build commit above, not subsequent documentation commits.
  GitHub asset digests match all three local files. Published checksums use flat
  asset filenames; the local catalog retains platform subdirectories.
  No agent installation or session interruption.
  No Client update is needed. All maintained gitlinks below are unchanged.

Candidate validation: 11 synthetic display-recovery checks, 100 audio-tap
lifecycle races, synthetic output-volume/mute policy and actual recovery
controller with fake audio boundaries all pass on SDK/OS 27. Existing Opus
fixture passed 6,998 checks; pen fixture passed 1,130 non-posting checks;
installer passed 29 checks. Developer ID signing, notarization, stapling,
Gatekeeper and temporary-keychain cleanup passed. Local portable ring test
passed 100,000 concurrent blocks, wraparound and overflow/resumption, including
Clang ASan/UBSan outside the sandbox. GCC ASan could not link its missing local
runtime; sandboxed LeakSanitizer cannot inspect threads. Neither limitation was
treated as a product failure or a passed test. Local CI policy (14), bundle
permission tests (7 passed/1 Mac-only skipped) and 23 installer shell checks pass.
- Previous full-platform release: [v1.0.105](https://github.com/instinctual/plank/releases/tag/v1.0.105).
  Its Linux Host and Linux/macOS Clients remain current; 1.0.106 updates only
  the macOS Host.
  All four packages were clean-bootstrapped and rebuilt on GitHub runners at
  `78e068edf9240de44e2aea5949dd94df713468b0`. The annotated tag identifies
  that exact build commit, not subsequent documentation commits.
- Notes: `docs/releases/1.0.105.md`. Packages, manifest and checksums:
  `artifacts/packages/releases/1.0.105/`.
- No workstation packages were installed for this release. Fresh live hardware/
  session tests were not performed; manifests correctly retain functional
  validation `not-recorded` and package validation `passed`.
- Deleted the fully merged `github-builds`, `macos-display-recovery` and
  `macos-media-recovery` branches locally and remotely at the operator's request.
  Only `main` remains in this repository; release tags and history are retained.
  Other repositories and their branches were not changed.

## Release evidence

All four exact-source runs passed:

| Product | GitHub run |
| --- | --- |
| Linux Host RPM | [35018358540](https://github.com/instinctual/plank/actions/runs/35018358540) |
| Linux Client DEB | [35018361548](https://github.com/instinctual/plank/actions/runs/35018361548) |
| Signed macOS Host PKG | [35018364501](https://github.com/instinctual/plank/actions/runs/35018364501) |
| Signed macOS Client DMG | [35018367944](https://github.com/instinctual/plank/actions/runs/35018367944) |

Verified SHA-256 values:

- Host RPM: `7aa4a71077ba22b836738ec53152c966af76555375da1514cc811065f3efb1be`
- Client DEB: `eb4c918e0c5c52fc3d5b0ef0bc16d340a89393971b71c8384f5491be0ec44985`
- Host PKG: `6e99f7509e31a17a097ee56c9f295f267bea5cd5a00dabf09582433646b94f92`
- Client DMG: `e88a62aee26d553d836ed7dbe6266441bf8037fa1623a27c307d4e602ea6fa54`

The collector verified transfers and retained source/gitlinks and sizes.
Local checksum verification passed; GitHub asset digests matched all four
packages, manifest and release checksum file. Published checksums use flat
asset filenames; local catalog checksums use platform subdirectories.
Temporary download/upload staging was removed after verification.

Both Mac packages passed Developer ID signing, notarization, stapling,
Gatekeeper and temporary-keychain cleanup. The Mac Host passed ten synthetic
recovery tests, four real TLS recovery scenarios, eight permission tests and
29 installer checks. Linux Client exact-decoder, private-FFmpeg, dependency,
version, reconnect and no-autostart gates passed. Host RPM manifest and
log-directory gates passed. Linux Host retains BUILD_TESTS=OFF and complete
CUDA architecture coverage. Local CI/version, package-collection, build-path
and bootstrap-input tests passed. These are not hardware acceptance results.

## Accepted fixes

Authenticated macOS topology requests can recover an inactive PLANK-owned
virtual display, with bounded authority/ownership checks and retained real
geometry. No physical mode changes, duplicate displays, TCC mutation or active
stream recovery. See `docs/development/plans/macos-display-recovery.plan`.

Host 1.0.103 had owner-only app directories/resources: ordinary users could see
a prohibited icon or "damaged or incomplete" launch error despite notarization.
Assembly now uses public distribution permissions, independently checked in the
app, staging and final PKG BOM/extraction. Never broaden private keys/state to
repair app access.

The operator accepted candidate 1.0.104-macos-display-recovery; merge commit:
`13e0c3248d223fd63d84919517df092d3e6d41ef`. Candidate source:
`ca36e48123d58cc84104f6fab5df59c35d14f05e`, signed run `35011167754`.
The Host-only mainline 1.0.104 used
`9284c204b6974e322e480442a0b0b91767420d2a`, run `35013030130`.
Those packages remain separately cataloged; 1.0.105 supersedes them.
Broad acceptance does not imply exhaustive sleep/ownership-transition tests.

Linux Host, shared Client and transport dependency revisions are unchanged
from 1.0.103. The corresponding 1.0.105 packages are rebuilds, not renamed files.

## Build and signing policy

Use GitHub-hosted workers for the requested releases, not a local Mac fallback.
All four clean hosted build paths and both signed Mac package paths are
qualified. Local builders have not been retired; hardware test roles remain
separate. Read `docs/development/build/github-builds.md` and the release build
runbook before the next build.

Signing is an explicitly dispatched direct job in `build.yml`, selected with
`signed=true`; ordinary push/PR builds never receive signing credentials.
At the operator's request, `macos-signing` has no reviewers or wait timer.
Custom branch restrictions are `main`, `macos-display-recovery` and the explicit
`macos-media-recovery` and `macos-auth-recovery` candidates, not a
wildcard. Certificate exports, passwords and notarization credentials remain
environment secrets. Temporary runner keychains are removed on success/failure.

Do not restore the initial reusable-workflow wrapper: it received empty
environment secret values; the direct protected job is qualified. Missing
secrets fail before bootstrap. No per-run human approval is needed.
Exact-input dependency caching remains optional, unimplemented future work,
not an outstanding release blocker or an automatically authorized task.

## Maintained inputs (unchanged from 1.0.105 through 1.0.106)

| Maintained input | Package source commit |
| --- | --- |
| Linux Host | `9329784ac41f50cbec0c9d76badfd22227ec5e5f` |
| Shared Client | `c032da3ae0d7e816a7a6f9bb9a51dd489d4d369c` |
| Transport | `912ece5c64787997f978673ca60d313898a3548c` |
| Host common-C | `775943b5ac5e5100a3c2b1b89d9e21151dea4f29` |
| Client common-C | `b9650552f98d97f6e30c9f007115c6246f0809e5` |
| Client mDNS engine | `b7a5a9f225d5e14b39f9fd1f905c4f505cf2ee99` |
| Host build dependencies | `caf0495d5e6baff94f349853d4a59e3779a451a0` |
| Host virtual HID | `93d57db99a5bf4b1a9fbbc7ad1371671725b7e97` |

The local checkout need not initialize every recursive dependency for notes;
builders initialize exact product inputs. Uninitialized local submodules do
not imply missing release dependencies.

## Remaining gates and publication boundaries

Mainline macOS Host 1.0.106 is rebuilt, collected and checksum-verified, ready
for manual installation. The merged feature branch has been deleted.
Volume/mute is operator-validated. Longer app/alert audio, device changes,
sleep/reconnect/topology and login/logout remain follow-up coverage, not
blockers invented beyond the operator's merge approval. Inspect the new audio
reason/overrun/restart logs if it fails.
The initial failure cause is not proven; overflow no longer permanently
disables audio. An offline display that never returns still fails boundedly
rather than forcing settings into WindowServer. Do not interrupt a production
session to install. Acceptance
criteria still apply, including final macOS release revalidation and live
recovery/ownership transitions.

Treat tracked files/messages as public. See `docs/security/private-information.md`
and `docs/security/publication-review.md`. Source audits were bounded, not
proof against unknown/encoded secrets; credential rotation remains the operator's
responsibility. Do not reimport private historical development commits or publish
old 1.0.100/1.0.101 preparation packages: newer build-path fixes do not repair
their metadata retroactively. Never patch signed bytes or relabel packages.

ENet/nanors and inherited transports remain absent from current builds.
Host common-C is header-only; Client common-C is a separate maintained branch.
Preserve attribution without restoring retired code. Private infrastructure,
PLANK2 and historical backups remain independent of the public Host/Client
repository and release. Historical validation detail remains in Git history,
focused documentation and the earlier artifact manifests.
