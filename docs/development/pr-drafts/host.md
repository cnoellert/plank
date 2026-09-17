# display: negotiate bounded physical modes and preserve primary output identity

**Draft: deploy only with the matching root display helper/package.**

## Summary

Negotiate optional matched-mode (`0x1000000`) and primary-output (`0x800000`)
capabilities while retaining schema 13. Validate canonical even dimensions,
one/two horizontal outputs and the 8192-pixel canvas bound. Keep headless startup
restricted to qualified EDID presets.

The supervisor invokes the root-owned packaged helper as the attested desktop
owner, retains the original MetaMode/primary property, and restores/cleans a
lease before replacement. Actual primary and geometry are verified. Existing
output identity is preserved for applications that enumerate physical connectors
independently from the XRandR primary flag.

## Dependencies and deployment

- Host contribution: `ec049615`; target: `main`.
- Depends on [libvirtualhid #1](https://github.com/instinctual/plank-libvirtualhid/pull/1)
  (`b0cc3c8`) and the root's `plank-display-match`
  helper, RPM ownership/dependencies and tests.
- Supervisor/worker request changes from SC-DISPLAY-3 to SC-DISPLAY-4; upgrade
  these components together. This is not an external schema-version change.

## Security review

PAM ownership checks remain. Helper arguments are validated dimensions and
indices, never Client-provided shell commands/modelines. The helper runs with
NoNewPrivileges, protected system files, hidden home directories and UNIX-only
network families. The attested user's runtime directory is bound read-only for
Xauthority/D-Bus access; socket operations still have their normal semantics.
Review that narrowed privilege boundary and timeout/restoration behavior.

## Verification and remaining gates

Focused Host topology/session tests and Linux keyboard tests passed in Rocky
9.7. Twenty helper transaction/geometry tests passed. Package and installed-file
checks, actual single/desktop-size/Retina-size helper trials, primary identity,
exact restore and temporary-mode cleanup passed on the authorized NVIDIA Host.
The operator confirmed correct display appearance and intended Flame placement.

An upstream Ubuntu Client, headless preset workflows, forced helper termination,
restoration failure and abrupt session recovery still need qualification. Do
not describe successful normal restoration as proof of every failure path.

The libvirtualhid dependency must be available from its canonical upstream URL
before the gitlink is used as a reproducible build input.

## Contribution set

Paired with the separate [physical display integration review](https://github.com/cnoellert/plank/blob/codex/physical-display-stack/docs/development/physical-display-integration-review.md). The root Mac Client PR no longer contains this Host feature.
