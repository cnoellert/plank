# PLANK handoff

Read AGENTS.md and the platform build runbook before work.

## Current source

The final Host/Client repository is `instinctual/plank`, on `main`, version
**1.0.101**. It remains PRIVATE pending explicit publication approval. The
original development repository is preserved privately; do not import its
history, old gitlinks, deployment notes or credentials here. Private
infrastructure products remain independent and are not build dependencies.

Maintained companions now use the final `plank-client`, `plank-host-linux`,
`plank-kymux`, `plank-common-c`, `plank-build-deps`, `plank-libvirtualhid` and
`plank-enet` repository names. All are new private destinations populated only
with audited refs. External upstream references retain their original targets.
Author names, noreply attribution, licenses and useful development history are
preserved. Six unsolicited dependency-update branches from preparation were
excluded; inherited automatic update schedules are disabled on the affected
default branches. Pinned runtime dependencies did not change.

This version rebuilds from the final repository names and rewritten source
identities. It makes no streaming behavior change relative to 1.0.100. Optional
Client wake requests remain hidden/disabled without administrator opt-in.

## Audit and validation

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

| Maintained input | Package source commit |
| --- | --- |
| Linux Host | `4a7fd6aabc1046cc0ccc864fd90f1cf1d37fd44b` |
| Shared Client | `c032da3ae0d7e816a7a6f9bb9a51dd489d4d369c` |
| Transport | `912ece5c64787997f978673ca60d313898a3548c` |
| Host common-C | `1337910ce816b15d03f4878a260df7b6ca1f45ee` |
| Client common-C | `b9650552f98d97f6e30c9f007115c6246f0809e5` |
| Client mDNS engine | `b7a5a9f225d5e14b39f9fd1f905c4f505cf2ee99` |
| Host build dependencies | `caf0495d5e6baff94f349853d4a59e3779a451a0` |
| Host virtual HID | `93d57db99a5bf4b1a9fbbc7ad1371671725b7e97` |
| Host ENet | `0492da7f03bdf97739b486afee087b8abf34845d` |

The private distribution review found no supplied-password matches in the
extracted payloads. However, binaries in all four products retain private build
paths. **Do not publish these assets.** Remove build-path metadata through
reproducible compiler/dependency build settings, rebuild with a new version,
then repeat the payload review. Do not patch signed binaries or relabel them.

No installation, deployment, GitHub Release or public visibility change is
authorized by this preparation. Remaining gates: distribution metadata cleanup
and review, hardware/session acceptance and independent
credential-rotation review. Older preparation hosting objects are not cleared
for publication. Private operational evidence stays outside Git as documented
in `docs/security/private-information.md`.
