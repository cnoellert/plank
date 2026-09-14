# Repository organization validation

September 13, 2026. Branch `repo-organization`; package source
`b12dc9ddba8bd264aa786e0ccb573f5027b77f73`, version `1.0.96-repo-organization`.
Later documentation-only commits record these results, not different binaries.

## Scope and invariants

- Product sources moved under `apps/`, with one shared Client tree.
- Linux Host and Client gitlinks, histories and licenses remain unchanged.
- All moved installation payloads (other than documentation) are byte-identical
  to the pre-move versions. Runtime service/configuration paths are unchanged.
- macOS production source files are byte-identical; the transport Rust change
  only updates two ignored-test runner descriptions.
- Scripts, packaging inputs and documentation references follow the new layout.
  No legacy-path symlink layer, new OS abstraction or Windows stub was added.

## Validation

| Check | Result |
| --- | --- |
| Shell/Python parsing | 143 files pass |
| Relative Markdown links and layout | Pass on Linux and macOS |
| Artifact collector | 6 tests pass on Linux and macOS |
| Portable root CMake mode | 2 tests pass, no Linux dependencies required |
| Linux qualification build | 24 tests pass |
| Host dependency integrity | All 8 required patches pass independent checks |
| Mock macOS installer lifecycle | 23 checks pass, no product services changed |
| Linux Host RPM | Clean build and all binary/package gates pass |
| Linux Client DEB | Clean build and exact private-dependency/runtime gates pass |
| macOS Host and Client | Clean builds pass; PKG/DMG signed, notarized and stapled |
| Cross-builder transfer | All six package SHA-256 values rechecked |

Fresh source/build directories were used on the designated builders, with
existing pinned dependency libraries and offline Cargo caches. No release was
built on a workstation or end-user client. No package was installed.

The Host move exposed stale generated dependency Git pointers/pkg-config
prefixes. Only path metadata was corrected, followed by the independent patch
gate; libraries and patched source were retained. The initial root CMake check
without the builder manifest failed to find FFNVCODEC. Loading the corrected
manifest resolved it. The GPU-less builder has no Capture SDK header, so NvFBC
hardware qualification remains a hardware-target task.

Mac SSH distribution signing hit the documented `errSecInternalComponent`.
The existing same-user Aqua signing route passed without unlocking by script,
changing identities, modifying keychain/TCC policy or installing an app. Its
one-shot launchd job exited successfully and was removed. Compiler/package
warnings from unchanged dependencies remain warnings, not new support claims.

## Package catalog

All packages are under
`artifacts/packages/candidates/1.0.96-repo-organization/`:

| Platform | File | SHA-256 |
| --- | --- | --- |
| Linux | `plank-host-1.0.96-0.repo_organization.1.el9.x86_64.rpm` | `5a79614e3c7561d49f30aebe28c62f8fffc125f702979fb5b3c593455da222a5` |
| Linux | `plank-client_1.0.96-repo-organization_amd64.deb` | `2f47d54ec398debfa40fd9b332d96be82c8467e4d50a8062c2bdd6ccd962983c` |
| macOS | `plank-host_1.0.96-repo-organization_arm64.pkg` | `4c39d2717237cba3225584c5883fdb8b1a3680da032497b6911acce7176fbbd7` |
| macOS | `plank-client_1.0.96-repo-organization_arm64.dmg` | `3c75ea07b9db6b14af10aeb5b1ab2254daea960ce36abf0f4399aded7e776f14` |

The version directory contains `manifest.json`, `SHA256SUMS` and individual
sidecars. Build logs and recursive Host pins are retained outside Git in
`artifacts/qualification/repository-organization/`. Current root and nested
commits, bundle hashes and the full recursive-pin record hash are in HANDOFF.

These are build/package results, not fresh interactive acceptance of video,
audio, input, display changes, reboot or upgrades. No hardware gates were
waived. Public-history sanitization, publication and merge are separate steps.
