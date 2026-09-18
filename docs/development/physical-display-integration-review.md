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

The Linux Pause-key dependency pin is tracked independently in
[Host PR #7](https://github.com/instinctual/plank-host-linux/pull/7), following
the merged [libvirtualhid fix](https://github.com/instinctual/plank-libvirtualhid/pull/1).
This display series leaves the Host dependency pointer at its base revision.
Earlier display-test RPMs contained the Pause pin; their reported test results
remain specific to those exact packages.

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

## Virtual connector order follow-up

On the standalone virtual-startup Rocky Host, a two-output bookmark put
1920×1200 on the left and 2560×1440 on the right. GNOME's primary flag alone
did not place Flame correctly: Flame opened on the left because virtual
connector `DP-0` (PLK Display 1) was there. A reversible live XRandR swap put
`DP-0` on the right, and the operator confirmed Flame's chooser opened on the
Eizo. The previous Host then reset that manual swap on reconnect.

The paired follow-up adds virtual-primary capability `0x2000000`. The macOS
Client sends the primary screen's index in left-to-right desktop order when
the Host advertises it. The Host binds `DP-0` to that side during live and GDM
transitions; earlier Clients retain the old connector order. The protocol
vector covers the asymmetric right-primary case. Rocky display-preparation
shell tests, local macOS Client tests, and Rocky 9.7 CI run `35303224086`
passed. The exact RPM was digest-verified and installed on flame-01; the local
signed Client used the same code.

The Client log recorded `plankPrimaryOutput=1` with modes 1920×1200 and
2560×1440. The operator then switched to a single 2560×1440 Eizo session and
returned to the two-output bookmark. The Host supervisor logged both live
transitions. XRandR independently read `DP-2` at 1920×1200+0+0 and primary
`DP-0` at 2560×1440+1920+0. The operator confirmed that the new two-screen
session launched correctly. This establishes the live single-to-dual path on
the tested Rocky 9.5 Host; GDM-start and interruption recovery remain open.

## Headless route comparison on flame-01

On September 17, with `display.startup_layout = virtual`, the operator tested
both connection choices against the Eizo-primary MacBook/Eizo arrangement.
Before each trial, the Host's NVIDIA MetaMode, XRandR outputs and GNOME logical
monitors were captured. **Match client displays** with macOS desktop sizing
rejected the MacBook's current 2056×1286 mode in the Client because that mode
is absent from the virtual EDID allowlist. The Host did not transition; its
4480×1440 layout and primary remained unchanged. Retina backing pixels would
also need a separate canvas-limit check before this route could be qualified.

**Two virtual displays** with the existing 1920×1200-left and 2560×1440-right
bookmark connected. XRandR reported `DP-2` on the left and primary `DP-0` on
the right; GNOME reported the same logical positions and primary. The operator
confirmed Flame's project chooser opened on the Eizo. After normal disconnect,
the NVIDIA MetaMode, XRandR geometry and GNOME logical-monitor geometry matched
the pretrial snapshot exactly. This is a working approximation of the MacBook
size, rather than exact automatic display matching.

The earlier viewport-based physical-startup trial had inconsistent desktop
geometry, but this virtual-startup trial does not reproduce that problem.
For this headless Flame workflow, the physical-output mode-changing helper is
not required by the observed two-screen path. Its potential value for hybrid
workstations with real Host monitors is a separate acceptance question. The
remaining headless display gap is automatic qualification of the MacBook's
current mode, or an explicit, predictable virtual-mode fallback.

## Upstream Host integration

Host commit `0957df96` merges the current upstream Host `main` into the draft
display branch. The only source conflicts were the topology feature declaration
and its test: upstream clipboard synchronization remains `0x400000` on Linux
X11, while matched modes, matched primary and virtual connector order retain
their separate bits. The resulting PR diff has eight display/session source and
test files and no Pause dependency change. The root display branch pins this
Host commit. Diff checks and the Rocky 9.7 package build in hosted run
`35313099850` passed; it has not had a new hardware retest, so earlier package
results do not qualify it.

Client commit `42f583c` merged the earlier Mac review base and upstream
clipboard support with the display controls. Follow-up `d26faf4` merges Mac
review `82436e5`, including Wacom timeout recovery and the unified macOS 15+
deployment policy. The Client keeps the clipboard bit separate from the
matched-mode and primary-output bits. Root display `b3b493f` merges root Mac
review `915f64a` and pins Client `d26faf4` with Host `0957df96`. Accepted
Client main was subsequently merged into display Client `38ea170`, and the
root display branch now follows accepted root main. The earlier integrated
root `61b82b7` passed all five hosted jobs and its local Mac build passed 125
Qt results. The newer root `3d7f413` passed all five hosted jobs, clipboard and
private-information checks. Its Client tree is unchanged by the accepted-main
merge. Portofino currently has SDK 26.2, below the SDK 27 build requirement.
Exact-package live display acceptance remains open.

## Remaining gates

### Maintainer review follow-up — September 18

The maintainer's review of root display PR #7 identified three correctness
gaps. The paired draft branches now address them without changing released
packages:

- Host `09eda225` limits the `DP-0` primary-connector identity check to a
  virtual-startup Host that negotiated that capability. A physical lease with
  a correctly selected `DP-2` primary no longer retriggers a transition.
  The binding test covers that case.
- The root helper verifies the full restored GNOME output set, rectangles and
  selected primary against XRandR before reporting success. Missing outputs,
  stale geometry and wrong primary are regression cases; all 29 no-display
  helper tests pass locally.
- Client `78f6074` offers and applies the Retina-size choice only when an
  authenticated physical Host advertises matched modes. Headless virtual
  Hosts retain the existing panel-native mode selection. The topology test
  covers physical and virtual startup with the capability present and absent.

Root `31b80e4` pins these Client and Host commits on the 1.0.137 mainline
base. Its unsigned four-product hosted build is
[run 35371792390](https://github.com/cnoellert/plank/actions/runs/35371792390).
Policy, Rocky Host, Ubuntu Client, Mac Host and Mac Client jobs all passed.
These are source/build checks, not signed-package or hardware qualification.
The GNU/Linux-only display preparation shell test and the new Host unit case
are in a separate exact-source Rocky qualification
[run 35373732797](https://github.com/cnoellert/plank/actions/runs/35373732797),
which passed. The Rocky job built the Host package and test binary, passed
`PlankTopology.PhysicalLeaseKeepsItsNonFirstPrimaryConnector`, all 29
display-helper cases, and `test-display-prepare.sh`. It did not install the
candidate on flame-01 or exercise live interruption recovery.

This review also confirms the working virtual-output route for the headless
Flame test workflow. The physical-output helper remains a separate draft for
hybrid workstations until its use case and interruption/restoration behavior
are qualified.

1. Test monitor-mode rejection, helper timeout and forced termination, failed
   restoration, abrupt Client exit and transport loss. Verify the original
   physical desktop remains usable, primary is correct and no lease-owned mode
   remains. The existing fake helper tests do not cover all supervisor failures.
2. Qualify exact or predictable fallback sizing for the MacBook's current
   2056×1286 virtual mode, plus virtual GDM-start and interruption recovery.
   Keep the existing EDID presets and manual workflows intact.
3. Qualify the final Client on Ubuntu and supported newer macOS, then repeat
   Mac logical/backing-size, single/dual, primary, Flame launch and normal
   restoration tests with exact build hashes.
4. Merge the paired Client and Host contributions and update their root
   gitlinks before treating the display branch as a reproducible mainline build.

The intermittent left-click failure is also an open Mac Client/Host input gate;
its live recurrence and recovery observations are recorded above. Do not infer
input acceptance from the successful display restoration.

Keep the PRs draft until these gates pass. Physical display mode changes can
interrupt an active desktop, so live failure tests require an operator-approved
window with work saved.
