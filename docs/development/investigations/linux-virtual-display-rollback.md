# Linux virtual-display transition recovery

The candidate is based on root `6eb31c9e` (the 1.4.22 checkpoint) and Linux
Host `8b02eac3`, matching upstream main at the source check. A live RandR
transition can fail after disabling the previous CRTC. The old supervisor
reported failure but left the desktop with no active output. This change
addresses that missing recovery path; the driver's original mode rejection
is not diagnosed by this patch.

## Recovery contract

Before changing a virtual layout, the supervisor reads a bounded
`xrandr --current --prop` snapshot through its existing unprivileged transient
command runner. A restorable snapshot has the qualified DP-0/DP-2 geometry,
mode, refresh rate, primary output, framebuffer, EDIDs and `non-desktop`
properties. Unknown active outputs, rotation, unsupported modes, incomplete
identity data and unrecognized geometry refuse the change before mutation.
An existing virtual framebuffer larger than its active modes is preserved
exactly, within the configured 8192 by 2160 ceiling. Verification of a newly
requested layout still requires its exact requested framebuffer dimensions.

The requested command runs once. Its exit status and a fresh topology read
must both agree with the request. On failure, including a command that leaves
no active outputs, the supervisor attempts the captured layout once and
independently verifies the resulting geometry and properties. It never invents
a replacement resolution or repeats the failed request.

Restoration is tied to the same active user login, display environment, X socket
and authority-file identity. Replaced EDIDs, connector changes, unrelated output
changes, lost session ownership or unreadable observations refuse a stale
restore. These checks bound recovery; they cannot make multiple external RandR
operations atomic or recover an unavailable X server. A failed restoration is
reported explicitly. The request still fails when the previous desktop is
recovered, so a failed requested layout is never reported as successful.

The change does not restart the display manager, modify persistent Xorg/Host
configuration, expand the mode allowlist, change physical-display leases, or
alter the Client/wire protocol. Display snapshots and authentication cookies
are not logged. Cookies are not read by the new ownership checks.

## Verification

`bash tests/display/test-virtual-display-transition.sh` exercises the production
parser and transaction code with synthetic RandR observations. Set
`PLANK_DISPLAY_SANITIZERS=1` to run with AddressSanitizer and UndefinedBehaviorSanitizer.
Coverage includes single/dual layouts, either primary side, exact saved refresh,
partial command failure, false success, malformed output, failed restoration,
identity changes and loss of ownership during each observation.

The full Host package build runs the same fixture as
`host_virtual_display_rollback_gate`. The manual `linux-display-tests` hosted
job uses the pinned Rocky 9.7/GCC 14 environment, runs normal and sanitized
fixtures, compiles the actual supervisor and session context, and runs adjacent
display-preparation/package-policy checks. It never starts the supervisor or
an X server and produces no installer.

Rocky component run [45543630010](https://github.com/cnoellert/plank/actions/runs/45543630010)
passed both 135-check variants and strict production compilation. Full Host run
[45543876250](https://github.com/cnoellert/plank/actions/runs/45543876250)
built root `3816cf0dbb5b17f29f00ee701b29bfc20cc16120` with Host
`509a3f654dcfae747c77f4f3b59324b4ce6a5586` and passed its input, transport and
RPM gates. The independently verified candidate RPM has SHA-256
`babbab7d4358b75dff7be0495ff8b54a0f0dea04e262481c8e5c18750fd57e0f`.

These results are not installed hardware acceptance. A separately authorized
disconnected installation is still required before installed qualification. Do not replay
a destructive modeset failure on an active workstation to validate this patch.
