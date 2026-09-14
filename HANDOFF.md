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

The earlier 1.0.100 packages passed all four build/package gates, including Mac
signing and notarization, but predate the final source identities. Their manifests
must not be relabeled. The 1.0.101 builds are pending; do not treat source-audit
success as package or hardware acceptance. Use the version/platform catalog under
`artifacts/packages/` for exact package hashes and recursive source provenance.

No installation, deployment, GitHub Release or public visibility change is
authorized by this preparation. Remaining gates: final-source package builds,
distribution metadata review, hardware/session acceptance and independent
credential-rotation review. Older preparation hosting objects are not cleared
for publication. Private operational evidence stays outside Git as documented
in `docs/security/private-information.md`.
