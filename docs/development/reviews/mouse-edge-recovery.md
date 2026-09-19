# Mouse-edge reconnect diagnosis

The Client rounded/clamped absolute positions to the stream width/height,
while common-C serialized inclusive maxima of width/height minus one. A point
on the right or bottom outer edge could therefore exceed its own wire maximum.
The macOS Host correctly rejected that packet, retiring the stream and causing
the Client to briefly show its waiting/reconnect UI.

The boundary error predates common-C PR3. A controlled sender-worker probe
showed that the earlier coalescing could overwrite an edge position across a
button barrier; the corrected queue preserves that position before the button.
Thus the input-order repair can expose an older defect. This does not prove
that every reported transient reconnect has the same cause: older Host logs
did not retain a specific teardown reason.

The operator subsequently reported occurrences away from screen edges, no
attached tablet, and possible idle occurrences. Those are not established as
this boundary defect. Keep the broader session-stop diagnosis open and use the
new first-cause logging to identify the remaining failure path.

## Repair

- Clamp rounded mouse coordinates to the dynamic last pixel in the Client.
- Independently clamp in common-C before queue insertion, rejecting degenerate
  dimensions. Preserve press/motion/release order and all pen mapping.
- Retain strict Host packet validation and held-input cleanup.
- Record one privacy-safe first-cause line at Mac session stop. Status/type
  codes are permitted; input contents and authentication material are not.

## Qualification

The common-C regression exercises 54 positions over six dimensions, including
exact edges, negative/out-of-window drags and the signed-short limit. It rejects
six invalid geometries and verifies ordered edge/press/drag/release delivery.
All six common-C suites passed 25 repetitions. The new test fails when linked
against the unfixed library and passes with the repair. Both Client package
builders also run it against the exact static library linked into the app.

Mac Host tests retain the existing lifecycle cases and add two malformed
one-pixel overruns plus a valid four-corner drag over actual local QUIC. They
check held-input release and first-cause retention. Hosted execution and live
hardware acceptance are recorded in HANDOFF, not implied by local C tests.

The separate operator-approved log policy makes system machine/sign-in logs
root:admin, directory0750/files0640. Installer fixtures cover fresh creation,
upgrades, admin read-only access, non-admin denial and unchanged private keys.
Desktop-user logs and key permissions remain private. No system-wide logging
policy or Linux Host log permission is changed.

## Wallpaper/settings recurrence and screen-lock continuity

The .141 Ubuntu-to-Mac test still exhibits lag over System Settings' Wallpaper
window and worse lag over its Screen Saver window, before the saver activates.
Matching logs show the Host transport already FAILED when input is denied;
the Client sees a closed native data receiver. That is not a malformed-input
or demonstrated permission failure. A bounded Host input receive queue and
synchronous delivery on the capture/control owner queue are diagnostic leads,
not an established cause. Low sampled RTT and sometimes zero missing video
symbols do not exclude every network failure.

.142 classifies the native last-error at teardown without exposing its raw
text, and records bounded input queue-wait/delivery aggregates. The counters
do not change scheduling, queue capacity, event order, retry or timeout policy.
The next controlled test should reproduce Wallpaper/Screen Saver hover and then
disconnect, retaining the resulting product log. Input-queue exhaustion and
delivery stalls must be established before choosing a throughput fix.

Actual screen-lock disconnection is separate: graphical authority previously
revoked permanently on `com.apple.screenIsLocked`. The operator requested that
an authenticated connection remain usable at the OS lock screen. .142 removes
only that revocation trigger, retaining user-switch/sleep notifications and all
per-use graphical scope, permission and machine-admission checks. The synthetic
regression keeps an active lease through saver/lock/unlock notifications and
tests nine terminal scope-change cases. Those tests do not qualify real
ScreenCaptureKit/Quartz behavior at the lock screen; operator validation remains.
