# Fresh dependency bootstrap validation

September 13, 2026; branch `repo-organization`.
All six package builds use root commit
`ec87bcf284936c90301c8d152847c966974b1df4`, version
`1.0.97-repo-organization`. Subsequent documentation/contract-test commits do
not change those binaries. No runtime transport, Host or Client code changed.

## What was clean

Each designated builder used an isolated `bootstrap-1.0.97` directory with
initially absent source, dependency, Rustup/Cargo and product build directories.
Existing normal builder manifests, prepared dependencies and installed product
services were not replaced. No package was installed, published or deployed.

The unpublished root branch was cloned from a verified full Git bundle, then
checked out as a detached worktree. Bundle SHA-256:
`6c75dbb4e9f7b021b9814c3c01feca7ee689e48485300ac6dce775a83eff3c28`.
Every required submodule was cloned recursively from its recorded network URL,
with global/system Git configuration and credential helpers disabled. No local
dependency mirror, old object directory or prepared library was used.
The root itself still needs private-repository access; this is not evidence
that an unauthenticated public root clone is available yet.

Rustup1.28.2 was downloaded and checksum-verified; Rust1.89.0 installed into new
isolated directories without changing shell profiles. Locked Cargo dependencies
were downloaded into empty caches, then product builds used offline Cargo.
The same pinned Host, Client, common-c, qmdnsengine and Kymux gitlinks as .96
remain in use; the artifacts' manifests record the root gitlinks.

This was **not a fresh OS installation** or a rebuild of every operating-system
library. Existing distro development packages, compilers and platform SDKs were
prerequisites. Qt6.10.2 on Ubuntu came from distro packages; macOS Qt6.10.2 was
downloaded anew from official archives, not compiled from Qt source. CUDA13
and Xcode/SDK27 are externally supplied toolchains.

## Findings and fixes

1. The Linux FFmpeg bootstrap incorrectly searched for the mandatory HEVC
   identity patch under its runtime output directory. The documented empty
   staging directory therefore could not work. Commit `709b226` resolves the
   patch from the checked-out Client source, keeping output separate.
2. The upstream pin auditor used relocated working paths as Git submodule
   section names. Commit `ec87bcf` restores the retained section names; the
   complete baseline audit now passes.

Three new contract tests cover empty runtime staging, rejection of a missing
tracked patch, and agreement between the auditor and `.gitmodules` sections.
These mock compilation deliberately; the real bootstrap is separate evidence.
Linux bootstrap documentation now pins/verifies rustup-init, avoids profile
edits, and lists Python/OpenSSL/patch/archive tooling explicitly. The Mac
runbook documents CMake as a prerequisite separate from Xcode.

## Results

| Component/check | Result |
| --- | --- |
| Rocky Host dependencies | Fresh Boost1.89.0 and FFmpeg/x264/x265 build-deps build; all 8 dependency patches pass |
| Rocky Host RPM | Clean compilation and package gates pass; `BUILD_TESTS=OFF` |
| CUDA coverage | Actual compile commands retain 75,80,86,87,89,90,100,103,110,120,121; no reduced candidate-only set |
| Ubuntu Client dependencies | Fresh FFmpeg9.0.1 plus required identity patch; independent pristine-source gate passes |
| Ubuntu Client DEB | Clean compile, Qt/binary/version/private-runtime/autostart package gates pass |
| Mac private Client dependencies | Fresh pkgconf2.5.1, OpenSSL3.5.5, Opus1.5.2, SDL3.4.2, FreeType2.14.1, SDL_ttf3.2.2, patched FFmpeg9.0.1 |
| Mac Host / Client compilation | Both build against fresh inputs without a supplied Apple signing identity |
| Mac transport unit tests | 19 pass, 2 intentionally ignored; 2 source-first FEC tests pass |
| Mac C ABI loopback | Intermittent peer-close timeout; see below — not an unconditional pass |
| Mac PKG / DMG | Signed, notarized, stapled, Gatekeeper accepted; installer lifecycle/package gates pass |
| Root Linux qualification | Fresh build using new dependency headers: 25 tests pass |
| Portable root contracts | 3 CTest entries pass, including 6 collector and 3 bootstrap-input tests |
| Transfers | All six package hashes match their originating builders |

The CMake cache's CUDA architecture default alone is not the effective list:
the Host CMake code computes the complete list used by nvcc. The list above
was verified in actual `compile_commands.json`, not inferred from the cache.

### Unresolved transport qualification

Follow-up: the runtime state-classification defect was subsequently reproduced,
fixed and qualified in [peer-close qualification](peer-close-qualification.md).
The original bootstrap results below are retained as recorded.

The first Mac C ABI loopback reported
`peer closure did not reach control receiver: 1` after video/control delivery.
An immediate rerun passed both fingerprint and explicit-approval cases.
Four subsequent two-case runs passed; the fifth failed at peer closure again.
The runtime sources and Cargo lockfile are unchanged from the .96 build.

A separately compiled harness then ran ten fingerprint cases each against
the retained .96 archive and the fresh .97 archive; both passed 10/10. This
does **not** invalidate the earlier failures or establish their cause.
No retry was added to the build runner, no timeout was relaxed, and no runtime
fix was layered into this organization/bootstrap task. Diagnose the intermittent
close/notification timing before claiming repeatable transport qualification.
Package gate success is distinct from that unresolved runtime test.

No new live capture, GPU decode, Wacom, media soak, login handoff, reboot,
fresh-install or upgrade acceptance was performed. The GPU-less Rocky builder
does not qualify NvFBC execution; its optional Capture SDK probe was unavailable.

## macOS signing and contributor workflow

Compilation was first exercised without Apple signing variables. The bare Host
uses an ad-hoc signature for uninstalled assembly checks, not a provisioned live
Host. Deployable Host identity/peer/TCC checks remain intact. Distribution was
then tested separately with the existing authorized Developer ID identities and
Keychain notarization profile, using a temporary same-user Aqua packaging job.
It exited0 and was removed. No keychain policy, privacy grant or installed app
was changed. No private keys or credentials are build-source inputs.

See [Building a fork from source](../build/from-source.md) for contributor
prerequisites and the distinction between compiling, live signed development,
and distributing notarized packages with a contributor's own Apple identity.

## Artifacts and evidence

All six packages are in
`artifacts/packages/candidates/1.0.97-repo-organization/{linux,macos}/`.
The version directory contains the exact source/size/hash manifest and
`SHA256SUMS`. These are candidates, not newly accepted production releases.

Logs and the exact bootstrap runner are retained outside Git at
`artifacts/qualification/full-bootstrap-1.0.97/`, including both failed Mac
loopbacks and the separate fresh/retained repeat comparisons. Builder-local
source/dependency/build evidence remains under the isolated `bootstrap-1.0.97`
directories beneath their work roots. Retain until review/push, then retire
these exact temporary trees; do not replace canonical dependency manifests
with these qualification paths.
