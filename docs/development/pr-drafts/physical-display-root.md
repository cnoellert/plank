# Linux physical display matching integration

**Draft: based on merged Mac Client work and pending recovery qualification.**

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
The root branch now merges accepted main; its incremental diff is the display
feature.

The exact split-branch Host package connected two 2560×1440 outputs and put
Flame on the intended primary. The operator confirmed normal work across the
two screens. The first normal disconnect then exposed a restoration bug:
GNOME selected a same-size temporary mode instead of the original physical
mode. The original Host layout was restored manually. A follow-up change now
removes the session's temporary modes before GNOME recovery; 28 no-display
helper tests pass. The corrected Host RPM passed Rocky 9.7 hosted run
`35285840457` and was installed on the Rocky 9.5 hardware-test Host. Two
normal disconnects logged exact restoration; the second was independently
checked against NVIDIA, XRandR and GNOME. The original single-output mode and
primary returned, no temporary mode or lease remained, and the Host stayed
active. Forced-failure recovery tests, including helper termination and abrupt
Client exit, remain. A headless virtual-startup comparison placed Flame on the
Eizo and restored the original Host layout after disconnect. The physical-mode
helper is not needed for that tested workflow; automatic matching still rejects
the MacBook's current 2056×1286 size under the virtual EDID allowlist.
An intermittent remote left-click failure recurred during the next test. The
Host input service was reset to clear a stale XInput button state; live input
after reconnect and the cause of that failure are still under investigation.

This stack now includes the Mac review's Wacom timeout recovery and one-package
macOS 15+ build policy. The earlier integrated head passed all five hosted jobs;
the current head needs a new SDK 27 build and exact-package live checks.

See the [display review](https://github.com/cnoellert/plank/blob/codex/physical-display-stack/docs/development/physical-display-integration-review.md)
for the full behavior, evidence and remaining gates. Keep this PR draft until
those gates pass; no release is part of this review.
