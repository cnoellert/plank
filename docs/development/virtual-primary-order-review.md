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

This series is refreshed onto released 1.0.143 main and uses the existing
qualified virtual-mode allowlist. The Client discovers its primary display,
translates it into left/right desktop order, and sends `plankPrimaryOutput`
only when an authenticated virtual-startup Host advertises capability
`0x2000000`. Both
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

On 2026-09-18, the preceding 1.0.137-based root, Host and Client pins passed the
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

The Host already had DP-0 on the Eizo side before this installation, so the
first live session alone did not exercise connector reassignment. A subsequent
test closed the Client cleanly and temporarily reduced the Host to one
2560×1440 DP-0 output at +0+0. That state remained stable before reconnect.
The unchanged two-output bookmark then caused the Host to expand to a
4480×1440 canvas with DP-2 at 1920×1200+0+0 and DP-0 primary at
2560×1440+1920+0; NVIDIA's MetaMode agreed. The signed Client connected and
streamed that full canvas. This exercises the live single-to-dual connector
transition. The operator also confirmed a fresh connection after the earlier
forced exit. After unlocking the desktop, the operator confirmed Flame's
project chooser opened on the Eizo. No project was opened. After a normal
disconnect, XRandR and NVIDIA still reported the same 4480×1440 layout,
DP-2 left and DP-0 right and primary. The Host and PAM services remained
active, and mouse and stylus buttons were released.

The previous paired development build passed a single-to-dual reconnect on
the headless hardware-test Host. The operator confirmed that Flame opened on
the intended primary screen, and NVIDIA, XRandR and GNOME readbacks matched
the original virtual layout after normal disconnect. That live result is
historical evidence from the earlier combined build; it does not qualify this
newly isolated source.

After an X server restart during tablet hotplug, a later Flame launch put both
its chooser and main UI on the left output despite XRandR marking the right
output primary. Flame's application log recorded its main UI at `0,240` on
`1920×1200` and its alternate UI at `1920,0` on `2560×1440`. A successful
pre-restart launch recorded those assignments in the opposite order. The
restarted NVIDIA MetaMode listed the left connector first; the earlier live
single-to-dual transition had listed the right, primary connector first.
Reordering only those MetaMode entries at runtime preserved both rectangles,
the XRandR primary and the Plank stream. On the next Flame launch, its log
placed the main UI at `1920,0` on `2560×1440` and the alternate UI at `0,240`
on `1920×1200`; the operator confirmed the chooser appeared on the intended
primary screen. The display helper now writes the primary connector first in
its boot MetaMode too. Its isolated Linux shell test passed. The exact-source
[hosted build](https://github.com/cnoellert/plank/actions/runs/35402337659)
passed all four product jobs, and the checksum-verified Host RPM was installed
on the hardware-test Host. A clean reboot with that package first generated the
expected single-output login layout. After Match Client workstation sign-in,
the newly started user X server read a dual-output MetaMode listing the right,
primary connector first. NVIDIA and XRandR reported `DP-0` at
`2560×1440+1920+0` and `DP-2` at `1920×1200+0+0`; Xinerama head 0 was the
right output. Plank retried while the new X server started, reconnected
automatically after the GDM-to-desktop handoff on its fifth attempt, and
streamed the full `4480×1440` canvas. Flame's new application log
placed its main UI at `1920,0` on `2560×1440` and its alternate UI at `0,240`
on `1920×1200`. The operator confirmed the chooser appeared on the Eizo.
This qualifies persistence through a clean Host reboot and one authenticated
GDM-to-user handoff on this hardware.

The Client and Linux Host branches were then merged with their released
1.0.143 main branches, and the root integration was merged with 1.0.143 while
pinning those combined revisions. The subrepository merges were conflict-free:
the released Client contributes its absolute-coordinate edge correction and
the released Host contributes immediate Linux mouse-button delivery.

The first refreshed exact-source hosted build exposed an intermittent failure
in the Linux Host's progressive transport-loss test at 3% and 5% loss. Repeated
Rocky 9.7 diagnostics isolated the failure from the display changes: the
fast-send congestion controller admitted only 64 datagrams per flight while a
protected frame required about 318. KyProto could expire the incomplete frame
after 50 ms before later acknowledgement rounds delivered its repair packets.
Kernel UDP receive-buffer errors and Quinn datagram queue evictions remained
zero. Raising only the Host fast-send minimum to 512 datagrams recovered every
frame in 12 of 12 repeated Rocky 9.7 runs across 0%, 0.5%, 1%, 3% and 5%
progressive loss. The independent correction is reviewed in
[root PR #11](https://github.com/instinctual/plank/pull/11) and is included in
this integration candidate until that dependency is accepted upstream.

An exact-source hosted build and repeat hardware check are still required
before the earlier results qualify the refreshed revisions. Before merge, the
refreshed source also needs sleep/reconnect and Wacom pointer mapping on the
hardware-test Host. The same Client package needs live macOS 27 acceptance.
Unavailable macOS 27 hardware is an open gate, not a passed test.
