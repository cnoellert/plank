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
separate gate.

`build.yml` has a separate signing job selected with `signed=true` for one Mac
product. The job requires manual dispatch and directly names the protected
`macos-signing` environment. Require human review, disallow bypass,
and allow only approved release/candidate branches in that environment. Review
the exact source SHA, workflows and dependency changes before approving; do not
auto-approve through a token. Public push/PR jobs have no signing authority.

Environment secrets (never repository files):

- `PLANK_DEVELOPER_ID_APPLICATION_P12`, `PLANK_DEVELOPER_ID_INSTALLER_P12`:
  base64-encoded encrypted exports including the matching private keys.
- `PLANK_DEVELOPER_ID_APPLICATION_PASSWORD`,
  `PLANK_DEVELOPER_ID_INSTALLER_PASSWORD`: the respective export passwords.
- `PLANK_APPLE_ID`, `PLANK_APPLE_APP_PASSWORD`: notarization account and its
  Apple app-specific password, not its ordinary login password.

Set environment variable `PLANK_MACOS_TEAM_ID` to the Developer Team ID.
Certificate type, private-key presence and team are validated on the runner.
Keep Developer ID distinct from Apple Development and Mac App Store identities.

After a clean committed/pushed source is qualified, request signing with
`bash scripts/ci/dispatch.sh macos-host true` (or `macos-client true`). The job
waits for manual approval. Only its signing step receives secrets. The helper
checks presence before bootstrap and removes them from child environments. It
bootstraps dependencies without credentials, then imports into a temporary 0700 runner
directory/keychain with narrowly allowed Apple signing tools, and stores
notarization credentials in that keychain. It restores the prior search list
and deletes temporary material on completion/failure; an always-run cleanup step
also handles interruption. Only the gated package catalog is uploaded, never
signing scratch, keys or keychains. Artifacts expire in seven days; this does
not publish a release or install on any machine.

This isolated-runner automation uses GitHub's per-step secret environment and
Apple CLI password arguments during import/profile setup. They are not echoed;
tool output/exception arguments are suppressed at that boundary. They may be
visible to another process under the same runner account, which is why this is
restricted to disposable GitHub-hosted machines running approved source, never
an operator's Mac, shared runner or public PR. Local interactive keychain rules
remain unchanged. See [GitHub's signing guidance](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications).

## Initial qualification

The protected direct Host job passed signing, notarization, stapling, final
package permission checks and temporary-keychain cleanup in
[run 35011167754](https://github.com/instinctual/plank/actions/runs/35011167754)
at source `ca36e48123d58cc84104f6fab5df59c35d14f05e`. This is not live
installation/recovery acceptance or qualification of the signed Client job.
The initial reusable-workflow version received empty secret values despite
environment metadata being present; the direct environment-protected job is
the qualified path. Do not restore that indirection or broaden secret access.

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
