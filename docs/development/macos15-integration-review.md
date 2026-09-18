# macOS 15 Client integration review

This is the current review summary for the experimental Apple Silicon/macOS 15
Client. The chronological [development record](macos15-client.md) contains the
individual build and live-test observations. Workstation details, credentials,
raw logs and recordings remain outside Git.

## Scope

The Mac Client contribution adds a selectable macOS 15 build target while
preserving the default macOS 27 target. It presents one decoded desktop across
two Metal windows using each display's actual backing pixels. Native fullscreen
Spaces, camera-safe viewport sizing, secondary-window cleanup, captured drags
and pointer/pen focus have targeted fixes. The Client forwards allowlisted USB
Wacom raw HID after ordinary Input Monitoring permission. It retains the
upstream MacApplication Quit and captured Command-Q behavior.

The shared common-C change keeps absolute mouse positions in queue order across
button and key events. It now combines adjacent pending positions while holding
the queue lock, before they can fill the bounded queue and exclude releases.
This affects Linux Clients too and requires their regression qualification.

Linux physical-monitor mode matching, generated XRandR modes, primary-output
negotiation, the display helper and its RPM packaging are a separate
contribution: [Client #4](https://github.com/instinctual/plank-client/pull/4),
[root #7](https://github.com/instinctual/plank/pull/7) and
[Host #2](https://github.com/instinctual/plank-host-linux/pull/2).
This Mac review uses the maintained Linux Host gitlink and its existing
display policy. The separate display series uses `0x1000000` for matched modes;
`0x400000` belongs to clipboard synchronization.

## Changes and evidence

| Area | Behavior | Evidence and limit |
| --- | --- | --- |
| Build target | Explicit 15.0 minimum OS; default remains 27.0 | Dependency target, architecture, package and signature checks passed for local 15.0 candidates; 27.0 still needs final regression |
| Two displays | Separate Metal surfaces crop one decoded stream with shared input geometry | Native GPU readback, mixed-density geometry and three Space exit/reentry cycles passed; longer pacing and color acceptance remain open |
| Fullscreen | Native Spaces on both screens, early SDL policy, camera-safe viewport, secondary-window cleanup | Operator accepted dual fullscreen drag, right-click focus and windowed transition in earlier exact candidates |
| Wacom | Exclusive allowlisted USB HID forwarding, report/control protocol, passive cursor and pen focus | Flame pressure and focus were accepted on earlier candidates; current ad-hoc builds may need renewed Input Monitoring permission |
| Input queue | Adjacent absolute moves coalesce at enqueue; button/key events retain order | Existing drag fixture and new 150-position release fixture pass with the actual worker; the new fixture fails on the prior PR head |
| Upstream behavior | Current MacApplication Quit/Command-Q, Linux capture policy and Wayland window lifecycle retained | Native Quit tests and platform source guards pass; Linux hardware remains untested |

Client `851f4a4` with common-C `b2b2b29` passed a complete local Apple
Silicon/macOS 15 build: 97 Qt results, the actual native input-worker fixture,
seven fullscreen/platform checks and three Quit lifecycle guards. The queue
fixture passed 50 repeated runs and an AddressSanitizer build. The root
integration tests and final package checks need to be rerun after the PR split.
This source result has not replaced the accepted local Client installation.

The earlier accepted Client 1.0.126 passed 84 Qt results, native input ordering,
106 Mach-O checks, dependency closure and ad-hoc signature checks. Three native
AppKit cycles and 14 Metal readback cases passed. Live testing confirmed
cross-screen dragging, immediate right-click after pointer focus transfer and
single-output window cleanup. The earlier raw-tablet candidate delivered
pressure to Flame and transferred pen focus between fullscreen screens.
Those observations do not establish the final review head as live-accepted.

## Dependencies and review state

- [common-C PR #3](https://github.com/instinctual/plank-common-c/pull/3)
  was merged and supplies the queue-order and release-delivery fix. Its source
  commit is now reachable from the canonical submodule URL.
- [Client PR #3](https://github.com/instinctual/plank-client/pull/3) contains
  the Mac-specific implementation and the common-C pin. Its current review
  branch is being narrowed to the Mac scope.
- [root PR #4](https://github.com/instinctual/plank/pull/4) coordinates the
  Client pin, optional target build paths, focused tests and this evidence.
- [libvirtualhid PR #1](https://github.com/instinctual/plank-libvirtualhid/pull/1)
  was merged as a separate Pause-key correction for Linux; it is not a Mac
  Client dependency. The Linux Host dependency pin is in
  [Host PR #7](https://github.com/instinctual/plank-host-linux/pull/7).

Upstream Client `86682b5` and root `cb01cfe` were merged into the review
branches. The upstream Quit implementation replaced the earlier bridge; Mac
capture/fullscreen changes remain macOS-scoped, while Linux/Wayland behavior
retains its upstream policy. No upstream merge or release has occurred.

## Gates before merge

1. Replace the unbounded Wacom report I/O and shutdown barrier with bounded
   asynchronous completion and safe callback/device lifetime. Exercise stalled
   I/O during focus loss, reconnect and Quit.
2. Reproduce and resolve the intermittent live left-click loss. The queue test
   proves one release-loss bug, not that every observed click failure had the
   same cause.
3. Qualify the final Client on Ubuntu and macOS 27, and recheck macOS 15
   single/dual presentation, mixed density, fullscreen/windowed transitions,
   mouse drag/click and Wacom pressure/focus.
4. Test Wacom unplug/replug, disconnect/reconnect, transport interruption,
   sleep/wake, and interruption with a key or button held.
5. Rebuild from the final root and recursive submodule commits, then run the
   required hosted build/privacy jobs and product packaging checks.

Keep the Client and root PRs draft while these gates remain. The local source
build does not establish release or cross-platform hardware acceptance.
