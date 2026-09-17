# PLANK handoff

## Publication-time upstream refresh

Upstream advanced during draft publication: Client `86682b5` and root
`cb01cfe` replace the earlier Quit bridge with MacApplication exit ownership and
captured Command-Q handling. Review Client `d9ad2b1` merges those changes while
retaining raw Wacom focus/cleanup and display routing. Root merges the matching
build/tests, runbook and release history. Candidate 1.0.128 supersedes the
1.0.127 review snapshot. A fresh application build from clean root `9b495ee`
passes 101 Qt results (including upstream's nine shortcut/eight application
lifecycle results), native input-worker ordering, seven fullscreen guards,
three Quit lifecycle guards, seven portable suites and 38 CI tests. All 106
Mach-O targets, dependency closure, build-path and ad-hoc signature checks pass.
Executable SHA256: `3fcabb629d9c1159921ac22e7ebb4c1f1e37e9bfe7b17d113413c00e0b546802`.
Retained artifact: `artifacts/development/macos15-pr-publication/PLANK Client Development.app`.
The installed accepted Client 1.0.126 / Host 1.0.125 are unchanged; 1.0.128 is
not live-accepted. New Client/root commit ranges and publication docs pass
privacy checks. GitHub's hosted-build and privacy workflows report
`action_required` without running jobs; maintainer action and hosted validation
remain pending.

## PR publication and regression review

The operator requested comprehensive documentation and protection of working
upstream paths before contribution. Root and Client branch
`codex/macos15-pr-review` is isolated from the accepted `codex/macos15-client`
checkout and installed Client 1.0.126 / Host 1.0.125. See the
[integration review](docs/development/macos15-integration-review.md) and
[five published draft PRs](docs/development/pr-drafts/README.md).

Fetched root `424204b` and Client `b9e4be6` and reconciled the Retina overlap,
retaining upstream's native Quit bridge and root build-cache/release work.
Review Client `9c1af82` limits automatic capture, native Space cleanup and
single-host-output presentation policy to macOS; Wayland keeps upstream policy.
Root `50a05e1` keys dependencies by explicit deployment target and adds platform
guards. The common-C PR must target `plank/client`, not the repository's default
`atomics` branch; the Host library PR targets `plank/main`, not `master`.

