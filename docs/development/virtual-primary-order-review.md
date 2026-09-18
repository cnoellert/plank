# Virtual monitor connector ordering — draft review

## Why this is separate

A headless Linux Host with `display.startup_layout = virtual` already accepts
two qualified virtual modes. In a live trial, GNOME reported the intended
right-hand primary, but Flame opened on the left because the first PLANK
connector (`DP-0`) stayed on the left. Reassigning that connector to the
client's primary side placed Flame's chooser on the intended screen. The
two-virtual-output route then worked, and Host layout readbacks matched the
pretrial state after normal disconnect. This is the workflow demonstrated by the
trial; it does not require changing physical outputs.

## Candidate behavior

This series begins at released 1.0.137 main and uses the existing qualified
virtual-mode allowlist. The Client discovers its primary display, translates
it into left/right desktop order, and sends `plankPrimaryOutput` only when an
authenticated virtual-startup Host advertises capability `0x2000000`. Both
manual two-output and Match Client bookmarks use that ordering. Manual mode
sizes still come from the bookmark. Native two-screen presentation uses the
Host output sizes for its stream boundaries when Mac panel pixel sizes differ.

The Host accepts only an in-range negotiated index. It checks both XRandR's
primary flag and whether `DP-0` is on that side. Live and GDM transitions
assign `DP-0` accordingly; topology reports virtual modes in left/right order
even when connector enumeration changes. Old Clients omit the index and keep
the existing DP-0-left behavior. New Clients omit it for old or physical-startup
Hosts. The private worker-to-supervisor display record advances from
`SC-DISPLAY-3` to `SC-DISPLAY-4`, so those binaries must ship together.

No physical-display helper, temporary mode lease, Retina size setting, codec,
input path, or administrator policy changes belong to this series. The
separate physical-display PRs remain draft while their hybrid-workstation use
case and failure restoration are reviewed.

## Evidence and gates

On 2026-09-18, the exact root, Host and Client pins in this series passed the
[hosted build](https://github.com/cnoellert/plank/actions/runs/35382202995),
including Rocky Host, Ubuntu Client, SDK 27 Mac Client and Mac Host jobs. A
separate [SDK 27 development-bundle run](https://github.com/cnoellert/plank/actions/runs/35386142008)
used those same code pins and produced a locally signed Client with macOS 15.0
minimum. Bundle integrity, local signature and startup were verified on
Portofino (macOS 15.7.4). The exact Host RPM was installed on flame-01
(Rocky 9.5); the Host configuration and XRandR/NVIDIA layout were unchanged by
installation.

With the two-output manual bookmark, the signed Client completed workstation
sign-in and streamed a 4480×1440 canvas. XRandR showed 1920×1200 left on
DP-2 and 2560×1440 right and primary on DP-0. The operator confirmed both
fullscreen windows mapped to the intended Mac displays and Flame's project
chooser opened on the Eizo. After a normal disconnect, both outputs, their
positions and primary assignment remained the same, and mouse and stylus
buttons were released. An abrupt Client process exit also left that layout,
the Host services and released input state intact. The Host log recorded a
transport-loss error after the forced exit and an NvFBC release error on both
normal and forced disconnect; the services stayed active.

The Host already had DP-0 on the Eizo side before this installation. Thus this
first live session validates the packaged pair and presentation, but does not
yet prove that this source changes connector order during a live transition.
The post-exit reconnect and a single-to-dual transition remain in progress.

The previous paired development build passed a single-to-dual reconnect on
the headless hardware-test Host. The operator confirmed that Flame opened on
the intended primary screen, and NVIDIA, XRandR and GNOME readbacks matched
the original virtual layout after normal disconnect. That live result is
historical evidence from the earlier combined build; it does not qualify this
newly isolated source.

Before merge, finish the live connector transition, post-exit reconnect,
single-to-dual return, GDM-to-user handoff, sleep/reconnect and Wacom pointer
mapping on the hardware-test Host. The same Client package needs live macOS 27
acceptance. Unavailable macOS 27 hardware is an open gate, not a passed test.
