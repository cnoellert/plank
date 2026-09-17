# Linux physical display matching controls for Mac Client

**Draft: stacked after [Mac Client PR #3](https://github.com/instinctual/plank-client/pull/3).**

This PR contains the Client half of optional physical-display matching. Under
the existing **Match client displays** bookmark choice, a separate **Retina
size** setting requests either the Mac's current workspace size or its current
backing pixels. Native/Scaled-Span keeps its existing meaning. A supported
physical-startup Linux Host can accept bounded real modes and the Mac primary
index; older or virtual-startup Hosts keep their existing qualified presets.

Matched modes use feature bit `0x1000000`; `0x400000` belongs to clipboard
synchronization. A Client test proves a clipboard-only flag cannot validate a
non-preset matched mode, while a matched-mode vector does not imply clipboard.
The Host and protocol changes are in the separate display series.

[View only this PR's changes relative to the Mac Client branch](https://github.com/cnoellert/plank-client/compare/codex/macos15-pr-review...codex/physical-display-stack).
The current GitHub PR diff also includes the unmerged Mac Client base until
that PR lands. No Linux physical mode change is part of the base Mac PR.

The local Apple Silicon/macOS 15 build passed 101 Qt results, including the
new negotiation test, plus the native input-worker and fullscreen/Quit guards.
The paired helper passed 20 fake-command tests. Earlier exact installed
packages completed normal two-screen matching and restoration; this stacked
source has not been installed. Ubuntu, macOS 27, headless virtual workflow and
Host failure-recovery qualification remain open. Keep this PR draft.

See the [physical display review](https://github.com/cnoellert/plank/blob/codex/physical-display-stack/docs/development/physical-display-integration-review.md)
for the full paired behavior and remaining gates.
