# Linux physical display matching integration

**Draft: stacked after the Mac Client PR and pending recovery qualification.**

This PR packages the temporary physical-display helper and pins the paired
Client and Linux Host changes. When **Match client displays** is selected on a
physical NVIDIA/X11 Host, it can use real display modes matching the Mac's
current workspace or Retina backing pixels, and can put the Client's primary
screen on the Host primary connector. On disconnect, it restores the Host's
original MetaMode and primary setting. Existing physical and headless virtual
preset choices remain available.

This is the display feature separated from [root Mac Client PR #4](https://github.com/instinctual/plank/pull/4).
The Client controls are in [Client PR #4](https://github.com/instinctual/plank-client/pull/4)
and the Host source is in [Host PR #2](https://github.com/instinctual/plank-host-linux/pull/2).
The matched-mode feature bit is now `0x1000000`; `0x400000` remains reserved for
clipboard synchronization. Client and Host constants, protocol vectors and a
negative Client negotiation test agree.

[View only this PR's changes relative to the Mac root branch](https://github.com/cnoellert/plank/compare/codex/macos15-pr-review...codex/physical-display-stack).
The GitHub PR diff also contains its unmerged Mac base until that PR lands.

The exact split-branch Host package connected two 2560×1440 outputs and put
Flame on the intended primary. The operator confirmed normal work across the
two screens. The first normal disconnect then exposed a restoration bug:
GNOME selected a same-size temporary mode instead of the original physical
mode. The original Host layout was restored manually. A follow-up change now
removes the session's temporary modes before GNOME recovery; 28 no-display
helper tests pass. It still needs a fresh qualified Host package and a repeat
live disconnect test. Forced-failure recovery tests, including helper
termination and abrupt Client exit, also remain. Virtual startup should be
compared for headless Flame Hosts.

See the [display review](https://github.com/cnoellert/plank/blob/codex/physical-display-stack/docs/development/physical-display-integration-review.md)
for the full behavior, evidence and remaining gates. Keep this PR draft until
those gates pass; no release or installed-binary change is part of this review.
