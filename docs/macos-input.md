# Native Mac input qualification

Experimental macOS/SDK 27 components, integrated with the authenticated A/V
capture owner but not the ordinary Client. Linux input and shared wire types are
unchanged. General desktop keyboard/mouse is the scope; Wacom comes later.

## Boundary

`host/macos/input/input-events.m` translates existing native KyProto input
payloads directly to public Quartz events. It opens no socket, posts nothing,
requests no permission and uses no inherited GameStream packet wrapper.

- Absolute motion uses inclusive wire maxima (`referenceWidth/Height - 1`).
  Captured-display physical pixels and global Quartz point bounds define the
  transform. Negative origins and Retina scales are explicit, not guessed.
- All five mouse buttons are mapped explicitly. Held buttons select drag
  events; duplicate down/up is suppressed. Click counts use the owner's local
  monotonic time and native double-click interval, never a remote clock.
- Vertical/horizontal signed wheel values retain fractions: 120 protocol units
  represent one line/notch. Fixed-point and pixel fields are populated; actual
  application scroll direction/speed still requires live qualification.
- Normalized Client virtual-key identities map to public macOS key constants.
  Alphabet/digits, punctuation, navigation, keypad, F1–F20 and left/right
  modifiers are included. Ctrl maps to Control, Alt to Option, Meta to Command;
  no silent Ctrl/Command swap. Remote snapshots apply to mouse modifier flags.
- Unknown keys/types return Unsupported, never an arbitrary fallback key.
  Non-normalized international identities and UTF-8 text are not qualified;
  neither is pen/raw-HID Wacom input. Do not advertise these as implemented.
- Event acceptance is transactional: if authorization changes after event
  construction, **all** tentative state is rolled back. Stop cannot release an
  undelivered key. Stop is one-shot and returns releases only for tracked input.

`native-input.m` wraps delivery with the existing stream lease and native
endpoint readiness checks. Event construction happens outside the auth lock;
only a bounded internal delivery sink runs under the revocation boundary.
Topology and permission validity are checked again immediately before delivery.
This adapter adds no private input queue/worker or retry after revocation.

The session owner now runs one native blocking receiver on a serial dispatch
queue. The existing transport condition variable wakes it immediately on input
or stop, with a one-second timeout only to recheck ownership. Each packet is
synchronously handed to the serial capture/session queue; at most one packet
awaits that handoff. Input is not polled by the 20-ms lifecycle timer and no
second input backlog is introduced. Framework/capture queue contention still
needs performance measurement; no end-to-end latency guarantee follows.

`quartz-input.m` supplies a private Quartz event source and uses only public
CGEvent posting with existing consent. The owner requires a valid mapper before
capture starts, checks permission during lifecycle and delivery, and drains both
capture and the input receiver before destroying the shared native endpoint.
Owner abandonment revokes first and retains the endpoint until both drains;
the receiver never strongly owns the session between deliveries.

Orderly teardown must call input stop **before** ending the lease. Transport
loss alone does not prevent releasing held input while the same desktop is
authorized. After desktop loss/replacement, discard rather than injecting
releases into another user's session. Actual OS held-state cleanup across
agent/session replacement remains a live gate, not proven by synthetic tests.

## September 7 results

On the dedicated Mac, SDK 27 / deployment 27.0, warnings as errors:

- **1826 event-construction checks**: scaling/offsets, buttons/drag, repeated
  clicks, fractional scroll, representative keycodes, repeat, modifier release,
  malformed/unsupported inputs, one-shot stop and rejected-event rollback.
- **129 checks / seven scenarios** over the unchanged native QUIC input API:
  active delivery, pending lease denial, desktop loss, generation replacement,
  topology/permission denial, revocation between construction and delivery,
  safe same-desktop cleanup after transport stop and no revival.

Neither suite posts OS input, captures user input or uses a real account.
The network suite supplies a synthetic account verifier and an inspecting sink;
it is not proof of TCC permission or WindowServer delivery.

The signed own-window Probe 50 stopped with zero received events, failed focus
and no pointer match. Its guard runs before every posting callback. Read-only
inspection then found the desktop logged in **but screen locked**. Do not
misdiagnose this as event-mapping failure or remove the focus check.

After operator unlock, Probe 51 still refused focus: active=0, key=0,
responder=1, permission=1. Probe 52 moves its single activation request to
`NSApplicationDidFinishLaunchingNotification`, after AppKit launch completes.
No mapper, event source, permission or per-event safety check changed.

