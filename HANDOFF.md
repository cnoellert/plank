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

Final source audit: remaining operator examples and Host test fixtures are
sanitized throughout history. Current Client runtime is byte-identical, and
current Host source changes are test-only. All historical root gitlinks resolve
after remapping. The final rewrite preserves commit messages, author identities,
commit counts and topology. Eleven focused authentication cases and four
portable repository checks pass. See docs/security/publication-review.md for
scope, intentional scanner findings and remaining publication boundaries.

Audited source before the dependency-attribution notes commit:
3b9bf487569905d973237f47ca3cdf264d6f6360.
Client: 8899119809369ec62fb03e6f15b313047febdedb.
Linux Host: b6e688ff594d6e26372382633d3621565b08bc9f.
Transport is unchanged: 912ece5c64787997f978673ca60d313898a3548c.
No new package was built or installed during this final source audit.

The operator approved private noreply replacements for common-C, build-deps,
libvirtualhid and ENet. They are plank-common-c-public, plank-build-deps-public,
plank-libvirtualhid-public and plank-enet-public in the project organization;
the names describe publication preparation, not current visibility. Existing
public repositories remain untouched. Dependencies and all historical
maintained gitlinks now follow those copies. External upstream links remain
unchanged. Do not import old dependency hashes or local URL overrides from
previous preparation checkouts or builders.

All seven rewritten histories preserve names, dates, messages, commit counts,
branch relationships and executable source. Only identity metadata, dependency
URLs/gitlinks and baseline pins change. The transport is unchanged. Four
portable checks pass, including 20 privacy cases. No package was rebuilt or
installed; the existing 1.0.100 manifests must retain their original provenance.
Use final-source rebuilds for a public binary release. Hosting-object cleanup,
distribution metadata and credential rotation remain separate publication gates.
