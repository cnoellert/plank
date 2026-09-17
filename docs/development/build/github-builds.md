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
separate branch-restricted release environment with Developer ID
Application and Installer certificates/private keys and notarization authority.
Do not copy a developer's entire keychain or reuse personal GitHub credentials.
Do not weaken existing signing/notarization gates to make an unsigned CI job
produce a release. Credential provisioning and release automation are a
separate gate.

`build.yml` has a separate signing job selected with `signed=true` for one Mac
product. The job requires manual dispatch and directly names the protected
`macos-signing` environment. At the operator's request, this environment has no
required reviewers or wait timer: an explicitly dispatched signed build on an
allowed branch proceeds automatically. Keep custom deployment branch policies
enabled (currently `main`, `macos-display-recovery` and
`macos-media-recovery`, `macos-auth-recovery`, `reconnect-lifecycle` and
`macos-fullscreen`, `macos-command-q`, `macos-quit-lifecycle`); do not replace them with
an all-branches wildcard. Review source, workflow and dependency changes before
dispatching or adding a candidate branch. Public push/PR jobs have no signing
authority. This removes the approval gate itself, not through a bot/token that
approves each run; it does not enable signing on every push.

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
starts without a separate approval prompt on an allowed branch. Only its
signing step receives secrets. The helper
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