Clean candidate 1.0.127 passes 84 Qt cases, seven fullscreen/platform guards,
native input ordering, 106 Mach-O/dependency/signature gates, seven portable
CTest suites and 38 CI tests. Executable SHA256:
`96807fe329b4e24e0a5e6e08785b0f4e831ea0abb853de0f7d6a4d4892a87442`.
Artifact: `artifacts/development/macos15-pr-review/PLANK Client Development.app`.
New-commit privacy scans pass across all five repos. This candidate is not
deployed or live-accepted. Ubuntu Client and supported newer-Mac qualification,
recovery/hotplug, physical single-output and failure-restoration gates remain.
All five contribution branches are published to contributor forks, with linked
draft PRs: root [#4](https://github.com/instinctual/plank/pull/4), Client
[#3](https://github.com/instinctual/plank-client/pull/3), Host
[#2](https://github.com/instinctual/plank-host-linux/pull/2), common-C
[#3](https://github.com/instinctual/plank-common-c/pull/3) and libvirtualhid
[#1](https://github.com/instinctual/plank-libvirtualhid/pull/1). Upstream bases
were unchanged at publication. Initial GitHub inspection reports no conflicts
and no status checks; that is not CI acceptance. Canonical dependency
reachability, platform/recovery qualification and maintainer review remain
merge gates. No upstream merge, release or installed-binary change was made.

## Secondary fullscreen window cleanup accepted

Client candidate 1.0.126 explicitly leaves and synchronizes a secondary native
fullscreen Space before hiding its window. Reentry shows the window before
requesting fullscreen. Primary Cocoa transitions are synchronized as well.
Two connected Client screens now provide capability only: a physical/fixed Host
uses its authenticated output count, while a requested single/dual layout uses
its resolved count during Host transitions. A single-output session therefore
does not allocate a second presentation window.

The native Metal probe now uses product-native Spaces and checks three repeated
exit/hide/reentry cycles against AppKit visibility/fullscreen state, SDL state,
display identity and real Metal readback. All three native cycles and 14 Metal
readback cases pass on the authorized two-display Mac. Topology coverage
includes single to dual and dual to single transitions. Clean root `b0fb4acd`,
Client `0f57be38`, produced
`artifacts/development/macos15-presentation-lifecycle/PLANK Client Development.app`.
The 84 Qt cases, five fullscreen checks, native input ordering, 106 Mach-O target
checks, dependency closure and ad-hoc signatures pass. Executable SHA256:
`f094e779e6ed1f7b390c99fcfd40b70a0d6c159d9c746bff2a4e8d07fdc5db64`.
The operator reports the correction is working. The authenticated matched-display
session independently logs one window, two fullscreen outputs, then one window
again, with no fullscreen transition failures or synchronization timeouts.
This accepts fullscreen/windowed cleanup with macOS desktop size/Native retained.
A physical single-output session has not yet been observed in this candidate's
log; that separate live case remains pending. Host 1.0.125 and tablet permissions
are unchanged.

## Preserve primary output identity for application monitor selection

A single-output to matched-output transition reassigned the original active
Host connector to the secondary Client screen. XRandR, Xinerama and Flame's Qt
screen list all correctly reported the Client primary, but Flame's independent
internal screen enumeration still placed its main UI on the other connector.
A controlled live swap retained both Client screen positions and dimensions
while assigning the original Host connector to the Client primary. Flame's
normal launch then selected the intended display, confirmed in its graphics
log and by the operator. No persistent Flame override was installed.

Candidate 1.0.125 preserves the active Host primary connector when applying a
matched layout. If the primary property names an inactive connector, it uses
the first active output. The remaining outputs keep desktop order; omitted
primary negotiation keeps the previous selection behavior. Twenty helper tests
pass, including single/matched transitions, right-hand primary, alternate
connectors, inactive primary and rollback after reassignment. The Client
is unchanged. Clean root `7c63f4bd` and Host `d96eb476` produced the installed
Host RPM, SHA256
`243025b6f79ee1b7577047bfdc668f88a59f4668edd041a60d33a7752eac3ac2`.
Package gates, installed-file verification and helper/source byte comparison
pass. Configuration/certificate hashes are unchanged and services remain active.
The isolated builder is stopped.

The previous authenticated session restored the exact single-output baseline
and saved primary property, with all lease modes removed despite their extra
test attachments. Three live trials of the installed helper pass: single
primary, matched desktop-size and matched Retina-size. Each retains the original
active connector for the Client primary, verifies XRandR/Mutter geometry, then
restores the exact baseline and removes owned modes. The corrected Host is at
direct Client sign-in for authenticated repeat testing; this remains pending.

## Primary matching and fullscreen-height candidate

Candidate 1.0.124 adds optional matched-primary negotiation (`0x800000`) and
copies the Client OS primary display into the temporary Linux layout. It
verifies the result in XRandR and Mutter and saves/restores the previous
primary property separately from the NVIDIA MetaMode. Restoration now requires
readback, covering NVIDIA's zero-exit-status assignment failures. Sixteen
helper tests and 19 focused Host tests pass. Two older session-context tests
were corrected to use invalid odd dimensions; their previous dimensions became
valid with bounded matching. Test commit `d96eb476` changes no product source
relative to the packaged Host `376462a4`.

Both products built from clean root `2e111e0b` as `1.0.124-macos15-client`.
Client `b6d5e12` is staged under `artifacts/development/macos15-primary-retina/`;
83 Qt cases, native input ordering, five fullscreen checks, 106 Mach-O checks,
dependency closure and ad-hoc signature verification pass. Client executable
SHA256 `da56e1e1ac1f7a86df6ddd3aa59e91f68a0a59cd2b3fa4215e09a7b1fe77f1ee`.
The installed Host RPM passes package and installed-file verification; SHA256
`a92bc61be92e965ae577ab84bc4e71ba653f9feaf0e3dd9e891600994df29f6f`.
Configuration/certificate hashes are unchanged, all Host services remain active,
and the isolated builder is stopped.

Four independent live helper trials pass: logical/backing sizes, each with the
left/right output primary. XRandR and Mutter agree on geometry and primary;
exact MetaMode/primary restoration and temporary-mode cleanup pass each time.
The authenticated Retina-pixel session now binds primary index 1 and the Host
reports 4112x2572 at 0,0 plus primary 2560x1440 at 4112,0, with no panning.
Operator visual/drag acceptance and full-session disconnect restoration remain
pending. The new client is connected for that test.

The experimental macOS 15 Client also includes the measured five-point AppKit
margin below a camera inset, correcting the predicted fullscreen viewport to
2056x1286 logical / 4112x2572 backing pixels for the observed scaled mode.
Newer macOS geometry is unchanged. The live Client log confirms its requested
4112x2572 viewport equals the settled native fullscreen Metal drawable exactly;
the standard-density output remains 2560x1440.

## Matching layout correction accepted in desktop-size mode

The first authenticated automatic-matching trial exposed a retained NVIDIA
panning domain larger than the requested Mac logical-size output. Pointer
movement shifted that viewport into the adjacent display despite an initially
correct CRTC position. The helper now sets each panning domain to its exact
output rectangle and verifies that it cannot move. Ten helper tests pass,
including rejection of a larger domain at an otherwise correct position and
NVIDIA's zero-exit-status assignment error. Clean root `68cb3f6a`, unchanged
Host `d5ead767`, produced Host `1.0.123-macos15-client`; package gates and
installed RPM verification pass. RPM SHA256
`3f3ccd8874467cbb2e1e67e78cec68bf6dcd0e08f5613c3c7b754a1bc68b0638`.
Configuration/certificate hashes are unchanged. All packaged Host services and
the existing remote-desktop service remain active; isolated builder stopped.

With the unchanged Client `efce3aa`, the operator now confirms both screens
look correct after reconnecting, entering fullscreen and crossing the pointer
between outputs. Active geometry was independently observed as 2056x1290 at
0,0 and 2560x1440 at 2056,0. This accepts the overlap/aspect correction for
**macOS desktop size**. Retina pixel detail still needs its own live acceptance.
The earlier single-output MetaMode at origin 0,0 was restored before this
connection; the operator subsequently disconnected, and exact restoration of
that baseline plus removal of this lease's generated modes is verified.
The older manually generated test mode remains inactive for later cleanup.

Separately, the Mac camera-safe size estimate differs from the settled native
fullscreen content height by a few logical pixels; investigate before claiming
exact Retina matching. The supervisor's legacy MetaMode assignment path still
needs readback verification for zero-exit-status driver errors.

## Automatic matching implementation and earlier qualification

The operator selected automatic display matching including Retina and requested
that existing bookmark layout/scaling controls be retained. A separate **Retina
size** choice now selects **macOS desktop size** or **Retina pixel detail** under
**Match client displays**; Native/Scaled-Span semantics are unchanged. See
[the plan](docs/development/plans/automatic-display-matching.md) and
[protocol contract](protocol/output-topology.md#bounded-physical-display-matching-optional-0x400000).

- Client `efce3aa`, clean root `bfa01708`, version `1.0.121-macos15-client`:
  `artifacts/development/macos15-automatic-match/PLANK Client Development.app`.
  82 Qt cases, five fullscreen checks, native input-order check, 106 Mach-O
  target checks, dependency closure and ad-hoc signatures pass. Executable
  SHA256 `133d273f44d7c2a790a8a64c6c1ce0e67badd216966f28a826b15e03c1b044b8`.
- Host `d5ead767`, clean root `3abc08d4`, version `1.0.122-macos15-client`:
  RPM built in the retained isolated pinned Rocky 9.7 container and installed on
  the authorized hardware Host. Eight focused Host topology tests, seven helper
  transaction tests and package gates pass. RPM SHA256
  `9ee6e2f4d2058432060ef5c863309d904bb9b7c89b6b23e68fa3a71d43b56c51`.
  Installed RPM verification passes; configuration/certificate hashes match the
  pre-update snapshot, and Host/PAM/display/Anyware services remain active.
- Live helper tests, including the supervisor's restricted service context,
  independently pass logical-size and backing-pixel dual layouts. XRandR and
  Mutter agree; exact initial MetaMode restoration and owned-mode cleanup pass
  after both tests. The initial restricted-path probe exposed inaccessible
  desktop-bus sockets; the final Host uses a read-only attested runtime bind.
- New Client opened and the separate Retina control inspected. Initial bookmark:
  Match client displays, macOS desktop size, Native scaling. Authenticated
  geometry acceptance is recorded above; automatic-matching drag and the
  alternative Retina-size choice remain unchecked. No persistent system DPI
  or Xorg configuration change was made.

The accepted native-Spaces Client and Pause Host below remain rollback artifacts.
Intermittent left-click recurrence is parked at the operator's request; its cause
is not established. Original pre-testing Host layout restoration remains due at
end of all live testing. Machine details and test captures stay in private audit.

## Fork continuation — experimental macOS 15 Client

Branch `codex/macos15-client` explicitly adds the macOS 15 Client target.
Read [the fork build/evidence notes](docs/development/macos15-client.md) and
the operator's local `private-notes/macos15-client.env` before continuing.
The self-contained development Client builds and opens on macOS 15.7.4.
Client tests, minimum-OS/dependency checks, real transport loopback and the
portable root qualification suites pass. Full live-session acceptance is pending.
Published Linux Host 1.0.105 was initially installed on the operator-authorized
hardware test Host; the Pause correction below now supersedes it. Its original
RPM dependencies and transaction passed on the installed Rocky 9.5;
Host/PAM/display services are active, with physical display policy and the
existing HP Anyware service still active. HTTPS certificate verification and
Client command-line discovery pass. A subsequent authenticated graphical session
completed a 45-second smoke test over LAN IPv4: 2560×1440@60, HEVC 10-bit 4:4:4
identity with VideoToolbox/Metal, stereo audio packets and input delivery. Logs
agree on 2,684 video frames, 8,595 audio packets and 1,875 input events, with zero
transport receive drops. Render rate was 59.67 FPS with 15 pacer drops (0.57%).
Toolbar disconnect completed and services remain active without restarts.
The operator confirms login and reports working basic keyboard/mouse input and
audible audio playback. Channel placement, sync and sustained audio remain unchecked.
The operator also confirms normal disconnect/reconnect works on one monitor.
The next candidate implements two-display Cocoa/Metal presentation at Client
`31f6081`. One decode feeds two cropped Metal surfaces using the shared input
geometry; the toolbar stays on the primary output. All 58 Client test cases pass.
Native GPU pixel readback passes eight windowed and eight fullscreen cases on
two physical Mac displays, covering software GBR10 and VideoToolbox P410 surfaces,
V-sync on/off and repeated single/dual renderer lifetimes. Full live two-monitor
acceptance is pending. The Host's second scanout has been enabled for that test;
the exact previous layout and restoration instructions are in private notes.
Linux display matching still rejects unlisted native presets.
The clean candidate built at root `50544c9` is staged with its manifest under
`artifacts/development/macos15-multimonitor/`; all 106 Mach-O target checks,
dependency closure and ad-hoc signatures pass. A live dual-1080p session
established two Metal outputs, fullscreen/windowed transition and clean
disconnect. Its fullscreen renderer ran at 48.16 FPS with mixed 48/60 Hz client
displays; the final windowed segment ran at 59.96 FPS. The operator reported
the fixed Host resolutions did not match the intended Client screens.
The next live connection uses a manually prepared physical Host layout matching
the Client's two native resolutions, with both client screens at 60 Hz by explicit
operator approval. Host, stream and Client canvas agree at 6016×2234; both Metal
outputs and exact HEVC10/P410 hardware decode initialize. The 24-second test
rendered at 59.63 FPS, delivered 1,449 frames and 1,251 input events with zero
transport receive drops, and disconnected cleanly; nine pacer drops (0.65%).
The operator's screenshots show an incomplete desktop on the Retina output.
Host investigation found two XRandR monitors but only one Mutter logical monitor:
the second output's duplicate-name mode selection was not recognized by Mutter.
Selecting its other existing timing preserved native geometry and made Mutter
recognize both outputs. The operator confirms resolution and screen fill now
work; the 53-second retest rendered at 59.82 FPS and disconnected cleanly.
Framebuffer/stream agreement alone is insufficient acceptance. See the fork
notes and private diagnosis. Pointer acceptance is pending. Automatic Retina
matching remains blocked by the mode allowlist. The operator then reported that
window dragging cannot cross displays and that an attempted manual revert left
the Host layout unusable. The saved single-output 2560×1440 Host baseline has
been restored and independently verified in XRandR and GNOME. Do not assume the
two-output test layout is active. Client `a78f7bd` resolves captured drag
coordinates through the target Mac window before applying its DPI mapping;
all 62 Client tests pass. This correction is not yet live-accepted and the exact
cause of the reported drag failure remains unconfirmed. The operator clarified
that a remote window also would not close, so click positioning/delivery must
be checked before attributing the failure only to drag capture. The candidate
from clean root `af6de59` is packaged at
`artifacts/development/macos15-multimonitor-drag/`; 106 target checks, dependency
closure and signatures pass. The operator confirms moving and closing remote
windows both work in Windowed mode against the restored single-display Host.
The subsequent test exposed a windowed-start/fullscreen-toggle bug and a
reported reversed monitor order. Client `74402df` keeps multi-output capability
when starting windowed and prepares its second surface hidden; all 62 Client
tests pass, but live transition/drag/order acceptance is pending. The Host now
uses a temporary real 3456×2234 mode instead of scaling a 1024×768 scanout.
XRandR and Mutter agree on actual current modes and adjacent monitor rectangles.
The clean `b05ccdc` candidate is packaged under
`artifacts/development/macos15-windowed-transition/`; 106 target checks,
dependency closure and ad-hoc signatures pass. The new native Client is open
for live input/order/transition retesting. The operator confirms the display gap
is closed. An authenticated windowed-start session now transitions to two Metal
outputs and back. A slow manual trace preserves the held button through twelve
Host display-seam crossings; the operator confirms the Settings window moves
between both Host desktops in windowed mode. Fullscreen cross-display drag
acceptance remains open. Automated rapid dragging exposed a
separate input-order defect: later motion overwrites the press location.
Client `0be626c` / common-c `0c82257` coalesces only adjacent mouse motion at both
SDL and native-input layers. A deterministic queued-drag worker test fails on
the previous implementation and passes after the fix. All 71 Client cases pass;
the worker check now runs in every Mac Client build. The clean root `deb9e8a`
candidate is packaged under `artifacts/development/macos15-input-order/`;
106 target checks, dependency closure and ad-hoc signatures pass. The previous
client disconnected cleanly. The replacement passes rapid windowed dragging
in both directions, with Host window geometry confirming the press and drag.
Fullscreen dragging still stops at the physical screen seam, despite both
native Client windows simultaneously covering their respective displays.
A separate two-window SDL probe records held drags across both screens in both
directions. Source inspection found startup explicitly disables automatic
mouse capture while the SDL3 input handler relies on it. Client `67564e5`
enables automatic capture; all 71 Client checks and the native input worker
regression pass. The clean root `aeb7279` candidate is packaged under
`artifacts/development/macos15-fullscreen-capture/`; 106 target checks,
dependency closure and ad-hoc signatures pass. Executable SHA-256 is recorded
in its adjacent manifest. The operator now confirms fullscreen window dragging
works in both directions. An independent Host trace records nine held-button
seam crossings in both directions, with remote window geometry changing.
Current state: corrected Client left connected for continued operator testing,
local probe closed, two native-resolution Host monitors prepared; original
layout restoration remains due when the operator finishes testing. This accepts
the fullscreen drag correction, not all multi-monitor/color/pacing gates.
The operator reports a remaining fullscreen input issue: right-clicking the
other presentation window requires a prior activation click; native focus does
not follow the pointer. This is not covered by the accepted drag test. First-click
forwarding is already enabled in SDL, and the shared mouse handler does not
explicitly reject right-clicks solely for missing keyboard focus. Trace native
button receipt, focus and Host delivery before changing focus policy. Acceptance:
first right-click after crossing either direction works without an activation
click, while held seam dragging and button release continue working.
Client `e2d4792` adds a focus handoff: while a presentation window already
owns keyboard focus, unpressed pointer movement may raise the fullscreen output
under the current desktop pointer. Held drags retain their starting window;
a final button release can hand focus to the destination afterward. Hidden,
minimized, windowed and non-presentation focus states are excluded. The operator
confirms that the first right-click now works on either fullscreen output and
cross-display dragging still works in both directions.
The clean root `a1cc07e` package is under
`artifacts/development/macos15-fullscreen-focus/`; 71 Client checks, native
input ordering, 106 target checks, dependency closure and ad-hoc signatures
pass. The previous Client disconnected cleanly. The replacement is connected
and left open for continued operator testing. Host layout remains prepared;
restore the saved baseline when testing finishes.
Restore the saved Host MetaMode and remove the temporary mode after testing.
The temporary Mac refresh change has been restored to its original setting.
Machine-specific details and logs remain in private notes/audit.
The next operator-selected target is USB Wacom forwarding. A standalone
[Mac Client read probe](probes/wacom/macos-client-hid.md) builds and passes target
and signature checks. Two USB tablet interfaces expose exact descriptors and
allow nonexclusive open/close and feature GET with the Wacom driver running.
A coordinated 60-second capture now receives 5,548 ID 16 reports (27 bytes) and
seven ID 17 reports (nine bytes), with changing payloads, intact report ID
prefixes and no callback errors. Both interfaces close successfully. The separate
touch interface is quiet; exact controls exercised await operator confirmation.
The follow-up adds selected HID value callbacks and confirms local pressure
0–7707 of 8191, changing tilt on both axes, tip/proximity transitions, both pen
barrel buttons and 2527 intact 44-byte reports on the touch interface. Both
interfaces open/close cleanly with no raw/value callback errors or out-of-range
values. Eraser, pad keys and ring remain unverified. Active raw input and core
pen fields are accessible alongside the installed Wacom driver. A subsequent
three-second exclusive ownership probe succeeds for both interfaces and releases
both cleanly. Client `285d58b` now implements Mac raw HID forwarding and passive
host-position cursor display through the existing authenticated protocol. Five
wire tests and strict syntax checks pass. The clean root `eab6d64` candidate is
packaged at `artifacts/development/macos15-tablet/`; all 76 Client checks,
native input ordering, 106 target checks, dependency closure and ad-hoc signatures
pass. After the operator grants Input Monitoring and the Client is relaunched,
both physical interfaces attach successfully. The Linux Host now exposes native
Intuos Pro M Pen, Pad and Finger nodes, with pressure maximum 8191 and two tilt
axes. The Client reports exclusive raw forwarding active with no report I/O
failure logged. The operator also confirms that the Wacom appears in Rocky's
Settings. The operator's screen recording now demonstrates variable
pressure in Autodesk Flame's Input Devices / Threshold Test: the pressure bar
changes through intermediate levels, reaches full scale and returns to zero.
This passes application pressure delivery for this candidate. Two separate Host
event captures were empty; their overlap with the recorded physical test is not
established, so they remain inconclusive. The private recording is the acceptance
evidence. Full-display cursor/mapping, buttons/eraser/tilt/pad/touch behavior and
focus/reconnect recovery still need live qualification. The Client remains
connected for operator testing.
The operator reports the tablet also needs fullscreen focus handoff. Client
`b2837fb` now routes fresh Host tablet positions through the existing presentation
focus helper, without comparing them to the stationary Mac mouse pointer.
Mouse drag guards and the requirement for existing presentation-window focus
remain in place. A regression covers stale positions after mouse takeover and
cursor epoch reset.
The clean root `f0d9558` focus candidate is now packaged at
`artifacts/development/macos15-tablet-focus/`: all 77 Client checks, native input
ordering, 106 target checks, dependency closure and signatures pass. Its initial
launch lost pressure because the old Input Monitoring grant did not match the
new ad-hoc signature. A targeted macOS permission reset, normal operator approval
and relaunch restore raw attachment. The operator now confirms both Flame
pressure and fullscreen pen focus work; Client logs also show eight focus
transfers across both outputs. An older Client launched by the OS reopen action
was closed; only the corrected candidate remains running. A coordinated
120-second Host recording independently receives pressure 0–7711 of 8191,
both tilt axes, proximity/tip transitions and both barrel buttons, with no read
errors. Both buttons reach the Host while hovering with zero tip pressure.
Held tablet drags, remaining application controls and full reconnect
qualification remain open.
The operator also reports reduced side-button hover distance compared with macOS.
The Host already enables hover clicks and uses absolute mode. Its X driver 1.0.0
applies the configurable proximity cutoff only in relative mode. No Host tablet
settings were changed. The recording shows button events at several raw distance
values; these are not physical height measurements and do not establish parity
with macOS. The operator subsequently reports that hover works better.

F15/Pause investigation: SDL 3.4.2 maps Mac native key 113 (F15) to Pause,
and the Client correctly forwards portable key `0x13`. Original Host 1.0.105
uses libvirtualhid `93d57db`, whose Linux uinput and XTest tables omit Pause.
That keyboard had no `KEY_PAUSE` capability and Host logs recorded
unsupported-key submissions. libvirtualhid `b0cc3c8` adds Pause to both paths
and tests key translation, press/release output, advertised capability and
separation from F15. Host `03a59815` selects that dependency. All six focused
Linux backend tests and the canonical Host build/package gates pass. Root
`66ec56e` produced candidate `1.0.116-macos15-client`, installed with verified
RPM/payload hashes. The live keyboard now advertises both Pause and F15.
During the operator's test, a bounded recorder observed 23 complete Pause
press/release pairs without errors. The operator confirms Pause performs its
expected action in Flame; this correction is live-accepted. Services, configuration,
certificate and exact display MetaMode match the pre-update snapshot. The
operator authorized an isolated, pinned Rocky 9.7 Podman builder on the available
Rocky 9.5 hardware Host for this fix; it is stopped after the build. This does not
qualify the hardware Host as a release builder. Machine details stay private.

Post-update mouse check: the operator reports movement without working clicks.
Read-only XInput inspection finds `libvirtualhid Mouse` as a floating slave.
Absolute motion uses XTest, while buttons use uinput, explaining that symptom.
Reattaching only the named mouse restored right-click. Left-click from both
mouse and pen still failed: complete mouse press/release pairs reached evdev,
but XInput retained left-button-down with the kernel button released. A scoped
disable/enable did not clear it. Clean disconnect and Host-service restart
recreated an attached mouse with every button up, preserving the exact display
MetaMode. The operator confirms clicks work again after reconnecting. The
source of the detach/stale state remains
unconfirmed; no permanent code fix is claimed.
Retina backport now underway: upstream morning Client `509f2fc` and `6f0c252`
are cherry-picked as `29ddc66` / `33898c4`. Earlier logical/backing-pixel Retina
matching is already in the fork. Client `10eeb75` preserves coordinated desktop
fullscreen for multiple connected displays; a single display uses upstream
native Spaces and its measured camera-safe Match Client viewport. Shared policy
keeps authentication, startup and reconnect geometry consistent. Input/tablet
and Metal rendering corrections remain intact; stock SDL is retained. Five
fullscreen source/compiled-geometry gates pass. Clean root `6323ec7` built
`1.0.120-macos15-client` under `artifacts/development/macos15-retina/`; 79 Client
checks, native input ordering, 106 minimum-OS/architecture checks and package
closure/build-path/signature gates pass. Executable SHA256:
`6e79dd12e4c9d3725a53926751e83304f0ad365541ab5b671283fb272c422e57`.
Live diagnostics rejected this initial candidate: the two-output session entered
native Spaces because SDL 3.4.2 caches the policy during video initialization.
Client `2d93285` now queries active CoreGraphics displays and sets the hint before
SDL video initialization; a topology-count change during setup fails explicitly.
The fullscreen regression gate now enforces this ordering. Corrected clean root
`15a60d2` passes the same build/package gates, staged under
`artifacts/development/macos15-retina-corrected/`, executable SHA256
`38f93a1b6081906d45bf80112961dd530401841630c43acccf4bf7d2558ac856`.
The superseded app is closed; the corrected app is open. macOS rejected the old
Input Monitoring code requirement, so the app-scoped ListenEvent record was
reset and normal operator reapproval is pending. Live mixed-display acceptance
remains pending. Single-display native Spaces and Mac-host matching are separate
live gates. See the
[backport record](docs/development/macos15-client.md#backlog--upstream-retina-fixes).
The operator subsequently identified the intermediate native-Spaces build as
visually preferable: both menu bars stayed hidden and performance felt better.
That build had not failed a drag/focus test; it was stopped on a policy mismatch.
Client `5b12882` now intentionally enables native Spaces on every presentation
display, retaining the early SDL hint and shared camera-inset calculation.
The fullscreen geometry gates are updated; a new clean build and live two-display
drag, focus, tablet and transition checks are pending. Perceived performance is
operator feedback, not a measured benchmark. This supersedes the display-count
policy above; the prior accepted input code and Linux Host remain unchanged.
Clean root `3f267d4` builds the new native-Spaces candidate under
`artifacts/development/macos15-native-spaces/`. All 79 Client checks, five
fullscreen checks, native input-order regression and 106 Mach-O target checks
pass, along with dependency closure, build-path and ad-hoc signature gates.
Executable SHA256: `ccee56e81b68b8e20484eaa09578d7f07f43622c22fa0e5ad037cabcadcc966f`.
The previous app is closed and the new app is at direct sign-in for live
menu-bar, drag and focus checks. Tablet permission/pressure remains to be
verified with this exact app. No release or performance acceptance is claimed.
The subsequent live session confirms two `native-fullscreen=1` windows with
settled drawables 2560x1440 at 1x and 4112x2572 at 2x below the camera area.
The operator confirms the requested fullscreen/menu-bar, cross-display drag and
immediate right-click tests work. Input Monitoring was renewed through normal
macOS settings: TCC now explicitly allows this exact app, and its live log
confirms both Wacom interfaces attached with raw HID forwarding active. The
session was disconnected during permission recovery; the operator is asked to
reconnect and confirm Flame pressure and pen focus in this native-Spaces build.
Those application checks remain pending; the prior build's pressure acceptance
does not substitute for this check.
The operator then reported another loss of remote left-click. The Client had
already closed before inspection: kernel, XInput slave and master button states
were all released, the virtual mouse was attached, and the exact display layout
was preserved. No Host restart or input/display configuration change was made.
The operator relaunched the native-Spaces artifact and confirms mouse left-click
and pen taps both work. Its running executable hash matches the candidate above.
This is recovery evidence; the intermittent failure's cause remains unconfirmed.
A completed 180-second read-only Host trace records 23 complete mouse-left
press/release pairs, two complete pen-tip pairs and no read errors. Kernel,
XInput and master-pointer button states finish released. No observer remains
running. Flame pressure in
this build remains a separate pending application check.
Other remaining gates: visual/color acceptance, modifier/scroll/display-mapping checks, longer pacing,
multi-monitor and outage-recovery tests;
investigate Host NvFBC teardown and Client renderer/window warnings. The earlier
hostname/offline discrepancy is not root-caused. See the fork evidence notes;
this smoke test is not full live qualification. Credentials must be entered
directly in the Client. Mac Client Wacom support remains experimental.
The upstream operational record below is retained as source context; its
installation and signing authorizations do not describe this fork's machines.

Read AGENTS.md and the platform build runbook before work. Read the private
notes' README before machine-specific work; deployment information stays outside Git.

## Current state

- The operator accepted 1.0.123 and authorized commit, push, merge, rebuild
  and release. Preparing mainline 1.0.124 for all four Host/Client packages on
  GitHub-hosted builders, with verified dependency caching and signed Mac
  packages. Do not relabel candidate artifacts. Clipboard PRs and unrelated
  RK3576 research remain excluded. Publication/build results are pending.

- Current root/Client branch is `macos-quit-lifecycle`, candidate
  `1.0.123-macos-quit-lifecycle`. The operator accepted 1.0.122's behavior but
  requested a fresh implementation without the contributed Quit bridge.
  That bridge is deleted, not layered over. MacApplication explicitly owns
  application exit: cancel active/startup/reconnecting sessions once, retain
  Qt until queued readyForDeletion completes, then perform normal Qt Quit.
  The SDL loop observes explicit exit state, not an injected SDL Quit event.
  Ordinary disconnect remains independent. The tested native Command-Q guard
  is unchanged. Linux, Host, transport and protocol behavior are unchanged.
  See `docs/development/plans/macos-quit-lifecycle.plan`. Local 37 CI, five
  fullscreen and three lifecycle source guards plus five root CTest suites
  pass. Hosted run 35185516514 compiled the application and passed existing
  topology/toolbar/desktop-stage tests, then caught a missing direct SDL include
  in the retained shortcut test after bridge removal. That test dependency is
  corrected; no package was produced by that failed run. Corrected signed run
  `35185783350` passed from root `be387875a3fde8dd87c5a3b4c046d368f1a58457`,
  Client `be8a1e06cba05299f939cea2bc4f440bef1a9196`. Dependency cache restored
  and independently verified. Native suite totals: topology 19, toolbar 21,
  desktop-stage 7, shortcut 9, application lifecycle 8 (totals include suite
  init/cleanup; the latter two have seven and six actual cases). All passed.
  Signing/notarization/stapling/Gatekeeper and signing cleanup passed. Verified
  86,548,985-byte DMG is collected under
  `artifacts/packages/candidates/1.0.123-macos-quit-lifecycle/macos/` as
  `plank-client_1.0.123-macos-quit-lifecycle_arm64.dmg`; SHA256:
  `58847e6616f240a98eb0a8180edefadaf1106ad19653e6f53f854e819f719a8c`.
  Host/Kymux and recursive Client pins remain those recorded below. Live
  acceptance of the rewrite was given by the operator; mainline rebuild and
  release are now authorized. No agent deployment. Preserve the
  original checkpoint branch and unrelated primary-worktree research.

- Accepted behavioral checkpoint: `1.0.122-macos-command-q`. Client commit
  `aaaa6b2ba17fa6e3b212b61a0eb8d938046b8f58` and package source root
  `70928380313edd7ab129bef10524384dd0ce3f39` are pushed. Signed hosted run
  `35183839235` passed with a verified dependency-cache hit, all existing Mac
  suites and eight new `macquitshortcut` test cases (10 Qt results including
  init/cleanup). These native tests run in every Mac Client build. Signing,
  notarization, stapling and Gatekeeper passed. The verified 86,124,020-byte DMG
  is collected at `artifacts/packages/candidates/1.0.122-macos-command-q/macos/`
  as `plank-client_1.0.122-macos-command-q_arm64.dmg`; SHA256:
  `252b4f25ed05aa164b041fe48597d98bb4d2b894ef738cb38c1c356972b0bdbf`.
  Unchanged Host, Kymux and recursive Client dependencies are recorded below.
  Local CI tests (37), fullscreen tests (5), shell syntax and whitespace checks
  pass. The operator reports this works as intended. That broad acceptance
  does not prove every lifecycle scenario; the rewritten candidate needs fresh
  menu/Dock, captured Command-Q and disconnect acceptance. No merge or release
  publication of this checkpoint.

- Mainline 1.0.121 package rebuild completed from pushed root
  `41961fb5e9ef8329711e04d1adf75cc4b2968ce3`. Client PR #1 is approved and
  merged at `b9e4be6b374001bef08ac4753764bc12edcb8357`; the root Client pin
  now includes the macOS native application Quit bridge. Linux Host and Kymux
  pins are unchanged. Clipboard PRs are not included: their reviews requested
  changes. All four hosted builds and package gates passed: Linux Host
  `35166761486`, Ubuntu Client `35166763396`, signed Mac Host `35166765361`,
  signed Mac Client `35166767426`. Both Mac packages passed notarization,
  stapling and Gatekeeper. All downloaded packages passed SHA256 verification
  and are collected under `artifacts/packages/releases/1.0.121/`, with manifest
  and checksums. Both Clients and Mac Host restored verified dependency caches.
  Linux Host had a cold miss because NVIDIA's two CUDA config-common RPMs
  advanced from 13.4.49 to 13.4.92; its successful build saved the new cache.
  Local CI tests (37) and package-collection tests (6) passed. See
  `docs/releases/1.0.121.md` for build links and validation scope. Published as
  [v1.0.121](https://github.com/instinctual/plank/releases/tag/v1.0.121)
  at the operator's request. Its annotated tag identifies the exact package
  source above, not the subsequent documentation commits. Server-side SHA256
  digests match all four packages, manifest and release checksum file. No
  installation or native hardware acceptance was performed. Unchanged Linux Host is
  `9329784ac41f50cbec0c9d76badfd22227ec5e5f`; Kymux is
  `912ece5c64787997f978673ca60d313898a3548c`. Client common-c is
  `b9650552f98d97f6e30c9f007115c6246f0809e5`; qmdnsengine is
  `b7a5a9f225d5e14b39f9fd1f905c4f505cf2ee99`. Host recursive pins remain
  as recorded below.
  Source review found no actionable defect in the Quit bridge, but native
  menu/Dock Quit during streaming/reconnect and physical Command-Q ownership
  remain live validation follow-ups. The author's reported eight lifecycle
  scenarios are not committed tests and were not independently rerun.
  Preserve the primary worktree's unrelated RK3576 research.

- Dependency-cache follow-up is merged and pushed to main at
  `4bd87fbcf5c96d177006ac0ea0c99b532396d5b5` (based on main `4001161`).
  All four hosted products are wired for exact-input caches; the previously
  qualified Mac Client cache format is unchanged. New Linux Host/Client caches
  retain prepared FFmpeg and patch-verification sources; Host also retains
  Boost. Those products and Mac Host cache Rust toolchains/downloaded Cargo
  inputs, never application/transport objects or credentials. Installed Linux
  package/compiler versions and dependency scripts/pins/patches invalidate keys.
  Pull requests cannot save caches; clean bootstrap bypasses restore and save.
  Local 37 CI tests and all five root CTest suites pass. Hosted cold/warm
  qualification passed for all four products; exact runs and phase timings are
  in `docs/development/build/github-builds.md`. Linux Host cold/warm used
  `35144970937` attempts 1/2 at `478edad0ee302c22c713df1cb67b4c4c185340a5`.
  The Ubuntu-specific archive correction is `64f368a4fdb58cc0de267bc8f59ec108a8f43be8`;
  its cold/warm runs `35146540028` / `35147537196` both passed. Initial warm
  run `35146202369` was correctly stopped by the source audit because the cache
  omitted the pristine FFmpeg archive. The archive is now cached and required
  by completeness tests; no source/patch gate was weakened. Mac Host warm run
  `35145530809`, Mac Client warm run `35145993419`, and an additional Mac Host
  cold build at the corrected source (`35146543166`) passed.
  The Ubuntu correction changes cache keys but not the qualified Host cache
  contents/logic. Application and transport source revisions remain identical
  to the 1.0.120 release below. No runtime change, version bump or deployment.
  Post-merge hosted run `35148481593` passed all four products at that exact
  merge SHA and populated main's branch-scoped caches. Do not relabel the CI test packages
  or replace the published 1.0.120 assets. No additional deployment requested.
  Completed root branches `dependency-cache`, `macos-auth-recovery`,
  `macos-fullscreen` and `reconnect-lifecycle`, plus the Client's three matching
  macOS/reconnect branches, were deleted locally and remotely after ancestry
  checks against pushed main. Their commits remain in main. Root, Client,
  Linux Host and Kymux remotes now have only main. Preserve the local
  `rk3576-client` research branch and its dirty primary worktree; it is not
  disposable merely because its committed starting point is an ancestor of main.

- Operator accepted Client 1.0.119-macos-fullscreen and authorized commit,
  push, merge and a full rebuild. Root merge `53c7c3988f88a440f1cffeda0ce61ed526de6c43`
  and Client merge `95060dee8fa63e0da98dfa83e7ddd8185731a837` are pushed to main.
  All four Host/Client packages rebuilt successfully as 1.0.120 from that exact
  root on disposable GitHub-hosted builders with `clean_bootstrap=true`.
  Successful runs: Linux Host `35137573043`, Ubuntu Client `35137572752`,
  signed Mac Host `35137572797`, signed Mac Client `35137572549`.
  Package, dependency, version and platform regression gates passed; both Mac
  packages passed Developer ID signing, notarization, stapling and Gatekeeper.
  All four downloaded packages passed SHA256 verification and collection with
  exact source provenance under `artifacts/packages/releases/1.0.120/`.
  At the operator's subsequent request, all four packages were published as
  [v1.0.120](https://github.com/instinctual/plank/releases/tag/v1.0.120).
  The annotated tag identifies the exact package source above. Server-side
  SHA256 digests match all four packages, manifest and release checksum file.
  Notes are in `docs/releases/1.0.120.md`. No installation or new hardware
  acceptance was performed. Preserve unrelated primary-worktree research. Earlier candidate
  packages below are historical evidence, not the current mainline artifacts.
  Normal full application rebuilds may reuse verified dependency caches;
  reserve cold bootstrap for explicit qualification. At this release's source,
  caching existed only for the macOS Client; the follow-up above extends it.

  | Package (relative to the 1.0.120 catalog) | SHA256 |
  | --- | --- |
  | `linux/plank-host-1.0.120-1.el9.x86_64.rpm` | `b74fd2486ab5864fb332d77d594b03c24ce76355c7651d24c3de3c05f49aa046` |
  | `linux/plank-client_1.0.120_amd64.deb` | `dea73b7f9ac840010ce02f15154b4ae2d4020ef61e925bc787ad0fb821074b53` |
  | `macos/plank-host_1.0.120_arm64.pkg` | `0fc01ce11172d075d864841d26a997c8bb5f5911032afff8536f43d98e244b35` |
  | `macos/plank-client_1.0.120_arm64.dmg` | `618a42f6ff8c86765f3a692b918c852ab7557a79e1733e0294999a219466765e` |

  Root and Client merge SHAs above pin the complete source tree; unchanged
  gitlinks are listed with the accepted evidence below. Linux Host common-c
  is `775943b5ac5e5100a3c2b1b89d9e21151dea4f29` and build-deps is
  `caf0495d5e6baff94f349853d4a59e3779a451a0`.

- Accepted Client 1.0.119-macos-fullscreen evidence:
  Operator tested all five standalone AppKit modes: no side borders, same
  system-owned top notch strip. Operator accepts that strip and native Spaces.
  New policy: Mac-to-Mac fullscreen Match Client uses NSScreen's dynamic top
  camera inset and preserves compositor backing density. Zero inset leaves
  non-notched displays unchanged. Windowed/manual sizing stays unchanged.
  Authentication, startup validation and reconnect use the same viewport;
  original display bounds remain separate for window placement/identity.
  Removed ineffective SDL content-size patch/hint/helper. Bootstrap/cache inputs
  changed, forcing fresh upstream SDL dependencies; FFmpeg patch gates remain.
  Local five fullscreen tests (including compiled geometry), 26 CI tests,
  14 reconnect guards and five root CTest suites pass. Signed hosted run
  `35131997746` passed from root `9167fd8412172fee9d47be9eb2bc67cc155d7750`,
  Client `6f0c25269c5a8bf1051814317440f2cd57fda005`: cold dependency bootstrap,
  SDK27 native compile, 19 topology / 21 toolbar / seven desktop-stage tests,
  package/version/dependency gates, Developer ID signing, notarization, staple,
  Gatekeeper and signing-material cleanup. New dependency cache sealed.
  Operator reports the fix works and accepts it. This is not a claim that every
  display/input combination was individually tested. No Host behavior change.
  Start a fresh fullscreen connection; toggling window mode alone does not
  renegotiate an existing Host resolution.
  Hash-verified DMG (85,582,956 bytes):
  `artifacts/packages/candidates/1.0.119-macos-fullscreen/macos/plank-client_1.0.119-macos-fullscreen_arm64.dmg`.
  SHA256: `58f8d4b56b6f68e3490e5c54b066030525e7ebee074ababcaccba96eaba709c9`.
  Unchanged gitlinks: Linux Host `9329784ac41f50cbec0c9d76badfd22227ec5e5f`,
  Kymux `912ece5c64787997f978673ca60d313898a3548c`; Client common-c
  `b9650552f98d97f6e30c9f007115c6246f0809e5`, qmdnsengine
  `b7a5a9f225d5e14b39f9fd1f905c4f505cf2ee99`.

- Superseded fullscreen evidence: Client 1.0.117 (root `aea1ab33`,
  Client `509f2fc7`, signed run `35124970815`) restored swipes but retained
  side borders; AppKit ignored the requested full-panel content size. The
  standalone 1.0.118 probe (root `21c29544`, signed run `35129303592`) passed
  build/signing and the operator compared all five modes. That probe is NOT
  Client 1.0.118. Its retained diagnostic DMG is under
  `artifacts/diagnostics/1.0.118-macos-fullscreen/macos/`; SHA256
  `8e391cf9c07ed7df9faaad1964f5319626e84a3f521c6527d8bec360600f06a9`.
  Full-panel override experiments are retired. See
  `docs/development/plans/macos-fullscreen.plan` for findings and acceptance gates.

- The operator authorized merging the reconnect follow-up into main after
  manually installing Host 1.0.116. Reconnect implementation root `4173138`
  and Client `e8fc0cc0` extend the previously accepted root `d34a110` / Client
  `060e6424`. The separate worktree (directory still named macos-auth-recovery)
  contains the continuation work; preserve unrelated primary-worktree research.
  Host and Client candidates 1.0.116 retain valid setup authorization across readiness retries,
  stop rejected authentication/TLS/permission failures, and gate new requests
  on the configured Ask/Disconnect deadline. Keep Waiting explicitly resumes.
  Mac Host retains authorized topology/display HTTP503 contexts within their
  unchanged original expiry; cancellation/rejection/failed launch still revoke.
  Linux Host is unchanged. See `docs/development/plans/client-reconnect-lifecycle.plan`.
  Local executable deadline/status checks, 14 reconnect source guards and 22
  CI tests and all five root CTest suites pass. Hosted compile/package gates
  now pass; live recovery acceptance remains pending. Host installation was
  operator-reported, not agent-verified; the agent only transferred and checked
  the package signature/notarization/hash. No release was published. Existing
  branch-qualified artifacts remain candidates; mainline packages require a
  fresh build and must not be relabeled.
  Host run 35074146670 at root f34ca0f passed same-token readiness/recovery
  tests but failed the cancellation gate: a deadline could expire before the
  network queue set its cancellation flag. Explicit monotonic deadline checks
  now revoke that context too; no 1.0.115 package was produced. Initial Client
  runs 35074149761 / 35074153250 were cancelled to include two review fixes:
  restart an authentication conversation paused behind Ask (its challenge can
  expire), and discard a transport completing after the deadline rather than
  keeping it hidden behind the unanswered prompt.
  Run 35074552628 passed the corrected cancellation gate but caught an unused
  synthetic-fixture counter; final Host run below includes that test-only fix.
  The primary worktree's `rk3576-client` research branch and uncommitted notes
  remain untouched. Published mainline remains Host 1.0.106, other products
  1.0.105. Do not select an old candidate paragraph as the current source.

- Current test packages are hash-verified under
  `artifacts/packages/candidates/1.0.116-reconnect-lifecycle/`:

  | Product | Source root | Hosted run | SHA256 |
  | --- | --- | --- | --- |
  | macOS Host PKG (6,611,153 bytes) | `4173138223c1d0b0a57ddac1977255ee6ea92b6a` | 35074853150 | `e443bc305bf3e03e3386378031d1cb40bce0de803bdba41bf77dfaa3c83a7717` |
  | macOS Client DMG (86,380,741 bytes) | `3a99c4489ddf40e6ab1557f88f012f711f7141bc` | 35074420641 | `92531ccd820e178245f91b532e0f4d208ac01ea2600a0d277176be08ebbac1d7` |
  | Ubuntu Client DEB (15,447,236 bytes) | `3a99c4489ddf40e6ab1557f88f012f711f7141bc` | 35074423798 | `e4873cfe03d8760ab4855c13429bd91bfcc7cddf359b0a799e6ea280382b1657` |

  Both roots use Client `e8fc0cc0c1d73d7cb78c81524fc0ee425c24ff05`;
  Linux Host, Kymux and recursive dependency revisions remain unchanged from
  the accepted work. The catalog records per-package source provenance.
  Mac Host passed seven real-TLS synthetic recovery scenarios (including 32
  repeated readiness requests using one authorization, ready-after-retry,
  cancellation and ownership revocation), 29 display cases, 128 permission-
  denial cleanup cycles, native input/audio/installer gates. Mac Client passed
  18 topology, 21 toolbar and seven desktop-stage/reconnect-policy cases.
  Ubuntu passed its desktop-stage/reconnect guards, exact dependencies, private
  FFmpeg, visible version and no-autostart gates. Both Mac packages passed
  Developer ID/notarization/Gatekeeper and signing-keychain cleanup.
  Next operator test: normal login/logout, temporary outage through Ask timeout,
  Keep Waiting followed by recovery, and Disconnect while paused. Definitive
  authentication/TLS/permission rejection must stop, not resubmit credentials.
  Do not induce production account lockouts for a test.

- Previously accepted Mac Client 1.0.114: root
  `ba91a32413b6d94e611bb48a873746e182209fea`, Client
  `060e6424ee9323f02ce53ce4e00e47427c0b6de8`. Signed hosted run 35071410245
  passed 18 topology/request cases and 21 toolbar-logic cases, dependency and
  version gates, signing, notarization, Gatekeeper, and credential cleanup.
  DMG SHA256 `0a986e97a2932b8e94f49ba95172d65f00df44245e13030a45252c97669d326e`.
  Size 86,349,889 bytes; hash-verified and collected under
  `artifacts/packages/candidates/1.0.114-macos-auth-recovery/macos/`.
  Manually installed and accepted by the operator; not installed by the agent.
  Pair with Host 1.0.113; no Host code/protocol change or Linux package required.
  Full-panel fullscreen correction is operator-accepted.

- Candidate 1.0.113 adds Retina-aware Mac Match Client: current logical desktop
  size AND current compositor backing pixels, for example 1710x1107 points at
  3420x2214 pixels. Display preparation is schema 3 with explicit integer 1x/2x
  scale; matching Host/Client builds are required. Manual modes and Linux
  Client Match Client remain 1x; Linux Host/EDID are unchanged. Mixed-scale
  dual displays fail explicitly. Mac Match Client preserves its measured
  fullscreen mode and uses backing-pixel presentation tiles.
  See `docs/development/plans/macos-retina-match-client.plan`.

- Signed Host 1.0.113 passed hosted run 35067335971 at
  `527cd5236e832396b6ed410fde4d9f00b345cefa`. Gates include 29 synthetic
  display/recovery cases, authenticated TLS schema-3 preparation/negative cases,
  real-QUIC no-media setup/teardown, 128 permission-denied setup cleanup cycles,
  129 non-waking activity checks, 216 native-input checks across eight scenarios,
  existing audio/installer tests and signing/notarization. Collected under
  `artifacts/packages/candidates/1.0.113-macos-auth-recovery/macos/`.
  PKG size 6,611,113; SHA256
  `2d40969bb830ae761f2f5581ed3db0f97404a2b3b440f7bf1ec55f465ed7f496`.
  Operator-installed Host/Client 1.0.113 are now observed in supplied logs;
  the subsequent Client 1.0.114 fullscreen correction is operator-accepted.

- Client 1.0.113 source is `ec17fc4`, Client gitlink
  `eb2d5ac1cc00630bd448b16976a15f93443ee15e`.
  Signed Mac run 35067619279 and Ubuntu run 35067622416 passed. The Mac job
  passed all 18 topology/request tests plus dependency/version/signing/notary
  gates; Ubuntu passed dependency, version, private-FFmpeg and autostart gates.
  Both packages are collected under the same version/platform catalog.
  DMG SHA256 `a260b5d42ae87dc8d70a72dec786b461e0381c2a3d2ea09e5721d96bf7ecd4aa`;
  DEB SHA256 `40ac84f2077f12573345283c8d27e42283f32226e29261c7e124a68f4f27b50a`.
  Earlier Client runs 35067338936/35067341704 were deliberately cancelled before
  producing packages to include the fullscreen/presentation correction.
  Host source is unchanged between those two root revisions. Do not rebuild
  or relabel the already-collected Host just to equalize provenance hashes.
  Local CI policy checks (14), bundle permission tests (seven pass/one Mac-only
  skip), Python syntax and shell/diff checks passed. An unsupported local Qt5
  attempt did not compile; no Qt5 compatibility was added. Required Qt6.10.2
  runner tests, not that attempt, are the Client compile gate.

- Secure-unlock fix is included: nine native lock-screen password rejections
  logged `The user did not become active for authentication. Fail the auth`
  after a five-second wait. Separate account verification succeeded; changing
  Shift/Caps did not help. A temporary `caffeinate -u -t 180` changed
  UserIsActive from 0 to 1 and the operator unlocked normally, with native
  `checkAuth result: 1`. The temporary assertion was explicitly stopped.
  Root `8a60ee3` (1.0.112, signed run 35066026592 passed) now reports only
  authorized real input as local console activity, at most once per second,
  with a ten-second OS timeout and immediate teardown release. No permanent
  power setting, TCC change, password logging or synthetic repeat/cleanup wake.
  The permanent implementation is not yet live-qualified.

- Earlier fixes on this branch: abandoned setup-token replacement/cleanup,
  bounded verifier diagnostics and successful-auth cooldown reset; authenticated
  bootstrap wake and bounded topology-settle wait; dynamic exact Mac display
  dimensions. See the auth/media/display recovery plans and Git history.
  Before the operator's upgrade, Host 1.0.111 real authenticated display preparation
  passed 3024x1964, 3456x2234, 2880x1864 and 5120x2160, then restored 1920x1080.
  These are geometry checks, not full streamed acceptance. Client retry
  lifecycle changes are now in the separate 1.0.116 candidate above.

- Supplied Retina screenshot/logs confirm Match Client negotiates and receives
  3420x2214, but a notched laptop's settled fullscreen drawable is 3420x2146
  (logical 1710x1073 instead of 1710x1107). This explains the top strip and
  aspect-preserving side borders; do not change Host Retina negotiation or
  stretch the stream to conceal the mismatch. The accepted correction keeps
  toolbar controls reachable around the camera housing. Candidate 1.0.114 implements SDL
  borderless desktop fullscreen without modesetting/Spaces and dynamically
  places the toolbar beside the camera housing. Hosted build passed and the
  operator accepted the correction. Mac fullscreen now uses the current desktop rather than a
  separate AppKit Space or an exclusive mode; test minimize and teardown too.
  Raw screenshots/logs remain outside Git.

- Next: operator qualification of the separate reconnect candidate. Broad acceptance
  of 1.0.114 is not a claim that every sleep,
  ownership, manual-mode and secure-unlock scenario was tested. Private deployment
  details and captures remain outside Git.

- Exact-input Mac Client dependency/Qt caching is committed as `8730581`;
  22 local CI tests pass. Hosted cold run 35070457888 passed and saved its
  dependency cache; signed Client 1.0.114 run 35071410245 restored the exact same
  key across the application change and independently verified its patch/receipt.
  Dependency bootstrap fell from 6m32s to 19s, plus 29s cache restore. The cold
  run was unsigned and the warm run signed, so their total job durations are
  not like-for-like benchmarks. Application/Rust compilation and all signing/
  notary gates still run fresh. Never cache application
  builds or signing material; `--clean-bootstrap` bypasses restore/save. This
  CI-only follow-up does not change the application version.

## Release evidence

Latest published release is **v1.0.121**, all four products, recorded above.
The merged dependency-cache work extends hosted caches without runtime changes;
qualification runs are separate from the published package source.

Historical Host-only release: [v1.0.106](https://github.com/instinctual/plank/releases/tag/v1.0.106),
mainline source `4b634071d0aa96c5568e90068f5f42b7cd953365`, signed run
35035036281. Catalog `releases/1.0.106/macos/plank-host_1.0.106_arm64.pkg`;
SHA256 `bdb59fb5ddf2df0afb4704920684b83d81c9b8975602e3d643bed5dd1c8d3e49`.
GitHub asset hashes match the local catalog. The other three products retain
1.0.105 below. Feature candidates in Current state do not replace published main.

All four exact-source runs passed:

| Product | GitHub run |
| --- | --- |
| Linux Host RPM | [35018358540](https://github.com/instinctual/plank/actions/runs/35018358540) |
| Linux Client DEB | [35018361548](https://github.com/instinctual/plank/actions/runs/35018361548) |
| Signed macOS Host PKG | [35018364501](https://github.com/instinctual/plank/actions/runs/35018364501) |
| Signed macOS Client DMG | [35018367944](https://github.com/instinctual/plank/actions/runs/35018367944) |

Verified SHA-256 values:

- Host RPM: `7aa4a71077ba22b836738ec53152c966af76555375da1514cc811065f3efb1be`
- Client DEB: `eb4c918e0c5c52fc3d5b0ef0bc16d340a89393971b71c8384f5491be0ec44985`
- Host PKG: `6e99f7509e31a17a097ee56c9f295f267bea5cd5a00dabf09582433646b94f92`
- Client DMG: `e88a62aee26d553d836ed7dbe6266441bf8037fa1623a27c307d4e602ea6fa54`

The collector verified transfers and retained source/gitlinks and sizes.
Local checksum verification passed; GitHub asset digests matched all four
packages, manifest and release checksum file. Published checksums use flat
asset filenames; local catalog checksums use platform subdirectories.
Temporary download/upload staging was removed after verification.

Both Mac packages passed Developer ID signing, notarization, stapling,
Gatekeeper and temporary-keychain cleanup. The Mac Host passed ten synthetic
recovery tests, four real TLS recovery scenarios, eight permission tests and
29 installer checks. Linux Client exact-decoder, private-FFmpeg, dependency,
version, reconnect and no-autostart gates passed. Host RPM manifest and
log-directory gates passed. Linux Host retains BUILD_TESTS=OFF and complete
CUDA architecture coverage. Local CI/version, package-collection, build-path
and bootstrap-input tests passed. These are not hardware acceptance results.

## Accepted fixes

Authenticated macOS topology requests can recover an inactive PLANK-owned
virtual display, with bounded authority/ownership checks and retained real
geometry. No physical mode changes, duplicate displays, TCC mutation or active
stream recovery. See `docs/development/plans/macos-display-recovery.plan`.

Host 1.0.103 had owner-only app directories/resources: ordinary users could see
a prohibited icon or "damaged or incomplete" launch error despite notarization.
Assembly now uses public distribution permissions, independently checked in the
app, staging and final PKG BOM/extraction. Never broaden private keys/state to
repair app access.

The operator accepted candidate 1.0.104-macos-display-recovery; merge commit:
`13e0c3248d223fd63d84919517df092d3e6d41ef`. Candidate source:
`ca36e48123d58cc84104f6fab5df59c35d14f05e`, signed run `35011167754`.
The Host-only mainline 1.0.104 used
`9284c204b6974e322e480442a0b0b91767420d2a`, run `35013030130`.
Those packages remain separately cataloged; 1.0.105 supersedes them.
Broad acceptance does not imply exhaustive sleep/ownership-transition tests.

Linux Host, shared Client and transport dependency revisions are unchanged
from 1.0.103. The corresponding 1.0.105 packages are rebuilds, not renamed files.

## Build and signing policy

Use GitHub-hosted workers for the requested releases, not a local Mac fallback.
All four clean hosted build paths and both signed Mac package paths are
qualified. Local builders have not been retired; hardware test roles remain
separate. Read `docs/development/build/github-builds.md` and the release build
runbook before the next build.

Signing is an explicitly dispatched direct job in `build.yml`, selected with
`signed=true`; ordinary push/PR builds never receive signing credentials.
At the operator's request, `macos-signing` has no reviewers or wait timer.
Custom branch restrictions are `main`, `macos-display-recovery` and the explicit
`macos-media-recovery`, `macos-auth-recovery` and `reconnect-lifecycle` candidates, not a
wildcard. Certificate exports, passwords and notarization credentials remain
environment secrets. Temporary runner keychains are removed on success/failure.

Do not restore the initial reusable-workflow wrapper: it received empty
environment secret values; the direct protected job is qualified. Missing
secrets fail before bootstrap. No per-run human approval is needed.
Exact-input Mac Client dependency caching is qualified as described above;
clean-bootstrap builds remain available to bypass it.

## Maintained inputs (unchanged from 1.0.105 through 1.0.106)

| Maintained input | Package source commit |
| --- | --- |
| Linux Host | `9329784ac41f50cbec0c9d76badfd22227ec5e5f` |
| Shared Client | `c032da3ae0d7e816a7a6f9bb9a51dd489d4d369c` |
| Transport | `912ece5c64787997f978673ca60d313898a3548c` |
| Host common-C | `775943b5ac5e5100a3c2b1b89d9e21151dea4f29` |
| Client common-C | `b9650552f98d97f6e30c9f007115c6246f0809e5` |
| Client mDNS engine | `b7a5a9f225d5e14b39f9fd1f905c4f505cf2ee99` |
| Host build dependencies | `caf0495d5e6baff94f349853d4a59e3779a451a0` |
| Host virtual HID | `93d57db99a5bf4b1a9fbbc7ad1371671725b7e97` |

The local checkout need not initialize every recursive dependency for notes;
builders initialize exact product inputs. Uninitialized local submodules do
not imply missing release dependencies.

## Remaining gates and publication boundaries

Mainline macOS Host 1.0.106 is published, collected and checksum-verified.
Its completed `macos-media-recovery` branch was deleted. The subsequently
accepted authentication, reconnect, fullscreen and dependency-cache work is
merged, and its completed feature branches are deleted. Unrelated local
RK3576 research remains separate.
Volume/mute is operator-validated. Longer app/alert audio, device changes,
sleep/reconnect/topology and login/logout remain follow-up coverage, not
blockers invented beyond the operator's merge approval. Inspect the new audio
reason/overrun/restart logs if it fails.
The initial failure cause is not proven; overflow no longer permanently
disables audio. An offline display that never returns still fails boundedly
rather than forcing settings into WindowServer. Do not interrupt a production
session to install. Acceptance
criteria still apply, including final macOS release revalidation and live
recovery/ownership transitions.

Treat tracked files/messages as public. See `docs/security/private-information.md`
and `docs/security/publication-review.md`. Source audits were bounded, not
proof against unknown/encoded secrets; credential rotation remains the operator's
responsibility. Do not reimport private historical development commits or publish
old 1.0.100/1.0.101 preparation packages: newer build-path fixes do not repair
their metadata retroactively. Never patch signed bytes or relabel packages.

ENet/nanors and inherited transports remain absent from current builds.
Host common-C is header-only; Client common-C is a separate maintained branch.
Preserve attribution without restoring retired code. Private infrastructure,
PLANK2 and historical backups remain independent of the public Host/Client
repository and release. Historical validation detail remains in Git history,
focused documentation and the earlier artifact manifests.
