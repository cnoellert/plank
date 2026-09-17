# Linux physical display matching: separate review

This draft series is stacked after the [Mac Client contribution](https://github.com/instinctual/plank/pull/4).
Its root and Client branches contain only the physical-display changes when
compared with `codex/macos15-pr-review`. The Host changes are in
[Host PR #2](https://github.com/instinctual/plank-host-linux/pull/2).
The split branch was subsequently built and installed for the live restoration
test described below.

## Purpose and boundaries

**Match client displays** already exists. On a physical NVIDIA/X11 startup,
the earlier Host could select a client-sized viewport while the real scanout
remained a different mode. In the observed Flame workflow, GNOME geometry and
that viewport diverged: windows overlapped, aspect ratios appeared wrong, and
Flame chose the other connector. This series optionally uses temporary real
modes on the active physical outputs, verifies XRandR and Mutter agree, and
restores the original NVIDIA MetaMode and primary property when the lease ends.

The existing **Physical displays** bookmark choice and headless virtual EDID
preset policy retain their behavior. A headless Flame Host may be better served
by virtual startup; this series does not establish physical matching as the
recommended headless configuration. It does not permanently edit Xorg or global
DPI settings. Native/Scaled-Span keeps its existing meaning. A separate Retina
size control chooses macOS logical workspace size or current backing pixels
only when using **Match client displays** with a capable physical-startup Host.

The Host advertises matched modes as `0x1000000` and optional primary binding as
`0x800000`. `0x400000` belongs to clipboard synchronization. Client parsing and
Host constants now keep those capabilities distinct; a Client test proves that
a clipboard-only flag cannot validate a non-preset matched mode.

## Implementation

- The Client validates canonical even dimensions, one or two horizontal
  outputs, an 8192-pixel-wide canvas and the negotiated Host policy. It sends
  the Mac primary display index only when that capability is present.
- The Host supervisor owns a session-scoped display lease. It invokes the
  packaged helper as the attested X11 desktop owner, and applies/restores
  through one internal display request version. Generated modes are unique to
  the lease; cleanup must leave unrelated modes alone.
- The helper selects connected outputs, keeps the original active connector
  assigned to the Client primary, constrains each panning domain, and checks
  exact geometry and primary in XRandR and Mutter. Restoration reads back
  both MetaMode and primary instead of trusting process exit status.
- The RPM owns the helper and its Python GObject dependency. Host source and
  this root packaging change must be deployed together.

See the [implementation plan](plans/automatic-display-matching.md) and
[protocol contract](../../protocol/output-topology.md#bounded-physical-display-matching-optional-0x1000000).

## Evidence

A local Apple Silicon/macOS 15 Client build passed 102 Qt results, the native
input-worker fixture and fullscreen/Quit guards with the new capability bit
and the bounded Wacom report path inherited from the Mac Client base.
Twenty-eight fake-command helper tests pass, covering bounds, command injection,
output selection, real modes, panning, primary identity, compositor mismatch,
NVIDIA zero-exit errors, restoration readback and generated-mode cleanup. The
Host topology header also compiles with the distinct bit and a unit expectation
has been updated. Hosted Rocky 9.7 run `35285840457` passed the Linux Host,
Linux Client, macOS Client, macOS Host compile and policy jobs for root
`f8b532d`, Host `87821ef`, and Client `d193690`. Private-information run
`35285840575` passed. The finished Host RPM and installed helper/supervisor
were checksum-verified before the live retest.

Earlier installed candidates were tested on a physical-startup X11 desktop
created by remote desktop software. With the laptop closed and two external 5K
panels, each Mac workspace was 2560×1440 at 60 Hz while each backing surface
was 5120×2880. The 10240-pixel Retina-detail canvas was correctly rejected by
the 8192 limit. Desktop-size mode connected with two real 2560×1440 Host
outputs and the right-hand Client primary. The operator moved a window across
the boundary and confirmed Flame opened on the primary display. Normal
disconnect restored the exact original single-output MetaMode and primary,
removed generated modes and cleared the lease. A separate Client retry fix
passed the 8192-rejection-to-valid-connection sequence without another sign-in
on the same Host worker. That retry behavior is part of this display series.
These are normal-flow observations on earlier exact packages, not qualification
of the newly split branch or standalone operation without remote desktop.

The exact split-branch Host RPM from hosted run `35270406081` (root `e60bfe3`,
Host `ec04961`) was installed on a Rocky 9.5 physical-startup test Host after
its dependency check passed. A matching macOS 15 Client (`d193690`) connected
with two 2560×1440 desktop-size outputs. XRandR and GNOME agreed on the
5120×1440 layout and the right-hand primary, and the operator reported that
window movement and Flame placement worked. **Normal disconnect failed the
restoration gate:** XRandR returned to one output, but NVIDIA retained an active
`PLANK-Match` mode. GNOME had chosen that same-size temporary mode during
logical-monitor recovery. The original NVIDIA mode, primary and GNOME logical
monitor were restored manually by assigning the saved MetaMode, removing this
lease's inactive modes, then recovering GNOME. The Host is no longer in a
temporary layout.

The follow-up source change passes the supervisor-owned mode token to the
helper and removes only that lease's modes after the NVIDIA assignment but
before GNOME recovery. The no-display helper tests include the same-size mode
ordering and an unattached-mode apply failure. The qualified replacement RPM
from run `35285840457` was installed on the Rocky 9.5 hardware-test Host with
`--replacepkgs` after its dependency preflight passed. The signed matching
macOS 15 Client connected twice with two 2560×1440 outputs and the right-hand
primary. On the first normal disconnect, the Host logged exact MetaMode
restoration and briefly showed one output before the operator reconnected. On
the second normal disconnect, independent readback confirmed the original
single-output NVIDIA mode, one primary XRandR output at 2560×1440+0+0, one
primary GNOME logical monitor at (0,0), no `PLANK-Match` modes, no display
lease, and an active Host service. The supervisor logged exact restoration with
no new restoration error. This qualifies normal disconnect restoration for the
tested physical-startup configuration; interruption and failure recovery remain
open.

While preparing the next abrupt-exit test, the operator reported another
remote left-click failure. With the session still active, the Host's XInput
virtual mouse and Wacom stylus were floating slaves with button 1 marked down;
the kernel virtual mouse reported its left button released. Reattaching and
disabling/enabling those XInput devices did not clear the virtual mouse's down state.
After normal disconnect, exact physical-display restoration still passed but
XInput still marked the virtual mouse button down. Restarting the Host service
recreated the virtual mouse attached to the core pointer with button 1 released
in both XInput and the kernel, without changing the original physical mode.
Live click behavior after reconnect remains to be checked. This evidence does
not establish whether the input failure is caused by display matching, raw
tablet forwarding or an independent XInput state transition.

## Remaining gates

1. Test monitor-mode rejection, helper timeout and forced termination, failed
   restoration, abrupt Client exit and transport loss. Verify the original
   physical desktop remains usable, primary is correct and no lease-owned mode
   remains. The existing fake helper tests do not cover all supervisor failures.
2. Compare virtual startup on a headless Flame Host before choosing a deployment
   default. Keep its qualified EDID presets and existing workflows intact.
3. Qualify the final Client on Ubuntu and supported newer macOS, then repeat
   Mac logical/backing-size, single/dual, primary, Flame launch and normal
   restoration tests with exact build hashes.
4. Merge or make canonical upstream submodule commits reachable before treating
   the root branch as a reproducible build input.

The intermittent left-click failure is also an open Mac Client/Host input gate;
its live recurrence and recovery observations are recorded above. Do not infer
input acceptance from the successful display restoration.

Keep the PRs draft until these gates pass. Physical display mode changes can
interrupt an active desktop, so live failure tests require an operator-approved
window with work saved.