All four 1.0.105 release packages were subsequently rebuilt from mainline
`78e068edf9240de44e2aea5949dd94df713468b0` on hosted runners. The signed Client
job passed in [run 35018367944](https://github.com/instinctual/plank/actions/runs/35018367944),
including package launch/version, dependency closure, signing, notarization,
stapling, Gatekeeper and temporary-keychain cleanup. Both Mac release jobs
started without reviewer approval under the branch-restricted policy. This
qualifies the hosted packaging path, not live hardware behavior.

Clean bootstrap runs qualify the public-clone path and expose missing
prerequisites. Do not silently
switch to paid larger runners, older SDKs or reduced CUDA architectures when a
standard runner is insufficient; record the resource limitation first.

### Exact-input dependency caches

All four products support dependency caching (including unsigned and signed
Mac jobs). Cold-save/warm-restore qualification is recorded below; local policy
tests alone do not prove a hosted speedup.

| Product | Cached inputs |
| --- | --- |
| Linux Host | Prepared FFmpeg, its dependency-only build/source tree for independent patch verification, Boost sources, Rust toolchain and Cargo downloads |
| Ubuntu Client | Prepared FFmpeg, patched source and pristine archive for the source audit, Rust toolchain and Cargo downloads |
| macOS Host | Rust toolchain and Cargo downloads; capture/encoding/audio use Apple frameworks |
| macOS Client | Prepared libraries, patched sources, downloads and Qt (existing qualified cache) |

Rust caches contain only toolchains, Cargo tool binaries and downloaded registry/
Git sources. They exclude Cargo credentials/configuration and target objects.
Linux keys include exact installed package versions and compiler/build-tool
versions after prerequisite installation. The Host build-deps Git pin and its
tracked files cover all dependency source pins, flags and patches. Client keys
include the FFmpeg build script and all FFmpeg patches. Every new key also
includes bootstrap scripts, Rust pins/lockfile, architecture and absolute
source/dependency paths. Source updates that do not affect dependencies reuse
the cache; dependency changes produce a cold build. OS packages are still
installed by the package manager on each disposable runner, not restored from
a copied system root. CUDA architecture coverage is unchanged.

Mac Host's cache avoids Rust installation/downloads, not application or
transport compilation. Do not promise the same improvement as caching FFmpeg.
Cache selection is exact, with no fallback restore keys. A receipt must match
the selected key, required outputs must exist, and Linux FFmpeg patches are
checked independently before bootstrap. Existing package/source gates still
run. A mismatched/incomplete cache fails closed rather than silently using
unverified dependencies. Use a clean-bootstrap build to diagnose such a failure.

#### Four-product qualification

All listed runs passed full application build/tests after dependency bootstrap;
Linux jobs also passed package gates. Mac runs here were unsigned, not deployment
or signing qualification. Existing signed release gates remain unchanged.

| Product | Cold run | Warm run | Bootstrap cold / warm | Warm restore |
| --- | --- | --- | --- | --- |
| Linux Host | 35144970937, attempt 1 | 35144970937, attempt 2 (Host job only) | 4m29s / 23s | 12s |
| Ubuntu Client | 35146540028 | 35147537196 | 5m06s / 3s | 4s |
| macOS Host | 35144970937, attempt 1 | 35145530809 | 11s / 2s | 4s |
| macOS Client | 35144970937, attempt 1 | 35145993419 | 6m26s / 16s | 14s |

These are dependency-phase times, not total-job benchmarks. OS package
installation, source checkout/key selection, fresh application builds/tests
and packaging still take time. Linux Host dependency-source checkout was about
4m19s in both runs, outside the bootstrap times shown.

Host and initial Mac runs used `478edad0ee302c22c713df1cb67b4c4c185340a5`;
the Mac Client warm run used docs-only successor `265fba442d690a18f85e7d232dae36241947c789`.
Ubuntu used `64f368a4fdb58cc0de267bc8f59ec108a8f43be8`, which adds its original
FFmpeg archive to the cache and required-file checks. That Ubuntu-only content
correction invalidates new cache keys without changing Host cache logic or
paths; Mac Host also passed cold run 35146543166 at that source.

The first Ubuntu warm experiment (35146202369) correctly failed the pristine-
source audit: patched sources and libraries alone are insufficient. Always
retain the original checksum-verified FFmpeg archive, which packaging extracts
for its full-source comparison. Do not disable that audit to accept a cache hit.

#### Existing Mac Client qualification

After successful cold-build qualification, Mac Client jobs may reuse prepared
libraries, their sources (needed for licenses and patch verification), downloads,
and Qt. The exact key includes dependency bootstrap scripts and all Client FFmpeg
patches, source/dependency paths, architecture, runner image, OS, SDK, compiler,
and build-tool versions. Application-only changes do not invalidate it.
There are no fallback restore keys. A restored receipt must match the exact key;
the mandatory FFmpeg patch is independently verified before use. Normal build
and package dependency checks still run. Missing or mismatched inputs fail.

GitHub also scopes cache access by branch. A cache saved only on one feature
branch is not available to a sibling feature branch, even with an identical
input key. Build main to populate the default-branch cache for future branches;
otherwise the first build on a new branch is cold. Do not weaken key matching
or change dependency pins to work around a normal scope miss.

PLANK and its tests build fresh. Application build trees, packages, Cargo objects,
signing material and credentials are not cached. Public pull requests may read
dependency caches but cannot save them through this workflow. Trusted jobs save
only after a successful build; signed jobs first clean their temporary keychain.
All product jobs save only successful dependency state; cold-bootstrap bypass
applies to every product. The standalone fullscreen probe has no dependency cache.

To prove a fresh bootstrap, dispatch with `clean_bootstrap=true`, or use:

```bash
bash scripts/ci/dispatch.sh macos-client false --clean-bootstrap
```

This bypasses both cache restore and save. Omitting the option enables caching;
the first run for a new key is naturally cold. Cache availability and retention
are optimizations, not build requirements.

Qualification: cold unsigned run 35070457888 saved the cache after passing;
signed run 35071410245 restored the identical key after a Client-only change,
verified the required patch and completed all build/package gates. Bootstrap
took 6m32s cold versus 19s warm plus 29s restore. Do not compare total durations
as equivalent workloads: the second job additionally signed and notarized.

## Diagnosing a hosted build

Manual dispatch accepts `product=all`, `linux-host`, `linux-client`,
`macos-host` or `macos-client`. A selected-product run has an independent
concurrency group, so retrying it does not cancel other platforms. Inspect the
failed job's first error, not the final nonzero-exit summary.

Use `bash scripts/ci/dispatch.sh linux-host` (or another product) after pushing.
It requires a clean, fully pushed branch and passes its exact expected SHA.
The policy job rejects a stale dispatch revision before costly bootstrap.

Diagnostic-only `macos-fullscreen-probe` additionally requires `signed=true`.
It builds the standalone AppKit probe, not either product, and uses the same
protected environment/cleanup. It skips product dependency bootstrap entirely
and uploads a separate `diagnostics/` catalog with source/hash evidence. See
`probes/macos/fullscreen-window.md`; no ordinary push/PR signs this diagnostic.
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
