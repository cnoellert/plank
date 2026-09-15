# PLANK handoff

Read AGENTS.md and the platform build runbook before work. Read the private
notes' README before machine-specific work; deployment information stays outside Git.

## Current state

- Working branch: `macos-media-recovery`, based on main `cf0f47d`.
  Host-only candidate 1.0.106 removes offline virtual-display settings
  reapplication, adds recoverable audio overruns/bounded audio restart and
  follows default-output volume/mute. See
  `docs/development/plans/macos-media-recovery.plan`.
  Portable ring tests and CI policy tests pass. Hosted Mac compilation,
  signing and live acceptance are pending; do not claim this candidate fixed
  the observed runtime failures until those gates pass. No installation or
  session interruption has been performed.
- Latest release: [v1.0.105](https://github.com/instinctual/plank/releases/tag/v1.0.105).
  All four packages were clean-bootstrapped and rebuilt on GitHub runners at
  `78e068edf9240de44e2aea5949dd94df713468b0`. The annotated tag identifies
  that exact build commit, not subsequent documentation commits.
- Notes: `docs/releases/1.0.105.md`. Packages, manifest and checksums:
  `artifacts/packages/releases/1.0.105/`.
- No workstation packages were installed for this release. Fresh live hardware/
  session tests were not performed; manifests correctly retain functional
  validation `not-recorded` and package validation `passed`.
- `github-builds` and `macos-display-recovery` still exist locally/remotely,
  fully merged with no outstanding work. Branch deletion was not requested in
  the notes update; do not infer permission to remove other repositories.

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
Custom branch restrictions remain `main` and `macos-display-recovery`, not a
wildcard. Certificate exports, passwords and notarization credentials remain
environment secrets. Temporary runner keychains are removed on success/failure.

Do not restore the initial reusable-workflow wrapper: it received empty
environment secret values; the direct protected job is qualified. Missing
secrets fail before bootstrap. No per-run human approval is needed.
Exact-input dependency caching remains optional, unimplemented future work,
not an outstanding release blocker or an automatically authorized task.

## Maintained inputs (1.0.105)

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

Next: run the new synthetic audio/display tests on the hosted Mac builder,
build a signed branch-qualified Host candidate and collect its exact package.
Do not interrupt a production session to install it. Acceptance
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
