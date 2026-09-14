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

## Diagnosing a hosted build

Manual dispatch accepts `product=all`, `linux-host`, `linux-client`,
`macos-host` or `macos-client`. A selected-product run has an independent
concurrency group, so retrying it does not cancel other platforms. Inspect the
failed job's first error, not the final nonzero-exit summary.

Use `bash scripts/ci/dispatch.sh linux-host` (or another product) after pushing.
It requires a clean, fully pushed branch and passes its exact expected SHA.
The policy job rejects a stale dispatch revision before costly bootstrap.
Always compare a run's `headSha` with the intended commit: an immediate dispatch
after pushing can otherwise select the prior revision during ref propagation.

- Rocky container ownership: checkout is runner-owned while the container runs
  as root. `context.py` trusts only the exact workspace. Never use a wildcard
  `safe.directory` exception.
- Rocky minor-release drift: a 9.7 image's ordinary mirror configuration can
  follow the next 9.x release. Pin the 9.7 vault **before the first package
  transaction**, including Git/Python installation. The container's existing
  `curl-minimal` is sufficient; do not conflict with it by installing `curl`.
- `glad: jinja2 not found`: `python3-jinja2` is an explicit Host bootstrap
  prerequisite. Do not depend on a previous builder's Python environment or
  let CMake install ad hoc dependencies late in the build.
- Download HTTP 502/503: use bounded retries of the pinned input, retaining its
  SHA-256 gate. Do not change versions or accept a partial download.
- Node.js 20 deprecation: the Node runtime embedded in a GitHub Action is
  separate from the OS `node` executable. Current pinned checkout/artifact
  actions use Node.js 24; installing a newer OS Node does not update an old
  Action.
