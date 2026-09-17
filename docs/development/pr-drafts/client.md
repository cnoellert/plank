# macos: add mixed-density multi-display presentation and raw Wacom input

**Draft: cross-platform and recovery qualification remain open.**

## Summary

- Present one decoded desktop on two Cocoa/Metal surfaces with consistent
  logical/backing-pixel input geometry.
- Preserve native Spaces; fix secondary Space cleanup and single-host-output
  presentation; retain the current upstream Retina and native Quit fixes.
- Preserve captured drags and input ordering; follow pointer/pen focus between
  owned fullscreen surfaces without an activation click.
- Forward allowlisted USB Wacom raw HID with normal Input Monitoring permission,
  explicit exclusive ownership, report/control forwarding and a tablet cursor.
- Preserve bookmark layout/scaling controls and add a separate Retina size
  choice; negotiate bounded Linux display modes and primary output.
- Keep macOS 15 target support explicit. The default remains macOS 27.

## Dependencies and compatibility

Depends on the common-C ordered-input PR (`0c82257`) and the root's build,
protocol fixtures and packaging. Display matching requires the optional Host
features; older Hosts retain preset-only matching. The default newer-macOS
build and Linux Client still require qualification.

Upstream `b9e4be6` is merged. The review branch scopes Cocoa automatic capture,
Space cleanup and one-host-output presentation policy to macOS. Wayland retains
its previous capture and window lifecycle policy. Shared motion ordering is an
intentional cross-platform correction and has its own test gate.

## Evidence

Accepted Client 1.0.126: 84 Qt tests, native input-worker ordering, five fullscreen
checks, 106 Mach-O checks and package/signature checks. Three AppKit lifecycle
cycles and 14 GPU readback cases passed. Operator acceptance covers fullscreen
mouse dragging/focus, earlier exact-build tablet pressure/focus and current
fullscreen/windowed cleanup. The integration candidate adds upstream Quit and
platform guards; its build record is linked from the root review.

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
