# PLANK handoff

Read AGENTS.md and the platform build runbook before work.

## Ready for operator test: signed GitHub Host 1.0.104

`macos-display-recovery` is committed/pushed, not merged. The first signed
GitHub Host candidate passed in
[run 35011167754](https://github.com/instinctual/plank/actions/runs/35011167754),
exact source `ca36e48123d58cc84104f6fab5df59c35d14f05e`. This includes both
authenticated display recovery and the 1.0.103 app-permission correction.

Package: `artifacts/packages/candidates/1.0.104-macos-display-recovery/macos/plank-host_1.0.104-macos-display-recovery_arm64.pkg`
(6,604,549 bytes). SHA-256:
`08727763e3c970c89b91b7930c1032bd5b1b6876764bdca7eea8c9cd4365b706`.
The collector independently verified the transferred bytes and retained the
exact root/gitlinks in the manifest. Developer ID signing, Apple notarization,
stapling, Gatekeeper, final BOM/extracted-payload permissions, all recovery and
portable tests passed. The temporary CI signing keychain was deleted and its
search list restored. No build ran on the dedicated development Mac.

Next: operator installs the candidate and verifies ordinary-account app launch,
reconnection after the owned virtual output becomes inactive, and login/logout.
No candidate install, live recovery acceptance, merge or release publication is
claimed. Client/Linux runtime and dependency gitlinks remain unchanged.

## macOS app permissions correction

Host 1.0.103's signed PKG preserved owner-only app directories and icon/signature
resources. Gatekeeper accepted notarization, but an ordinary account could not
open the app. The authorized installed test Host was repaired with exact 0755
bundle-directory / 0644 resource changes; ordinary-user deep strict signature
verification and Gatekeeper now pass. No keys, settings, logs, services or TCC
policy were changed. Finder launch has not been user-retested yet.

The correction is alongside display recovery on `macos-display-recovery`,
1.0.104. Public app assembly uses explicit distribution permissions without
changing private installed-state policy. New gates check the app, payload and
finished PKG BOM/extraction. All eight permission tests, including an actual
unsigned PKG roundtrip, passed on the GitHub Mac. Its complete ad-hoc app bundle
also passed under caller umask 077. The signed installer is recorded above. Existing 1.0.103
release bytes are unchanged; earlier package review missed this permission gate.

Clean GitHub Host build/test passed at `9d0203563465e97fc26fa18afd851e66ad7d6191`
in [run 35008511989](https://github.com/instinctual/plank/actions/runs/35008511989).
Ten synthetic display recovery checks and four real
loopback TLS scenarios (success, failure, revoked authority, timeout) pass.
Initial runs exposed ARC test-case scoping and OpenSSL 3 PKCS#8-default fixture
issues; those were corrected, not bypassed. Host/Client/transport gitlinks are
unchanged. No live display-recovery test or candidate installation yet.

## macOS inactive-display recovery candidate

Branch `macos-display-recovery`, version 1.0.104, addresses authenticated
topology reads failing after the agent-owned sign-in display becomes inactive.
Recovery is attempted only after a valid peer-bound token, only for the owned
virtual display, and never while a stream is active. The existing real geometry
snapshot remains authoritative. Recovery reports remote user activity, reuses
the last successful mode and republishes existing virtual settings only if
offline; it does not create another display or modify physical display modes.
The main-queue operation has a three-second authority deadline; the network
queue stays responsive, and request cancellation/ownership loss stops recovery.
The signed package is recorded above; live recovery qualification remains open.

The operator intentionally powered off the dedicated development Mac to require
GitHub-hosted builds. Do not build on it or turn it on as a fallback. Compilation
and synthetic recovery/TLS gates must run on the hosted macOS runner. Protected
GitHub Developer ID/notarization configuration is now explicitly authorized;
credential provisioning and Host signing validation are complete. No
credential values, private operational logs or deployment identities belong here.

## Hosted builds qualified; Host signing qualified

The approved `github-builds` work is fast-forward merged into `main`, adding
GitHub-hosted clean-worktree builds. The 1.0.103 release is unchanged. See
`docs/development/build/github-builds.md` and the matching plan. Public jobs
have no signing/deployment secrets, private sources or access to internal
machines. No candidates have been installed and no existing builder is retired.

Hosted clean-bootstrap/build qualification results:

- macOS Host compile/portable tests and Ubuntu Client DEB/package gates passed
  in [run 34833324611](https://github.com/instinctual/plank/actions/runs/34833324611).
  Its overall result is failure because the other initial jobs needed fixes.
- macOS Client clean bootstrap/build passed in
  [run 34833858993](https://github.com/instinctual/plank/actions/runs/34833858993).
- Node 24 privacy checks passed in
  [run 34834417907](https://github.com/instinctual/plank/actions/runs/34834417907).
- Linux Host RPM and package gates passed in
  [run 34836078210](https://github.com/instinctual/plank/actions/runs/34836078210),
  explicitly checked against source `882cf322128584b30f48791f2b0ce3436b0a0f55`.
  The full CUDA architecture set and independent dependency-patch gates remain
  enabled; no hardware or installation tests were performed on the runner.

The Client DEB and Host RPM were transferred through the checked collector to
`artifacts/packages/candidates/1.0.103-github-builds/linux/`. SHA-256 values:

- Client: `831e04102110cb586ab2824630100f653479691e62a696c8f4852bedea5ccb23`
- Host: `895d53b9e83bc40759445bcd3ee6cbd807c53fe32a5c0f95b5cdf1dd5d2996db`

Their manifest retains each actual source commit, not the newer workflow-only
tip. Validation was across separate product runs, not one all-green aggregate
run at the final notes commit. Eight CI policy/context tests pass, including
the exact-source check and isolation from inherited runner environment values.

Selected-product manual dispatch permits retries without canceling other
platforms. Use `scripts/ci/dispatch.sh`: the expected-source gate now rejects
stale ref propagation before bootstrap. Container trust is exact-path only;
Rocky repositories are pinned before the first transaction; `python3-jinja2`
is declared and checked before lengthy dependency builds. Current Actions use
Node 24. These are CI/build fixes, not Host/Client runtime changes.

macOS distribution requires manual approval of the protected Developer ID and
notarization environment. Ordinary Mac CI
does not upload unsigned applications as release packages. Initial clean runs
use no dependency caches; add exact-input caches only after clean bootstrap
qualification. Hardware/session gates remain separate from hosted build tests.
Protected GitHub signing was authorized. The protected `macos-signing`
environment contains encrypted certificate exports, their passwords and
notarization credentials; values have not been retrieved or logged. A separate
manual-approval job prepares a disposable keychain and invokes the normal
package gates. Fourteen CI policy/helper tests pass. Credential validity and
the first signed/notarized Host runner package are now qualified. The Mac
Client signed runner job has not yet been exercised.
The first protected run, `35010539351`, received empty values for all six
environment secrets despite their presence in the environment metadata. It
stopped before keychain creation or certificate validation; no installer was
produced. Signing now runs as a direct environment-protected job in build.yml,
not through a reusable-workflow call. Missing secrets are checked before
dependency bootstrap. The direct-job signed rerun passed as recorded above.
The public and both private infrastructure CI branches are merged into their
respective `main` branches. Next: candidate hardware acceptance and, separately,
qualification of an exact-input dependency cache. Existing candidate packages keep their original
branch/source provenance; merging does not promote or relabel those artifacts.

## Current source

The final Host/Client repository is `instinctual/plank`. Build-path cleanup is
merged and all four mainline **1.0.103** packages passed build and payload review
from root **06bc71add24d7b7bddd19db1a9c2e914f0cb8383**. Later notes commits
do not change those package bytes. ENet cleanup was pushed and
merged at **5844885**; its **1.0.102** candidate provenance is retained below.
The audited Host/Client repository and its six required maintained dependencies
are PUBLIC following explicit approval. Release
[v1.0.103](https://github.com/instinctual/plank/releases/tag/v1.0.103) contains
the four verified packages, checksums and provenance manifest. Fresh live-session
testing was explicitly skipped for this release, not reported as passed. The
original development repository is preserved privately; do not import its
history, old gitlinks, deployment notes or credentials here. Private
infrastructure products remain independent and are not build dependencies.

Maintained companions now use the final `plank-client`, `plank-host-linux`,
`plank-kymux`, `plank-common-c`, `plank-build-deps`, `plank-libvirtualhid` and
`plank-enet` repository names. ENet is now removed from the current build graph;
its repository is not required for current builds and remains private. The seven
published repositories were fresh destinations populated only with audited refs.
External upstream references retain their original targets.
Author names, noreply attribution, licenses and useful development history are
preserved. Six unsolicited dependency-update branches from preparation were
excluded; inherited automatic update schedules are disabled on the affected
default branches. Pinned runtime dependencies did not change.

The 1.0.101 baseline rebuilt from the final repository names and rewritten source
identities. It made no streaming behavior change relative to 1.0.100. Optional
Client wake requests remain hidden/disabled without administrator opt-in.

## ENet cleanup

The Host-only common-C branch now contains three protocol headers and no
compiled implementation or recursive submodules. ENet, nanors and the unused
GameStream transport/library sources are removed. Input and PLANK wire headers
are unchanged; Limelight.h only loses the unused ENet RTT query declaration.
The Host's CMake source list follows the three retained headers. Client and
KyProto transport sources are unchanged. Historical builds are not supported.
Do not retain or restore current dependencies solely for old build compatibility.

Seven positive/negative tests pass, including standalone C/C++ header compilation.
The header-only CMake configure/build and four portable root CTest entries also
pass. Host executable source, Client gitlink and transport gitlink are unchanged.
The Host package preflight runs the tests and requires the header-only dependency.

Clean Host RPM build and all package gates pass from root
`d178c67240555d3425ba51df4d116fbb2f83b50b`, Host
`9329784ac41f50cbec0c9d76badfd22227ec5e5f`, Host headers
`775943b5ac5e5100a3c2b1b89d9e21151dea4f29`. Later notes commits do not
change those package bytes. The RPM is cataloged under
`artifacts/packages/candidates/1.0.102-enet-cleanup/linux/`, with version/branch
and SHA-256 provenance. It retains BUILD_TESTS=OFF and the full CUDA target set.
The exact clean source requires no ENet or nanors checkout, and the Host link
contains no ENet library. Existing Client packages require no code update for
this cleanup. No hardware/session testing or installation was performed.

Root, Host and Host-header commits were pushed and fast-forward merged in
dependency order. The completed enet-cleanup branches were removed locally and
remotely; their commits remain on the corresponding main/Host-header branches.
The current header branch replaces the Host-specific common-C branch, never the
Client's branch. Old remote repos/history were not deleted or rewritten.

## Audit and validation

### Build-path cleanup

Product builds now map C/C++ and Rust diagnostic paths to neutral build labels.
Cargo native compiler flags are isolated from qmake's Make variables. Client
FFmpeg bootstrap sanitizes only its generated configure-description string,
retaining the exact identity-GBR patch and actual private link/pkg-config paths.
macOS Client dependencies were rebuilt from pinned archives; OpenSSL runtime
defaults no longer point into an operator's home. No TLS verification downgrade,
new shipped trust/configuration file, media source or transport source change.

Normal package assembly strips debug sections before distribution signing.
All four package paths have a fail-closed home-path gate. Three exact public Qt
vendor paths (six occurrences) are narrowly allowed only in the pinned official
QtQuick/QtWidgets frameworks; there is no general home-path exemption.

Nine focused build-path cases and five portable CTest entries pass, including
privacy and bootstrap contracts. Mainline privacy CI passes. All four packages
passed clean builds and uninstalled package gates from the exact root above:

- `artifacts/packages/releases/1.0.103/linux/plank-host-1.0.103-1.el9.x86_64.rpm`
- `artifacts/packages/releases/1.0.103/linux/plank-client_1.0.103_amd64.deb`
- `artifacts/packages/releases/1.0.103/macos/plank-host_1.0.103_arm64.pkg`
- `artifacts/packages/releases/1.0.103/macos/plank-client_1.0.103_arm64.dmg`

The catalog retains SHA-256 checksums and source provenance; transfers were
hash-verified. Linux Host retains BUILD_TESTS=OFF and the full CUDA target set.
Both Mac products passed signing, notarization, stapling and Gatekeeper. The
actual Client on the read-only mounted final DMG passed a certificate-verified
TLS1.3 loopback using its bundled OpenSSL3.5.5. The mount and temporary signing/
validation job were removed after success. Initial fixture/compiler-flag failures
remain in private evidence; none were waived.

Extracted final payloads have zero supplied-secret or operator build-path
matches. Supplemental private-identity/token and symlink review found only two
non-text byte coincidences identical to the pinned official Qt input, not
deployment metadata. This is bounded scanning, not proof against unknown secrets
or every form of encoded metadata. Public Qt vendor literals above remain.
No installs or hardware/session tests occurred. Completed build-privacy branches
were removed locally/remotely after the fast-forward merge and push.

### Previous source/distribution audit

Every rewritten commit was checked for allowed URL/gitlink/pin changes, unchanged
executable source, retained messages and parent relationships. Historical
maintained gitlinks and branch hints resolve. All eight stored object sets have
zero supplied-password matches and zero maintainer personal-email matches.
Five previously reviewed Host test/demo/API scanner fixtures remain intentional.
See `docs/security/publication-review.md` for scope and limitations.

All four **1.0.101** packages passed clean build and uninstalled package gates
from `152dca081fea9585220ba0330b6492dff9137a6c`. Later handoff commits are
documentation only. Packages are under
`artifacts/packages/releases/1.0.101/{linux,macos}/`, with hashes and source
provenance in the version catalog's manifest. Transfers were SHA-256 verified.
The earlier 1.0.100 manifests retain their original provenance.

Linux Host retains `BUILD_TESTS=OFF` and the full supported CUDA target set.
Both macOS packages passed Developer ID signing, notarization, stapling and
Gatekeeper. All three builders used new worktrees and build outputs, reusing
the qualified bootstrap dependency caches. This was not another dependency
bootstrap. The temporary Mac signing job exited successfully and was unloaded.
Four portable root CTest entries pass, including 20 privacy guard cases.

## Current maintained inputs (1.0.103)

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

## Remaining gates

The older **1.0.100/1.0.101** assets are not cleared for publication: their binary
build-path metadata is not repaired retroactively by 1.0.103. Do not republish,
patch signed binaries or relabel their manifests.

Publication was authorized after the operator waived fresh hardware/session
testing for 1.0.103. That waiver does not change package-manifest functional
validation to passed, or waive future acceptance criteria. No packages were
installed on test or production machines. Credential rotation remains the
operator's separate responsibility, not a verified audit result.

The release tag points to the exact package source commit above; later notes
commits on main do not change it. All six release assets were downloaded without
authentication and SHA-256 verified. The seven repositories are anonymously
accessible. Private infrastructure, PLANK2, the historical backup and retired
ENet repository remain private. Older preparation hosting objects are not cleared
for publication. Private operational evidence stays outside Git as documented
in `docs/security/private-information.md`.
