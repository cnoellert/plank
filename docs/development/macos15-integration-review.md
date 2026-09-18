# macOS 15 Client integration review

This is the current review summary for the experimental Apple Silicon/macOS 15
Client. The chronological [development record](macos15-client.md) contains the
individual build and live-test observations. Workstation details, credentials,
raw logs and recordings remain outside Git.

## Scope

The Mac Client contribution uses one SDK27-built Apple Silicon package with a
macOS15 deployment minimum, including when running on macOS27. Newer APIs use
runtime availability checks; the build rejects unguarded newer API calls rather
than removing modern features. The Host remains27-only. It presents one decoded desktop across
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
| Build target | One SDK27-built Client, minimum OS15.0; Host stays27 | Portable target/cache guards pass; identical-package live validation on15 and27 remains open |
| Two displays | Separate Metal surfaces crop one decoded stream with shared input geometry | Native GPU readback, mixed-density geometry and three Space exit/reentry cycles passed; longer pacing and color acceptance remain open |
| Fullscreen | Native Spaces on both screens, early SDL policy, camera-safe viewport, secondary-window cleanup | Operator accepted dual fullscreen drag, right-click focus and windowed transition in earlier exact candidates |
| Wacom | Exclusive allowlisted USB HID forwarding, timed report I/O, remembered focus/reconnect intent after bounded release waits | Delayed-release, superseding-request and terminal-Quit tests pass; pressure/focus acceptance belongs to earlier candidates, not this repair |
| Input queue | Adjacent absolute moves coalesce at enqueue; button/key events retain order | Existing drag fixture and new 150-position release fixture pass with the actual worker; the new fixture fails on the prior PR head |
| Upstream behavior | Current MacApplication Quit/Command-Q, Linux capture policy and Wayland window lifecycle retained | Native Quit tests and platform source guards pass; Linux hardware remains untested |

Client `397678e` with common-C `b2b2b29` passed a complete local Apple
Silicon/macOS 15 build: 98 Qt results, the actual native input-worker fixture,
seven fullscreen/platform checks and three Quit lifecycle guards. The queue
fixture passed 50 repeated runs and an AddressSanitizer build. The split root
passed six CTest gates and 38 CI-policy tests. Final package checks remain.
This source result has not replaced the accepted local Client installation.
The Wacom report callback retains its device and buffer until IOKit calls back;
an OS request that never calls back is capped at 64 retained contexts so a late
callback cannot access freed memory. The release barrier gives up after two
seconds and a stalled worker owns its state until it exits. Neither behavior
has been exercised with a stalled physical device.

Client `26c031a` merges upstream clipboard support with this Mac branch. Its
common-C pointer advances to canonical `16a7a50`, which includes the merged
queue-order fix. The text conflicts combined the mouse-motion and clipboard
includes, and retained both presentation and clipboard topology tests. Diff
checks passed; the merged Client has not yet had a fresh Mac build or live
tablet acceptance, so the results above remain tied to `397678e`.

### Maintainer follow-up — 2026-09-17

Client `a6faf27a` fixes the timeout latch rather than extending the two-second
wait. Requested focus/reconnect state and release tickets share one lock.
Forwarding becomes eligible only after the worker acknowledges every requested
physical release. A late release resumes input without another focus event or
reconnect callback, but cannot override a newer focus loss, reconnect, Quit or
worker exit. Stale report epochs and worker-owned shutdown lifetime remain.
This changes only the Mac raw-HID Client path, not Linux input or the wire format.

The Qt6.10.2 Wacom suite passes all11 results (including init/cleanup),30 repeat
runs and ASan/UBSan with leak detection in an isolated Ubuntu26.04 test container.
These are portable state tests, not IOKit or physical-device fault injection.
Five new cases cover delayed focus recovery, delayed reconnect completion,
newer requests superseding older acknowledgments, focus loss during reconnect,
and terminal shutdown/exit.

Client `82436e5a` and the parent build changes select the unified15.0 minimum.
SDK27 remains mandatory independently of deployment target. Dependency cache
identity changes, application/dependency/DMG gates share the target policy, and
every Mac build runs real Mach-O target-validation fixtures. The complete
packaged app is checked again after Qt deployment. Portable validation passes:
43 CI tests, six root CTest suites, seven fullscreen checks and three Quit
guards. Native Mach-O execution is explicitly skipped on Linux. The new
candidate version is1.0.129; hosted/native builds and live macOS15/macOS27 tablet
acceptance are pending, not implied by these source-level checks.

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
  branch is limited to the Mac scope.
- [root PR #4](https://github.com/instinctual/plank/pull/4) coordinates the
  Client pin, unified target build paths, focused tests and this evidence.
- [libvirtualhid PR #1](https://github.com/instinctual/plank-libvirtualhid/pull/1)
  was merged as a separate Pause-key correction for Linux; it is not a Mac
  Client dependency. The Linux Host dependency pin is in
  [Host PR #7](https://github.com/instinctual/plank-host-linux/pull/7).

Upstream Client `0544586` and root `7dd2c1a` were merged into the review
branches. The upstream Quit implementation replaced the earlier bridge; Mac
capture/fullscreen changes remain macOS-scoped, while Linux/Wayland behavior
retains its upstream policy. No upstream merge or release has occurred.

## Gates before merge

1. Exercise the new asynchronous Wacom path on physical hardware: pressure,
   focus loss, reconnect, Quit and unplug/replug. The deterministic test covers
   delayed callback state and release deadlines, but not a stalled HID driver.
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
