# GitHub-hosted builds

`Hosted builds` compiles all four public products from clean Git worktrees.
It runs on pushes, pull requests and manual dispatch. No self-hosted machine,
deployment credential, private repository or signing secret is available to
these jobs. Actions are pinned to commit IDs and receive read-only permissions.

| Product | Environment | Result |
| --- | --- | --- |
| Linux Host | Pinned Rocky 9.7 container on Ubuntu runner | RPM and provenance catalog |
| Linux Client | Ubuntu 26.04, Qt 6.10.2 | DEB and provenance catalog |
| macOS Host | `xcode-27`, arm64, SDK/OS 27+ | Unsigned compile and portable tests |
| macOS Client | `xcode-27`, arm64, SDK/OS 27+ | Unsigned developer build |

Runner labels are not substitutes for version checks. Unsupported OS, Qt or
SDK versions stop the build. The Rocky repositories are fixed to the 9.7 vault;
CUDA compilation retains the existing complete architecture set. Runtime GPU
drivers are not installed. `scripts/ci/` creates the path contract, bootstraps
pinned dependencies, then invokes the normal build/package scripts. Existing
patch, payload, version and clean-source gates remain mandatory.

Linux package artifacts expire after seven days and do not publish releases.
Feature builds retain their branch-qualified visible and package versions.
These jobs do not install products or perform live display, audio, input,
network-loss or hardware-decoder qualification. Existing hardware gates and
local builders remain available until hosted builds are qualified.

## macOS distribution credentials

Ordinary CI intentionally has no Apple credentials. Its unsigned results are
not end-user installers. Signed, notarized PKG/DMG publication requires a
separate protected, manually approved release environment with Developer ID
Application and Installer certificates/private keys and notarization authority.
Do not copy a developer's entire keychain or reuse personal GitHub credentials.
Do not weaken existing signing/notarization gates to make an unsigned CI job
produce a release. Credential provisioning and release automation are a
separate gate; neither is configured by the ordinary build workflow.

## Initial qualification

First runs deliberately bootstrap from source without dependency caches. This
checks the public-clone path and exposes missing prerequisites. Add caches only
after clean runs pass, keyed by platform, toolchain and exact dependency/patch
inputs. Never cache signing material or application worktrees. Do not silently
switch to paid larger runners, older SDKs or reduced CUDA architectures when a
standard runner is insufficient; record the resource limitation first.
