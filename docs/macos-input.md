# Native Mac input qualification

Experimental macOS/SDK 27 components, not enabled in the ordinary Client or the
authenticated A/V capture owner yet. Linux input and shared wire types are
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
There is no private input queue/worker or retry after revocation.

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
misdiagnose this as event-mapping failure or remove the focus check. Probe 51
adds focus-state diagnostics only; compiled/signed, not run. The tested A/V
Probe 49 was restored and its executable hash/signature verified.

Next: operator unlocks the dedicated Mac; temporarily install Probe 51 and run
the bounded Aqua own-window test. It expects ten tagged event classes (mask
1023) and absolute pointer agreement. It restores the pointer/foreground app.
Do not run it in LoginWindow or send credentials. LoginWindow input remains a
separate, operator-coordinated acceptance gate.

## Cursor decision still open

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
Existing Mac A/V qualification still embeds the cursor. The Linux local-cursor
contract and working toolbar behavior are unchanged. Resolve the Mac cursor
contract before ordinary Client integration; no permanent fallback was selected.
