# PLANK handoff

Read AGENTS.md and the platform build runbook before work.

## Current source

The final Host/Client repository is `instinctual/plank`. Build-path cleanup is
merged and all four mainline **1.0.103** packages passed build and payload review
from root **06bc71add24d7b7bddd19db1a9c2e914f0cb8383**. Later notes commits
do not change those package bytes. ENet cleanup was pushed and
merged at **5844885**; its **1.0.102** candidate provenance is retained below.
The repository remains PRIVATE pending explicit publication approval. The
original development repository is preserved privately; do not import its
history, old gitlinks, deployment notes or credentials here. Private
infrastructure products remain independent and are not build dependencies.

Maintained companions now use the final `plank-client`, `plank-host-linux`,
`plank-kymux`, `plank-common-c`, `plank-build-deps`, `plank-libvirtualhid` and
`plank-enet` repository names. ENet is now removed from the current build graph;
its repository is not required for current builds or publication. All are new private destinations populated only
with audited refs. External upstream references retain their original targets.
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

No installation, deployment, GitHub Release or public visibility change is
authorized by this preparation. Remaining gates: hardware/session acceptance,
explicit publication approval and independent
credential-rotation review. Older preparation hosting objects are not cleared
for publication. Private operational evidence stays outside Git as documented
in `docs/security/private-information.md`.