**Two fresh Probe 52 Aqua runs passed**: received mask 1023/1023, absolute
pointer match, result/exit zero. This verifies actual private-source Quartz
delivery into AppKit: move, left down/drag/up, right down/up, both scroll axes,
key down/up. The test restored pointer and prior foreground app. The temporary
agent exited/was removed; signed A/V Probe 49 was restored and hash-verified.

Probe 53 extends the live guard to all eight left/right modifiers and deliberate
held-input cleanup. It passes: base mask 1023, modifier down/up masks 255/255,
Shift-key and Shift-click, private-source held-state confirmation, then receipt
of all three generated cleanup releases (key, Shift, left button) and cleared
private-source state. Repeated stop is empty and the stopped mapper refuses new
input. No generated shortcut is sent into a foreign application.

The integrated owner now passes **300 checks / 11 scenarios** using real QUIC
and a non-posting synthetic device. These add actual native input reception,
authorized releases before revocation, no releases into a changed desktop,
permission loss, malformed input and receiver drain/owner abandonment. The
unchanged hardware-video tests still pass 180 checks each at 1080p and 4K.
Signed Probe 54 includes the real Quartz input device with authenticated A/V;
its qualification manifest sets both audio and input true. Synthetic HTTPS
security/admission tests pass. Live A/V qualification does not inject any input;
see HANDOFF for its measured results. The Client draft stays paused.

These tests are not an ordinary Client session, an agent-replacement cleanup
test, multi-display/HiDPI live qualification, or custom cursor extraction.
Do not run it in LoginWindow or send credentials; LoginWindow input remains a
separate operator-coordinated acceptance gate.

After operator logout, signed Probe 56's separate `--login-pointer` mode passed
the strict LoginWindow identity/permission guard and posted two motion-only
packets through the unchanged production mapper/private source. Both targets
and restoration matched the OS-reported position: matches=3, restored=1,
no_held_input=1, result=0. Non-root SSH and root Background invocations both
failed closed before posting. The temporary LoginWindow agent exited and the
authenticated A/V Probe 54 was restored. The operator was observing through
Screen Sharing and cannot confirm cursor visibility; these counters alone do
not establish it. No clicks,
keys, login, capture or display changes were performed. LoginWindow keyboard/
button delivery and authenticated session replacement remain unqualified.

## Accepted Mac cursor contract — September 7

The operator approved ScreenCaptureKit's embedded cursor as the Mac Host
design, not a temporary preview fallback. The stream carries the actual system
and application cursor in its video pixels. Cursor motion and shape changes
therefore inherit capture/encode/network/decode latency; there is no independent
low-latency cursor channel or local prediction. Linux remains unchanged.

The authenticated launch must explicitly declare `cursor: "embedded"` and must
not claim the Linux separate-shape/position capability. When ordinary Client
integration resumes, suppress its local pointer over remote video only; retain
a visible local pointer over the toolbar, dialogs, letterboxing and other local
UI. Do not warp coordinates, inject toolbar events into the Host, or infer the
cursor policy from codec, bit depth or a missing capability. Preserve the local
pointer during disconnect, timeout and session transitions. These Client gates
remain paused until the Host lifecycle is complete.

SDK 27's `NSCursor.h` marks `currentSystemCursor` deprecated and says it will
always return nil in a future macOS version. Apple's public documentation
directs capture applications to ScreenCaptureKit's embedded cursor, whereas
`currentCursor` is only the calling application's cursor:
[Apple NSCursor](https://developer.apple.com/documentation/appkit/nscursor/currentsystem),
[ScreenCaptureKit showsCursor](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/showscursor).

The SDK's checked SCStream API exposes cursor inclusion, not a cursor-image
output. This is not an exhaustive proof that no alternative exists. Do not
implement a deprecated global-image poller, private API workaround, or fake
generic-arrow replacement as if custom-cursor extraction were qualified.
Existing Mac A/V capture already sets `showsCursor = YES`; no runtime change is
required to adopt this decision. Custom-shape/movement capture qualification is
separate from the earlier event-posting tests. The Linux local-cursor contract
and working toolbar behavior are unchanged.

Signed Probe 55 passed two fresh Aqua launches: cursor-disabled baseline,
custom two-color cursor at the expected hotspot, movement to a second position,
reversed custom shape, then cursor-disabled absence again. Each phase requires
two matching samples. The capture filter includes only the probe's own window;
analysis reads BGRA pixels in memory and never persists images. No clicks,
keys, audio or network are involved. The app restores its pointer/focus and the
tested authenticated Probe 54 was restored after qualification. This proves
embedded shape/movement before encoding, not end-to-end latency, arbitrary
application cursor animation or the paused Client's presentation behavior.
