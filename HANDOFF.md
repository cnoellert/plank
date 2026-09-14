# PLANK handoff

Read AGENTS.md and the platform build runbook before work.

This is a separately sanitized Host/Client preparation repository. It remains
private pending explicit publication approval. The complete original development
repository is preserved privately. Private infrastructure products are extracted
to independent private repositories and their source/packaging histories are
excluded here. Mixed historical operational documents were removed; current
Host/Client-only documentation is curated. Upstream source and license notices
remain, as do useful Host/Client history and historical submodule targets.

Maintainer names are retained with GitHub noreply email. Original commit hashes
in older prose may refer to the preserved original history, not this copy.
Do not import private notes, passwords, audit data or old mirrors into Git.

Preparation version: 1.0.100. Client wake requests now require an explicit
administrator opt-in and are disabled/hidden by default. Linux and macOS share
the same policy and menu implementation. Ordinary streaming is unchanged.
Eighteen Qt policy test cases pass on the Linux Client builder.

All four 1.0.100 Host/Client packages pass clean build and uninstalled package
gates from source 79345726c2d6c549e34c12ee208978fd6f0b7c11. Linux Host retains
BUILD_TESTS=OFF and the full CUDA target list. Mac Host/Client distributions
passed signing, notarization, stapling and Gatekeeper. No installation or live
session test was performed. Package hashes and exact source provenance are in
artifacts/packages/releases/1.0.100/manifest.json. Infrastructure artifacts are
kept in their independent private repositories, never in this public catalog.

Four portable root CTest entries pass, including 19 privacy tests. GitHub privacy
CI passed for the package source. All retained historical root gitlinks resolve
in the maintained companions; no excluded private implementation blob remains
in the reachable public object set. The earlier 1.0.99 packages predate the split.
Hardware/session acceptance remains governed by
docs/development/acceptance-criteria.md.

Publication review must cover the final object set, hosting metadata/caches
and distribution assets. Original history still requires credential-rotation
review. Keep this repository private until the operator explicitly approves.
