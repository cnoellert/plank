# macos: add mixed-density multi-display presentation and raw Wacom input

**Draft: cross-platform and recovery qualification remain open.**

## Summary

- Present one decoded desktop on two Cocoa/Metal surfaces with consistent
  logical/backing-pixel input geometry.
- Preserve native Spaces; fix secondary Space cleanup and single-host-output
  presentation; retain the current upstream Retina, captured Command-Q and Quit lifecycle fixes.
- Preserve captured drags and input ordering; follow pointer/pen focus between
  owned fullscreen surfaces without an activation click.
- Forward allowlisted USB Wacom raw HID with normal Input Monitoring permission,
  explicit exclusive ownership, report/control forwarding and a tablet cursor.
- Preserve bookmark layout/scaling controls and add a separate Retina size
  choice; negotiate bounded Linux display modes and primary output.
- Keep macOS 15 target support explicit. The default remains macOS 27.

## Dependencies and compatibility

Depends on [common-C #3](https://github.com/instinctual/plank-common-c/pull/3)
(`0c82257`) and the root's build,
protocol fixtures and packaging. Display matching requires the optional Host
features; older Hosts retain preset-only matching. The default newer-macOS
build and Linux Client still require qualification.

Upstream `86682b5` is merged in review Client `d9ad2b1`. Its explicit
MacApplication exit ownership replaces the earlier Quit bridge; captured
Command-Q handling and both new native suites are preserved. The review branch scopes Cocoa automatic capture,
Space cleanup and one-host-output presentation policy to macOS. Wayland retains
its previous capture and window lifecycle policy. Shared motion ordering is an
intentional cross-platform correction and has its own test gate.

## Evidence

Accepted Client 1.0.126: 84 Qt tests, native input-worker ordering, five fullscreen
checks, 106 Mach-O checks and package/signature checks. Three AppKit lifecycle
cycles and 14 GPU readback cases passed. Operator acceptance covers fullscreen
mouse dragging/focus, earlier exact-build tablet pressure/focus and current
fullscreen/windowed cleanup. The integration candidate preserves current upstream Quit lifecycle and
platform guards; its build record is linked from the root review.


Publication-time upstream refresh: fresh candidate 1.0.128 from root `9b495ee`
/ Client `d9ad2b1` passes 101 Qt results, native input ordering, seven fullscreen
and three Quit lifecycle guards, seven portable suites, 38 CI tests, 106 Mach-O
checks, dependency closure and ad-hoc signatures. It has not been deployed.
GitHub hosted-build/privacy runs report `action_required` with no jobs executed;
maintainer action and hosted CI remain pending.

## Known limitations / merge gates

- Recovery after transport loss, sleep/wake and Wacom hotplug remains open.
- Intermittent remote left-click loss has no established permanent fix.
- Ad-hoc rebuilds can invalidate Input Monitoring authorization.
- No Ubuntu client or supported newer-Mac hardware acceptance is claimed.
- Mac Host matching, Retina-detail full-session acceptance, sustained pacing and
  visual/color checks remain separate gates.
- Wacom support is allowlisted USB raw HID, not generic USB or Bluetooth.

Review Metal resource lifetimes, raw-HID ownership/control bounds and shared
input ordering. Authentication, TLS and exact video-profile negotiation remain.
Attach only sanitized bookmark UI screenshots; development captures are private.

The common-C dependency must be available from its canonical upstream URL before
this gitlink can be treated as a reproducible build input. Keep this PR draft
until the dependency and qualification gates pass.

## Contribution set

Tracked by [integration PR #4](https://github.com/instinctual/plank/pull/4); [change inventory and verification record](https://github.com/cnoellert/plank/blob/codex/macos15-pr-review/docs/development/macos15-integration-review.md).
