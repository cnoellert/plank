# macOS normalized pen input

The existing native input type7 payload remains32 bytes, as encoded by
`plank_transport_input_encode_pen`. No USB report, physical tablet identity,
additional channel, driver or queue is introduced.

Actions:0 hover,1 down,2 up,3 contact move,4 cancel,5 buttons only,
6 proximity leave,7 cancel all. Tools:1 pen,2 eraser (Quartz pointing type3).
Cancel/leave ignore coordinates/tool; buttons-only ignores coordinates/pressure.
Coordinates and pressure are finite0..1; reserved bytes must be zero. Known tilt
and rotation are validated but not injected in this initial pressure-only scope.
Button bits are conveyed in Quartz tablet metadata and paired mouse events:
primary barrel button maps to right, secondary to middle, tertiary to button4.
Tip multi-click uses the same OS double-click interval as mouse handling.
Live application/button acceptance remains pending. No Tablet Margins claim.

Normalized coordinates map through the captured display's current global Quartz
point bounds and physical pixel dimensions, including negative origins/Retina.
Hover distance is never misinterpreted as pressure. Tool change releases old
contact and exits proximity before entering the new tool. Cancel and stream
cleanup emit only owned tip-up/proximity-exit events, at most once.

Each generated event is delivered synchronously through the existing stream
lease and graphical-session checks. A packet can generate proximity then point;
state commits per accepted event, not per packet. Revocation between those two
must not create a phantom held tip. No permission prompt or authorization bypass.

Qualification: synthetic own-process AppKit pressure/proximity passes, production
mapper validation/geometry tests are in `tests/input/macos-pen-events.m`. Real
Wacom input, pressure-sensitive application behavior, session cleanup and Linux
input regressions remain release gates. See `docs/macos-tablet.plan`.
