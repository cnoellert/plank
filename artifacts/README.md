# Build artifacts

Generated packages are ignored by Git. Published GitHub release assets are a
separate, explicit publication step; collecting a package does not publish it.

```
packages/
  releases/<version>/<linux|macos>/<original-package-filename>
  candidates/<version>-<branch>/<linux|macos>/<original-package-filename>
```

Each version directory has `manifest.json` and `SHA256SUMS`. Each package also
has a neighboring `.sha256` sidecar. Run `sha256sum -c SHA256SUMS` from the
version directory (on macOS, `shasum -a 256 -c SHA256SUMS`). Filenames retain
product/version/architecture and the feature branch when applicable.

`releases` means an unqualified **mainline build**, not proof of hardware
acceptance or a published release. Read each manifest's validation state.
Collection records package gates separately from functional validation; it
never upgrades a successful compile into an accepted product.

The shared collector is `scripts/collect-package.py`. All package builders
call it only after their package gates pass. `PLANK_ARTIFACT_ROOT` optionally
selects the package collection root; otherwise the retained canonical root's
`artifacts/packages` is used (or the source root when no canonical root is set).
Builder output arguments select scratch staging, not a second release catalog.

Use the collector again after transferring an artifact, specifying its exact
source commit, original branch, target OS and expected SHA256. Never collect an
old branch build as `main` or rename it to a newer version. Different payloads
or provenance under the same filename are rejected; increment the build version.

`qualification/` contains ignored validation reports/captures. Build trees,
signing intermediates, private keys and package extracts belong in builder
scratch/cache directories, not the package collection or tracked source.
