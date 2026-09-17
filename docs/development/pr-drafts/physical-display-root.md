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

Earlier exact packages connected two 2560×1440 outputs, preserved the intended
primary for Flame, and restored the original one-screen Host layout after a
normal disconnect. Twenty helper tests and a local Client build with 102 Qt
results pass. This split branch still needs a fresh qualified Host package and
forced-failure recovery tests, including helper termination, failed
restoration and abrupt
Client exit. Virtual startup should be compared for headless Flame Hosts.

See the [display review](https://github.com/cnoellert/plank/blob/codex/physical-display-stack/docs/development/physical-display-integration-review.md)
for the full behavior, evidence and remaining gates. Keep this PR draft until
those gates pass; no release or installed-binary change is part of this review.
