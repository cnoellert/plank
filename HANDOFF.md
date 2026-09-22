# PLANK handoff

## Current task: virtual-primary PR repairs

The operator authorized fixing two Client findings in the coordinated Client
#6 / Linux Host #9 / root #10 series. Work uses branch `virtual-primary-fixes`
in `build/worktrees/virtual-primary-fixes` and its Client worktree. The fixes
are pushed to the author's editable `codex/virtual-primary-order` PR branches.
Main remains unchanged. Do not merge, install or publish without approval.

Root PR base: `db868b4a8930397628c3fb10949c61c1c9ad6a2d`.
Client repair: `6580f794141b2073eae1110136d8665605eb3803`.
Root integration: `c38d5ea6952d8422f1334d5a671846a476b5c916`.
The root branch is refreshed with main's completed build notes at
`652718632be33b355df5e1fce989018c9df49f3a`; only HANDOFF conflicted.
Candidate version is 1.0.152, with the actual CI branch qualifier retained.

- Removed the Host-sized presentation-canvas override and its unused helper.
  Primary connector ordering retains the established aspect-preserving
  renderer and corresponding mouse/pen/cursor geometry.
- Bound the optional primary hint to the requested output count and an
  unambiguous horizontal layout. Manual bookmarks omit an unmappable hint
  instead of sending index 2 or rejecting an otherwise valid connection.
- Unit coverage includes 0–4 displays, every primary position, reversed
  enumeration, negative origins, ambiguous layouts, differing Host/Client
  aspect ratios and Retina logical input/cursor round trips.
- Linux Host code is unchanged from the reviewed Host #9. No transport,
  capture/encoding, physical-monitor policy or Wacom-focus change was added.

Local CI policy checks pass (60), version-contract and diff checks pass.
Exact-source hosted Client checks are pending. No new hardware acceptance or
signed installer is claimed. See `docs/development/virtual-primary-order-review.md`,
`protocol/output-topology.md` and `docs/releases/1.0.152.md`.

## Other open PRs

All four cnoellert PRs were rechecked; no new PR or unreviewed revision appeared.
Client #7 at `af659dbca03304897dc693dc323a419134de6147` remains a separate
Wacom-focus proposal. No blocking code defect was found; native fullscreen
Spaces, focus release into local dialogs, reconnect and pressure still need
live macOS 27 qualification. It is not included in this candidate.
Linux Host #9 remains at `ebf63ac9347e461a1eaff5adc83a77724187002a`.
Client #6 and root #10 contain the authorized repairs and remain drafts.

The latest pre-repair root rebase passed all four hosted jobs in run
35675419841. Earlier paced-baseline and skipped-frame failures remain
historical evidence, not erased by later passes. Main now tests only the
selected shipping transport policy, as explicitly authorized by the operator.
Do not relax its three loss matrices or other shipping gates.

## Mainline packages and provenance

All four 1.0.151 packages passed and are collected/checksum-verified under
`artifacts/packages/releases/1.0.151/`. Nothing was installed or published.
The latest published release remains 1.0.143.

- Ubuntu Client: run 35672399443.
- Signed Mac Host: run 35672399113.
- Signed Mac Client: run 35672399343.
- Linux Host: run 35674515126.

The first three use root `c14704801ffa8c5166961c03db8f4bf6c57b08d5`;
the RPM uses `aa885d0f5b86f4e9101cff97d22c2caa9aeab66c`, which only changes
Host gate selection and its tests/docs. Exact hashes and submodule provenance
remain in each catalog manifest and main's HANDOFF at `6527186`.
Never replace or relabel those packages with this candidate.

The candidate's maintained inputs are Client `6580f794`, Linux Host
`ebf63ac9`, Kymux `158719b6`; nested dependency pins are unchanged.
Use GitHub-hosted builders, verified dependency caches and the release runbook.
Preserve the unrelated RK3576 plan, dirty HANDOFF and diagnostics in the
primary checkout. Private deployment notes stay outside Git.

## Remaining acceptance

Validate connector-primary behavior and image/input mapping with mixed
resolutions, Native and Scaled-Span, one/two local monitors and a manual
two-output bookmark on a three-monitor client. Confirm reconnect, fullscreen
transitions, mouse, pen and cursor behavior. macOS 27 live acceptance remains
outstanding; earlier macOS 15 trials are not exact-source qualification.

Mainline takeover/handoff acceptance, Wallpaper/Screen Saver hover lag and the
Linux physical-display provenance issue remain documented at main `6527186`.
This repair does not expand into those tasks or the separate Wacom-focus PR.
