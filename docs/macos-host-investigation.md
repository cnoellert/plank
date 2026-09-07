# macOS Host investigation and development probes

Date: 2026-09-06. Branch: `macos-host`.

## Scope and stopping point

The user supplied an existing machine-room Mac running PCoIP as a read-only
reference, then requested that all active development/testing wait for a
dedicated development Mac. This investigation is complete within that boundary.
Do not resume remote probes, installs, or service experiments on the reference
Mac without new authorization. No credentials, host/network identity, serials,
private certificates, or raw logs are retained here.

Read-only commands inspected system inventory, installed launchd plists,
package metadata, signed entitlements, imported binary symbols/frameworks,
selected display/encoder log messages, existing authorization mechanism names,
power settings, and installed public SDK headers. Root-only log reads used
sudo. No debugger, screen capture, input injection, TCC database inspection,
permission request, mode switch, logout, restart, install, or configuration
change was performed. SSH/sudo can generate normal operating-system audit
records; this is not a claim of a bit-for-bit unchanged filesystem.

A draft passive CoreGraphics inventory source was written locally before the
read-only clarification. Its pending remote preparation command was cancelled
at the SSH password prompt, before it executed. The source was never uploaded,
compiled, or run. It remains explicitly unvalidated under `probes/macos/` for
the future development machine, outside Linux build and package paths.

## Hardware and toolchain observed

- Mac mini, Mac16,10, Apple M4, 10 CPU cores (4 performance/6 efficiency),
  10 GPU cores, 16 GB RAM, arm64.
- macOS 26.6.2, build 25G83.
- Xcode 26.6, build 17F113; selected developer directory
  `/Applications/Xcode.app/Contents/Developer`.
- `xcrun --show-sdk-version` reports macOS SDK 26.5. Installed DriverKit SDK
  directory includes 25.5. Do not equate OS, Xcode, and SDK version numbers.
- FileVault Off; SIP enabled; authenticated root enabled.
- Existing AC settings include computer sleep disabled, display sleep after
  ten minutes, and restart after power failure disabled. No settings changed.
  Blank-display versus machine-sleep recovery needs later qualification.
- PCoIP/Anyware Graphics Agent 26.05.3 is installed and a desktop session is
  active. No PLANK capture/encode performance was tested on this machine.

## Headless display: direct evidence

The active display reports `Built-in Reti`, 1708x1072 at 60 Hz. The name alone
was initially ambiguous; the current PCoIP server log resolves that ambiguity:

1. It reports a default system virtual display active before session setup.
2. It creates its own virtual display named `Built-in Reti`, with a configured
   maximum pixel size of 4096x4096 and physical dimensions of 641x401 mm.
3. It adds an initial mode of 1708x1072 at 60 Hz.
4. That display becomes primary and is identified as `Anyware Virtual Display 1`.

The observed desktop is therefore a PCoIP-created software display. This is
not a physical monitor EDID being renamed. The configured 4096x4096 maximum
belongs to this observed descriptor, not a demonstrated Apple hardware limit.
No experiment established display lifetime after disconnect, behavior before
boot-time login, or the geometry/capturability of the default system display.

The executable imports `CGVirtualDisplay`, `CGVirtualDisplayDescriptor`,
`CGVirtualDisplayMode`, and `CGVirtualDisplaySettings`, plus public CoreGraphics
display-mode/configuration functions and `CGSConfigureDisplayEnabled`.
The selected public CoreGraphics headers contain no `CGVirtualDisplay`
declarations. The inspected IOKit graphics headers and DriverKit filename
inventory did not reveal a supported equivalent display-creation interface.

Conclusion: PCoIP demonstrates that software headless displays are possible,
but does not prove a public, supported API is available to PLANK. Imported
symbols plus explicit creation logs strongly associate its implementation with
the CGVirtualDisplay family; no disassembly or proprietary source copying was
performed. Do not claim we have reproduced or fully understood its internals.

The future decision gate is whether a documented solution meets the headless
requirement independently, or whether an isolated undocumented-API dependency
or hardware alternative needs explicit discussion. Do not silently adopt a
private API, promise a DriverKit display driver, or require a dummy dongle.

### User-provided header reference

The user supplied [CGVirtualDisplay.h from w0lfschild/macOS_headers](https://github.com/w0lfschild/macOS_headers/blob/master/macOS/Frameworks/CoreGraphics/1336/CGVirtualDisplay.h).
It is a class-dump declaration, not an Apple SDK contract. It exposes
descriptor-based creation, settings application, display ID, modes, HiDPI,
dimensions, and color primaries. Its unknown block-type placeholder and
untyped method arguments require validation, not blind inclusion in PLANK.
The class name matches PCoIP's imports. This is a concrete future experiment
reference, not proof of current ABI compatibility, permissions, or LoginWindow
operation. No header was vendored and no API was invoked.

### Concrete implementation reference

Also reviewed [node-mac-virtual-display's Objective-C++ implementation](https://github.com/enfp-dev-studio/node-mac-virtual-display/blob/main/src/virtual_display.mm).
Useful references: descriptor/mode creation, HiDPI backing dimensions, actual
mode queries, and idempotent object cleanup. Do not adopt its Node wrapper,
physical-main enforcement, vendor-based physical-display heuristic, or fallback
that labels requested dimensions as actual before activation. Replacement
releases the old display before proving the new one works; PLANK needs explicit
failure recovery. LoginWindow and crash recovery remain unqualified. No code
was copied. If adapted later, preserve its [MIT notice](https://github.com/enfp-dev-studio/node-mac-virtual-display/blob/main/LICENSE).

### HiDPI and lifecycle reference

The user clarified that all supplied projects are learning references, not
instructions to copy their implementations. Reviewed
[pasky/hidpi-mirror](https://github.com/pasky/hidpi-mirror), its Objective-C
source, and its Aqua-only LaunchAgent. The author reports mode-ordering,
HiDPI mode-list synthesis, and persisted vendor/product preferences affecting
results on macOS 26. Treat those as test hypotheses, not universal API rules.

Useful future tests: confirm logical and backing dimensions after activation;
recreate with existing display preferences; exercise process lifetime and
run-loop-delivered display callbacks. Compare the supplied projects' differing
HiDPI mode-list strategies empirically. No constant 2x input transform.

Its physical-panel mirroring/downsampling, fixed descriptor values, permanent
configuration fallback, and periodic repair loop are not our headless design.
Its Aqua-only launch configuration does not prove LoginWindow operation.
PLANK should capture the selected virtual framebuffer directly, explicitly
validate readiness, and preserve the administrator's display configuration.
No source was copied, installed, or executed.

## Session and authentication architecture

Installed configuration and live process identities show:

| Component | Context/identity | Evidence |
| --- | --- | --- |
| PCoIP agent | `_pcoip` service account | LaunchDaemon UserName/GroupName and process owner |
| PCoIP session manager | `_pcoip` service account | LaunchDaemon plus multiple named Mach IPC services |
| PCoIP user agent | Interactive graphical session | LaunchAgent limited to both Aqua and LoginWindow, KeepAlive enabled |
| PCoIP media server | Logged-in desktop user | Child of the graphical user agent |
| Recovery helper | Privileged launchd helper | Separate Mach service, no non-root UserName in plist |

The current process snapshot proves only the active user-session identities,
not the identity or success of a PLANK pre-login agent. The user-agent binary
imports NSXPC classes and OpenDirectory's ODNode.

PCoIP also installs authorization plugins in
`/Library/Security/SecurityAgentPlugins/`. A read-only
`security authorizationdb read system.login.console` confirms its mechanisms
interspersed with Apple's normal sequence: load, loginWindow, loginStart,
and loginDone. A separate lock-screen plugin is installed; its presence alone
does not establish the exact active unlock flow.

This is more integration than a LaunchDaemon calling screen capture. PLANK
should begin with authenticated remote access to the normal login UI, then
measure whether additional login integration is genuinely needed. Do not copy
PCoIP's authorization database modifications as a starting point. Preserve
active-user ownership and distinguish PLANK authentication from OS login.

Apple DTS independently describes a network daemon plus graphical capture/input
agent connected by IPC, with Aqua and LoginWindow session contexts. DTS reports
having prototyped ScreenCaptureKit in pre-login on macOS 14.4 and later. This
supports our architecture, not PLANK's permission provisioning or headless
display implementation. See [Apple DTS's explanation](https://developer.apple.com/forums/thread/814152).

## Capture and encoder evidence

The PCoIP server imports CGDisplayStream capture APIs, VideoToolbox compression,
CoreVideo/IOSurface, Metal/MetalKit, and CoreGraphics. ScreenCaptureKit is not
in the inspected direct dependency list. This does not exclude dynamic loading
or another capture backend; it is not proof of every runtime path.

Its current log twice reports VideoToolbox hardware support for H.264 High
Level 5.2. That is a capability/probe message, not proof that every currently
transmitted frame uses that encoder, nor evidence of HEVC Main10 qualification.
Existing PCoIP policy includes Ultra value 3, link-rate value 135000, and
bandwidth-floor value 95000. These are reference settings, not proposed PLANK
defaults. A one-time CPU sample was not retained as a performance benchmark.

Public installed `ScreenCaptureKit.framework/Headers/SCStream.h` provides:

- IOSurface-backed screen sample buffers and independent audio output.
- Configurable output width/height and frame interval.
- BGRA, packed 10-bit RGB (`l10r`), 8-bit video/full-range 4:2:0, 10-bit
  full-range 4:4:4 (`xf44`), and half-float RGBA in its documented format list.
- Cursor inclusion control; capture source rectangle in logical points versus
  destination rectangle in pixels. This distinction must be explicit in input
  and presentation geometry.
- Queue depth default of eight in this SDK's header. This is capacity, not a
  claim of eight mandatory frames of latency. Retain surfaces briefly and
  qualify a small bounded depth rather than blindly increasing it.
- System audio capture, with documented defaults of 48 kHz and two channels.
- Separate frame statuses for complete, idle, blank, suspended, started, and
  stopped. Idle means the display did not change, not connection failure.

The documented list does not include 10-bit 4:2:0 (`x420`) as a direct capture
output. Do not assume an arbitrary CoreVideo format works in ScreenCaptureKit.
Qualify whether the desired 10-bit encoder input needs a Metal conversion from
an accepted high-precision capture surface or a supported VideoToolbox path.
No extra CPU round trip is justified merely by a format mismatch.

Public `VideoToolbox.framework/Headers/VTCompressionProperties.h` exposes
hardware-required selection, actual-hardware reporting, real-time operation,
frame-reordering/delay controls, average bitrate, rate limits, Main10 profile,
and optional low-latency rate control. These properties need per-codec runtime
support queries and real encode tests. Low-latency rate control has specific
GOP/profile/temporal-layer semantics; do not assume it is interchangeable with
RealTime or equally supported for H.264 and HEVC Main10.

Static desktop capture is an integration risk worth testing explicitly: an
idle ScreenCaptureKit stream must not trip PLANK's video-silence/reconnect
logic. Select a bounded repeat-frame strategy or an explicitly negotiated
idle/health contract only after inspecting and testing the current receiver.
This investigation did not change any receiver timeout or transport policy.

## Input, cursor, audio, and entitlements

The PCoIP server has the signed `com.apple.developer.hid.virtual.device`
entitlement and imports IOHIDUserDevice functions. IORegistry shows its virtual
keyboard. This establishes a virtual HID input path exists; it does not prove
which mouse/keyboard events use HID versus CGEvent at runtime.

The same executable imports CGEvent mouse/keyboard/scroll operations, event
taps, NSCursor, and capture cursor inclusion controls. A reliable separate
custom-cursor shape path for PLANK remains unproven. Do not infer it solely
from these imported names.

The inspected server and helper entitlement lists did not show the persistent
content-capture entitlement. The helper permits disabled library validation
and declares a private keychain group. Do not copy these grants, assume they
are required, or infer PLANK can avoid TCC permissions from their absence.

PCoIP installs its own HAL audio plugin, active inside Core Audio. Other
third-party audio/driver components are present on this reference Mac, so it
is not a pristine qualification image. PLANK should first qualify
ScreenCaptureKit audio rather than automatically writing a HAL driver.

## What remains unproven

- Independent headless display provisioning with approved API boundaries.
- LoginWindow capture/input with a fresh PLANK identity and real provisioning.
- Actual Apple hardware encode/decode support, precision, quality, copy count,
  latency, throughput, and A/V synchronization for each proposed profile.
- Custom cursor extraction and accurate input with Retina/headless geometry.
- Login/logout, lock/unlock, abrupt agent exit, display sleep, reconnect,
  takeover, and operation without any PCoIP components.
- Permission persistence after installation, upgrade, logout, and reboot.

These require the dedicated development Mac and later operator-assisted tests.
Do not replace them with capability strings or run them on the reference Mac.

## Next session

Wait for the user to provide the dedicated development Mac. Read this report,
`macos-host.plan`, and HANDOFF.md first. Resolve headless API policy, establish
an independent recovery path, and pin the new Mac's actual SDK/toolchain.
Then compile and validate the passive probe before any capture/input test.
No current capture, trace, loss injection, or probe process needs stopping.

Session closed out on 2026-09-06 at the user's request. The SSH control
connection was closed. All three supplied virtual-display references were
reviewed and their lessons recorded above, without vendoring or executing
them. Further progress now requires the dedicated development Mac, not more
unattended investigation of the production reference system.

### Dedicated development Mac readiness (subsequent update)

On 2026-09-06 the user supplied a separate M4/16 GB development Mac running
macOS 27.0 (26A5425a). After user preparation, read-only checks confirmed
FileVault Off, SIP enabled, selected Xcode 27.0 (27A5252f), SDK 27.0, and
first-launch readiness exit 0. SSH-key access works. Initial SSH display inventory
was empty. The hardware wait above is now
resolved; restrictions on the reference Mac remain unchanged. Treat macOS
26.6.2 and 27.0 as separate qualification targets.

## Active dedicated-Mac probes (2026-09-06)

The user subsequently authorized active development on the dedicated Mac.
Reference-machine read-only restrictions remain in force. All source is original
probe code; none of the user-supplied reference implementations was copied.
Root branch remains macos-host from e451f24; Linux runtime/gitlinks unchanged.

### Headless graphical context and display lifecycle

- Five standalone Objective-C sources built against SDK 27.0 using clang with
  ARC and `-Wall -Wextra -Werror`. No third-party dependency installed.
- SSH launched in the Background session: public display list empty and capture/
  input preflights false. A private display object obtained there did not yield
  queryable graphics geometry. This did not qualify the display path.
- `launchctl print loginwindow` (root) identifies the actual LoginWindow domain.
  Its printed name includes a PID, but appending that PID to the command targets
  a service, not the domain. The temporary runner uses the bare domain.
- Root-owned temporary one-shot agent, no KeepAlive, no persistent plist:
  graphical inventory saw an active 1920x1080@60 main display. Creation provenance
  of that baseline display is not established by enumeration alone.
- Lifecycle probe created its own distinct display ID, measured active/online
  1920x1080 backing pixels at 60.000 Hz for ten samples, released the object, then
  confirmed its ID absent from successful public enumeration. Exit 0.
- Runtime signatures are checked before private calls. In particular, this
  runtime's virtual-mode width/height arguments are unsigned 32-bit values, not
  the NSUInteger declarations used in one reference implementation.
- These are isolated private-API feasibility results, not a public support
  contract. Retina, multiple displays, alternate modes, and login transitions
  remain untested. Do not infer supported production modes from a single test.

### ScreenCaptureKit permission gate

The bounded ScreenCaptureKit probe failed to enumerate shareable content in
LoginWindow with SCStreamErrorDomain -3801 (permission denied). Capture/input
preflight returned false. It failed both as a standalone executable and as the
installed ad-hoc-signed app; root execution did not grant permission.

`/Applications/PLANK Host Probe.app` is installed, root-owned, bundle ID
`la.instinctual.PLANK.Host.Probe`, signature verified. Its explicit
`--request-permissions` mode asks macOS for Screen Recording and event-posting
access, presents setup instructions, and injects no input. The operator must
run this mode in a logged-in GUI session and grant access in System Settings.
Built-in Screen Sharing is already running. No TCC database modification,
SIP change, authorization-plugin installation, or automatic login was used.

Next: verify capture after consent in Aqua, then LoginWindow, including identity
and permission persistence across logout. Ad-hoc signing is development-only;
release Developer ID/notarization/permission provisioning remains undecided.
No successful screen capture, saved pixels, audio capture, or input injection
is claimed. A metadata-only complete-frame check will still not prove correct
visible login-screen contents; operator visual confirmation remains a gate.

### VideoToolbox hardware encoding (independent of capture)

Synthetic immutable IOSurface-backed video-range grayscale ramps, 40 frames per
case, hardware required and actual hardware-use property checked. RealTime on,
frame reordering off, 60-fps timestamps, BT.709 tags. One frame in flight,
first ten omitted from timing. No ScreenCaptureKit input or Metal conversion.

| Case | Mean callback time | P95 | Max |
| --- | ---: | ---: | ---: |
| H.264 High 8-bit 4:2:0, 1920x1080 | 4.475 ms | 4.685 ms | 4.737 ms |
| HEVC Main 10 10-bit 4:2:0, 1920x1080 | 5.045 ms | 5.335 ms | 5.385 ms |
| H.264 High 8-bit 4:2:0, 3840x2160 | 16.153 ms | 16.316 ms | 16.434 ms |
| HEVC Main 10 10-bit 4:2:0, 3840x2160 | 10.402 ms | 10.633 ms | 10.661 ms |

All cases passed. Generated synthetic Annex B streams were inspected and fully
decoded by the retained private FFmpeg 9.0.1 on linux-client-builder. Each had 40 readable
frames; H.264 High/yuv420p or HEVC Main 10/yuv420p10le as requested, exact
dimensions, no B frames, video range, BT.709 matrix/transfer/primaries. No
package installation/build or dependency modification was required on that VM.

These short serial static-ramp tests do not establish 60-fps moving-footage
performance, visual fidelity, glass-to-glass latency, energy use, or soak
stability. They do not qualify the separate LowLatencyRateControl mode.
The video-range test choice is not a new Linux profile or final macOS range
policy. Actual capture-to-encoder conversion/range fidelity remains to test.

### Cleanup and resume

All temporary agents were unregistered and their root staging directories
removed. Privileged SSH shell closed; no probe remains running. The development
app and temporary probe compiler outputs remain for the next permission test;
paths are in HANDOFF.md. No persistent Host service, network listener, package,
version change, push, merge, or tag was created. Current plan/probes/notes are
saved locally, uncommitted. Source transfer hashes matched on the Mac.

### Operator-consent follow-up

User reported completing the permission step. Same installed app, no binary
replacement or signing change:

- `open -n -W -a "PLANK Host Probe"` from SSH launched through LaunchServices
  into the active Aqua desktop. Capture preflight=1, input preflight=0. Ten
  complete 1920x1080 BGRA IOSurface-backed frames, 16.667 ms PTS spacing,
  clean capture stop and result=0. No screenshots were written.
- Repeated as a one-shot LaunchAgent in `gui/UID`, same executable inside the
  installed app bundle: same capture/permission result, launchd exit code 0.
  This validates the graphical-agent context, not just an interactive launch.
- The separate virtual-display lifecycle binary also passed in Aqua: measured
  1080p60 for ten samples, then verified its display ID disappeared after release.
  The capture runs selected the main display, not specifically the temporary
  lifecycle display; combined owned-display capture remains to test.
- Initial `launchctl asuser` as the non-root SSH user failed switching audit
  sessions. Do not treat that launch error as capture failure. Ordinary `open`
  through LaunchServices and direct `launchctl bootstrap gui/UID` work here.

The runner is now `run-graphical-probe.sh`: explicit LoginWindow/root or
Aqua/current-user domain, per-invocation private staging, bounded wait and
unregistration. All registrations were removed after the completed checks.
The installed app still has its original ad-hoc signature and bundle ID.
The user was asked to check Accessibility specifically because fresh processes
continue reporting input preflight=0. No input was posted. Desktop is left
logged in for that check; logout is the next operator step before repeating
LoginWindow capture after consent. No automatic logout/reboot was performed.

### macOS 27 privacy-pane naming correction

The operator could not find Accessibility under Privacy & Security. Inspection
of the installed SecurityPrivacyExtension's Localizable.loctable resolved the
discrepancy: `en.ACCESSIBILITY` is **Device Control and Data Access** on build
26A5425a. The service remains TCCServiceAccessibility and its reveal key remains
Privacy_Accessibility. The deep link opened successfully; actual visible
navigation/approval is left to the operator. Do not infer this renaming from
the unrelated macOS 27 MDM/PPPC deprecation. The published older Accessibility
instructions and the probe's existing setup text are outdated for this beta.
The installed app binary was not replaced, so this correction does not reset
its current capture consent identity.

### Native consent request and macOS 27 baseline

At the user's request, probe build 2 replaces the instructions-only alert with
a modeless permission window. It calls the public
`AXIsProcessTrustedWithOptions` / `kAXTrustedCheckOptionPrompt` API once on
normal launch. Apple documents this prompt as asynchronous, not an immediate
grant; a false return is not proof that the request failed. A status timer
never re-prompts. Separate buttons request recording, request control, open
the verified permission pane, or quit. Setup never captures or posts events.
Capture now requires `--capture`. Unknown arguments fail with exit 2.

User explicitly selected macOS 27 as the minimum supported platform. All five
probes rebuilt with -Werror and deployment target 27.0, SDK/OS checks require
27+, and the bundle minimum is 27.0. Mach-O LC_BUILD_VERSION independently
reports minos 27.0 and sdk 27.0. No older-OS UI fallback is retained. The older
reference Mac remains research-only. Final OS release testing remains required.

Installed build 2 at the same application path, verified ad-hoc signature,
preserved build 1 in a root-private backup, and opened setup through LaunchServices.
The log confirms `device_control_request_issued=1 trusted_now=0`; the user must
confirm the visible prompt and approve it. No TCC changes or privilege bypass.
Because the ad-hoc binary changed, recheck prior capture consent before further
tests. No assertion that consent persisted or that input now works is made.
Official prompt API: https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions

### Build-2 permission verification

After operator approval, setup logged trusted_now=1. A fresh Aqua LaunchAgent
capture run independently reported input_preflight=1, but capture_preflight=0
and ScreenCaptureKit -3801. Thus device-control approval worked; build-1
capture consent is not sufficient for this updated ad-hoc binary. No input
events were posted. The agent exited 2 and was unregistered. Reopened setup
and asked the user to click Request Recording; desktop remains logged in.
Do not proceed to logout until both permissions are checked in a fresh process.

### Stale Screen Recording identity confirmed and reset

Operator toggled the visible Screen Recording entry off/on, but both a fresh
Aqua agent and LaunchServices `--capture` run remained denied. TCC diagnostics
explicitly reported failure to match the existing ScreenCapture code requirement:
stored cdhash `1a45573981dc12f20017b2f1a6b9a78d20e0eb75`, installed designated
requirement `2f83fd65a1b94898ac3a1ea5b6e5f8f976707a62`, status -67050.
Device-control checks matched the new requirement successfully. Thus the UI's
enabled entry did not authorize the current ad-hoc build; this was not merely
the probe's cached boolean or a capture-context failure.

Used Apple's installed `tccutil reset ScreenCapture la.instinctual.PLANK.Host.Probe`,
which reported success. Only that bundle's recording consent was reset; device
control and unrelated apps were untouched. No direct TCC database modification,
TCC daemon restart, or SIP change. Restarted the known probe setup process and
opened the Screen Recording pane. The user must now request/approve recording
again before a fresh-process verification. No app rebuild accompanied this repair.
Stable certificate-backed development signing should be established before
further repeated rebuilds to avoid recurring hash-bound consent churn.
After operator reapproval, the unchanged build-2 app passed a fresh Aqua agent
test: capture_preflight=1, input_preflight=1, ten complete 1920x1080 BGRA
IOSurface frames, one idle callback, clean stop and launchd exit 0. This confirms
the targeted consent repair. The observed PTS gap accompanying idle is not a
throughput/drop measurement. Actual input injection and LoginWindow capture
remain untested; operator logout is the next step.

### Post-logout LoginWindow capture passed

After explicit operator logout, console ownership returned to root and a new
root loginwindow process existed. Ran the unchanged build-2 app through the
temporary LoginWindow agent: capture_preflight=1, input_preflight=1, ten complete
1920x1080 BGRA IOSurface-backed frames, two idle callbacks, clean stop and exit 0.
The agent was unregistered and its temporary files removed; SSH closed. No
probe remains running and the dedicated Mac remains at LoginWindow.

This proves basic capture delivery and consent persistence through this logout.
It does not yet prove continuous session handoff, actual login-screen pixel
contents, custom cursors, injected input, owned-virtual-display capture, or
long-session stability. No screenshots or input events were produced.

At that checkpoint, `security find-identity -v -p codesigning` reported zero
valid identities. The next decision was stable development signing before more
rebuilds, avoiding the demonstrated ad-hoc code-hash/consent churn. No new
certificate, private key, keychain trust, or signing-account configuration was
created. Linux runtime and submodules remain unchanged.

### Apple Development signing established

The operator created an Apple Development certificate/private key in Xcode.
Initially one matching identity existed but none was valid: the required WWDR
G3 intermediate was missing. Downloaded the public intermediate from Apple's
PKI endpoint, verified the leaf/intermediate against the existing Apple root,
and installed it as an ordinary certificate in the user's login keychain.
No Always Trust override, root installation, private-key export, or SIP change.
The keychain then reported one valid signing identity. Codesign over SSH also
required interactive keychain unlock in the same SSH session; an earlier
session's unlock did not suffice. A disposable executable was signed, verified
and run successfully before building the application.

`build-probes.sh` now requires an explicit valid certificate SHA-1 through
`PLANK_MACOS_SIGNING_IDENTITY`, without ad-hoc fallback. All five probes built
with warnings as errors; the installed app passed strict signature verification.
Its designated requirement is certificate-backed rather than bound to an
ad-hoc executable hash. This is development signing, not Developer ID
distribution/notarization. Identity values and private keys are not repository
inputs. See `probes/macos/README.md` for reproducible preflight instructions.

Installed root-owned app executable SHA-256:
`aa25577bce41cd067b94e037abc7ca75778bc188ca1ed1069b0ed84dc90bc9e7`.
The capture/setup implementation is unchanged; signing identity changed.
A fresh Aqua test reported capture/input preflight=0, SCK error -3801 and exit
2, confirming old ad-hoc grants did not authorize the replacement. Reset only
this bundle's ScreenCapture and Accessibility grants using supported `tccutil`
commands, then opened its native permission setup. Operator reapproval is now
required. Next validate fresh-process permissions, a same-certificate rebuild,
and logout persistence; the earlier ad-hoc capture results do not satisfy these
new signing gates. No actual input injection or captured-image storage occurred.

### Same-certificate application update preserves desktop consent

After operator approval, signed build 2 passed a fresh Aqua test: both preflight
checks=1, ten complete 1080p BGRA IOSurface frames, one idle callback and exit 0.
Then incremented CFBundleVersion to 3 and added the build number to capture
diagnostics, ensuring a real executable/bundle change rather than merely
reinstalling identical bytes. Rebuilt with the same Apple Development identity,
verified the signature, retained a recoverable prior app and installed build 3.
The designated requirement stayed the same while the code hash changed from
`6bc6a007a2f3d3ca77e85bb0f2e0ecc10ca7957e` to
`ffff077c0b0c5916d96110de55cb9c9d0c0bc207`.

Fresh Aqua output: probe_build=3, capture_preflight=1, input_preflight=1,
ten complete 1920x1080 BGRA IOSurface frames, zero idle callbacks, clean stop
and exit 0. No additional consent or TCC reset accompanied the update.
Installed executable SHA-256:
`747ef2ff8a34ba29f596056fd01e0d4d6d4be822ad9b3eed1f47c2e20f4aed31`.
This establishes consent persistence for this same-certificate app update;
it does not establish renewal/team-change behavior or distribution readiness.
All probes and temporary agents stopped. Await operator logout to qualify
LoginWindow with the certificate-signed build; actual input is still untested.

### Certificate-signed build 3 passes post-logout LoginWindow

Operator logged out. Confirmed root console ownership and a new root
loginwindow process; the installed executable hash and strict signature
verification still matched build 3. Ran it through the bounded temporary
LoginWindow agent without changing the app or requesting/resetting permissions.
Output: probe_build=3, capture_preflight=1, input_preflight=1, ten complete
1920x1080 BGRA IOSurface frames, two idle callbacks, clean stop and exit 0.
The runner removed its temporary agent/staging and the SSH session closed.
No probe remains running; the development Mac remains at LoginWindow.

This verifies capture delivery and permission persistence after both a
same-certificate app update and logout on the current macOS 27 beta. It does
not yet verify actual input delivery, visible login-screen pixel content,
continuous handoff, cold-boot persistence or production signing/notarization.
Next qualification work is actual keyboard/mouse input and owned-display
capture, then the shared-buffer capture-to-VideoToolbox path.

### Owned virtual-display capture passed; input needs desktop comparison

Shared the existing runtime-checked private-display helper between the standalone
lifecycle test and signed capture app, without introducing another implementation.
The new `--capture-virtual` mode captures only the newly created display ID;
dimension mismatch or missing ID fails instead of falling back to another screen.
Build 4 passed at LoginWindow. Final installed build 7 repeated the test:
actual 1920x1080@60, ten complete BGRA IOSurface frames, zero idle callbacks,
clean stop, owned display removal confirmed and exit 0. Both permission checks
remained allowed through these same-certificate app updates. This proves frame
delivery, not visible login-screen contents or end-to-end color/performance.

Added a bounded `--input` receiver window that counts only probe-tagged AppKit
events and requires owned key-window focus before posting. No user key contents
are logged. Initial LoginWindow execution found current-event creation working
but private event-source creation returning NULL. A follow-up explicitly tested
the three documented states: private unavailable, combined-session and HID
available. With an explicitly selected HID source, the receiver window could
not acquire focus (active=0, key=0), so the probe exited 6 without posting.
This safety refusal is not evidence that the login UI cannot receive input.

A separate `--pointer` mode avoids focus changes and posts only motion to two
positions derived from actual display bounds, then restores the original
position. It stalled before the first event was posted. The 40-second runner
terminated it and removed its temporary agent. A repeat with one-second
process sampling found the main thread waiting inside:

```
CGEventCreateMouseEvent / SLEventCreateMouseEvent
  SLEventCreate
    CGSEventSourceForID
      CGSEventSourceShutdown
        std::mutex::lock / __psynch_mutexwait
```

No input was delivered by these runs; no credential entry or login attempt.
Do not interpret this as a proven OS-wide bug, permission denial, or lack of
LoginWindow support. The same public API/source choices need comparison in Aqua
after operator login. Public API reference: Apple's
[CGEventSourceCreate](https://developer.apple.com/documentation/coregraphics/cgeventsource/init(stateid:)).
The installed SDK's CGEventSource.h documents private, combined-session and
HID-system source semantics; no private input API was introduced.

Current signed app build 7 executable SHA-256:
`457b5df1ad86de5cf3a6e7688da78f113eb7078032b40e279445de177410b799`.
All six Objective-C sources compile with warnings treated as errors; strict
codesign verification and plist/shell checks pass. These are probe builds only,
not Host release packages. All temporary agents stopped; recovery access and
Linux runtime remain unchanged. The operator needs to log in for the next test.

### Aqua comparison: actual input and owned-display capture passed

After operator login, confirmed desktop ownership and the unchanged build-7
signature/hash. Its motion-only test passed both positions and restoration.
All three Quartz source types initialized successfully in Aqua, unlike the
private-source failure seen at LoginWindow. Its receiver window did not gain
focus via either a temporary agent or normal LaunchServices opening, so the
safety gate stopped those tests without posting keys/buttons.

Build 8 removed the probe's premature manual `finishLaunching` call and used
the explicit activation sequence already working in permission setup. No
event-injection API, permissions or TCC settings changed. The bounded Aqua
agent test then delivered all nine tagged events into the probe's NSView:
move, left down/drag/up, right down/up, scroll, key down/up. Received mask
511/511, absolute position verified, result/exit 0. This is actual global
Quartz-to-AppKit delivery, not direct method calls to the view or a permission
preflight. No user keystrokes, credentials or login controls were involved.

The same build also captured its newly created 1080p60 display in Aqua:
ten complete BGRA IOSurface frames, zero idle callbacks, exact owned ID,
clean stop, display removal confirmed and exit 0. A following pointer-only
run again verified both positions and restoration. Temporary agents stopped.
The development Mac remains at the desktop. Signed executable SHA-256:
`ddeaa5057e1c2fbad51e578b0a9ef9790f5189b3144a4925886c69a84e29ad8c`.

Next: operator logout, repeat the corrected build's LoginWindow tests.
The prior capture successes stand; the earlier focus refusal is not a valid
conclusion about LoginWindow input. The separately sampled event-construction
stall still requires isolation. No product integration or Linux change yet.

### LoginWindow retest and event-source isolation

After another operator logout, the corrected build-8 receiver still reported
active=0/key=0 and safely refused to post keys or buttons. Its successful Aqua
test therefore does not qualify a LoginWindow receiver window.

Verified the temporary probe and actual loginwindow process share the same
audit session with `has_graphic_access,has_tty`; the target launchd domain is
LoginWindow, not System or SSH Background. No new audit session is created.
This rules out that specific launch-context mismatch, not every WindowServer
or security restriction.

Build 9 added an explicit combined-session-source comparison. Its source ID
was 0 as requested; event construction and posting returned normally, but
observed cursor positions did not match either target. The original position
still matched at the restoration step. A HID-source control (actual ID 1)
again timed out under the 40-second watchdog.

Build 10 tested the combined-session source at `kCGSessionEventTap` rather
than `kCGHIDEventTap`: again, neither target matched, restoration read matched,
and the probe exited 5 without a stall. These are explicit probe experiments,
not automatic product fallbacks. Existing desktop-qualified HID posting is
unchanged. Public Apple APIs only; no TCC, SIP or login security modification.

Current signed executable SHA-256:
`8f23ca57278cd908933e8ef2bae874a56d02a3bc4ba67d2ef9125a254f837c71`.
Next: operator-visible cursor check at LoginWindow. `CGEventCreate(NULL)` plus
location readback is the current measurement; independent visual observation
is needed before equating mismatch with absent movement. Login-screen input
remains unqualified. No credential entry or click on login controls occurred.

### Pre-login declaration resolves construction stall; visible delivery unverified

The operator watched five repetitions of build 10 and saw no movement. That
confirms its failed coordinate checks were not merely misleading readback.
Before replacing the public input path, inspected Apple's own build settings:
[IOHIDFamily at commit 777ccd9698845aadf711e32d843c8c9b777431d9](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDFamily.xcodeproj/project.pbxproj).
Apple's hidd and test targets include the linker section declaration
`-sectcreate __CGPreLoginApp __cgpreloginapp /dev/null`. Our executable lacked
it. This is a Mach-O marker, not an Info.plist key, entitlement or permission.

Build 11 added that exact marker and incremented the probe version; it did not
change event sources, posting entry points, signing identity, TCC, SIP or OS
authentication policy. The original HID-source/HID-entry-point `--pointer`
immediately passed both requested coordinates and restoration, exit 0, with no
event-construction stall. Private-source creation now succeeded as well. This
strongly implicates the missing pre-login executable declaration in the earlier
failure; it is not proof of an OS-wide Quartz bug. The build script now verifies
the section/segment before signing. Build-11 executable SHA-256:
`f902c6a0cc4f25b521975a0cf39cd4f3a695119996c4bfbadc5d30078f3868ef`.

The own-window `--input` probe still could not acquire active/key focus and
refused all clicks and keys. Build 12 added the public
[`canBecomeVisibleWithoutLogin`](https://developer.apple.com/documentation/appkit/nswindow/canbecomevisiblewithoutlogin?language=objc)
window opt-in; the same guard still refused (active=0/key=0, exit 6).
Apple's archived [PreLoginAgents sample](https://developer.apple.com/library/archive/samplecode/PreLoginAgents/Introduction/Intro.html)
uses a nonactivating panel and special ordering. Its 2014 sample is conceptual
reference only, not a macOS 27 qualification or source copied into PLANK.
Do not confuse this test-window focus limitation with input rejection by the
actual LoginWindow controls. Do not remove the guard to force a passing test.

Installed build 12 executable SHA-256:
`8670b5e847a28cfd18e9b85f599dcbc71e712a2e169091744f7cdb359afb3296`.
A repeat LoginWindow HID pointer run passed both target coordinates and
restoration. Owned-display capture also passed: actual 1920x1080@60, exact
created display ID, ten complete BGRA IOSurface frames, 32 idle callbacks,
result 0, display removal confirmed. The static-screen callback intervals do
not qualify 60fps throughput. Images were not saved or visually analyzed.

Next coordinate operator-visible input testing against the real login screen,
without submitting credentials or a login attempt. Actual login-screen
keyboard/buttons, handoff, cold boot and final-OS revalidation remain open.
All temporary probes/agents stopped, no persistent service installed, Mac
logged out, Linux unchanged. New work remains locally saved, uncommitted.

**Subsequent operator test contradicts visible-delivery inference:** build 12
ran five times while the operator watched. All 15 position readbacks passed,
but the operator reported no visible cursor motion. These checks therefore
cannot qualify the visible cursor. The marker removed the construction stall;
it has not established working input at the actual login UI. No clicks or keys
were sent. A subsequent bounded LoginWindow inventory found one active main
1920x1080@60 display, origin (0,0); Screen Sharing was running. Observation
method (physical display versus Screen Sharing) is the next clarification.
Do not treat that server process alone as proof of a viewer-cursor issue.

### Cursor uncertainty deferred; live capture-to-encode feasibility

The operator confirmed Screen Sharing observation, switched to Observe mode,
and still saw no movement during another five passing readback runs. They
explicitly asked to assume progress could continue and defer that issue.
Visible pointer and actual login-control input remain unqualified; no keys,
clicks, credentials, permission changes or OS login attempts followed.

Added standalone `capture-encode.m` to the signed probe, not the production
Host. SDK 27 explicitly lists SCK 420v and x420 output. `--encode-h264` requests
video-range 8-bit 4:2:0 and H.264 High; `--encode-hevc` requests video-range
10-bit 4:2:0 and HEVC Main10. Both use hardware-required VideoToolbox, real-time,
no reordering, 60fps expected rate and a fixed probe-only 20 Mbps target.
The exact captured IOSurface pixel buffer is submitted unchanged. No CPU pixel
map/copy or explicit transfer stage; Apple-internal copies are not measured.

Serial-queue state, at most three encode frames in flight, 180-submission or
15-second capture limit, and three-second drain bound keep resource use bounded.
Exact surface/dimensions, increasing input/output PTS, matching output PTS,
nonempty compressed sample buffers, actual hardware property, drops and overflow
are checked. The existing outer runner retains its 40-second watchdog. No
pixels or compressed output files are stored by this live probe.

Build 13 first passed both formats. Its diagnostic assumption that stream PTS
could be subtracted from host time yielded incomplete capture-age samples.
Build 14 uses the SDK-documented Mach-absolute SCK displayTime instead and
explicitly counts missing/future values. Many are still future/unavailable at
submission; partial positive-only averages are **not overall capture latency**.
This diagnostic uncertainty does not alter the independently timed encoder
submission-to-callback measurement or PTS-order checks.

Build-14 LoginWindow results, 1920x1080:

| Path | Submitted/encoded | Wall time | Encode mean / p95 / max | Drops / overflow | Peak in flight |
| --- | --- | --- | --- | --- | --- |
| H.264 High, 420v | 121 / 121 | 15.163 s | 11.468 / 12.096 / 17.539 ms | 0 / 0 | 2 |
| HEVC Main10, x420 | 180 / 180 | 10.760 s | 14.129 / 19.043 / 22.570 ms | 0 / 0 | 2 |

Both exit 0. Idle callbacks: 396/229 respectively. These are changing-but-low-
motion login-screen samples, not sustained 60fps, decoded-image acceptance or
end-to-end latency. Capture display timestamps unavailable/future: 64/121 and
145/180. H.264 capture primaries/transfer/matrix attachments all report BT.709;
HEVC x420 reports all three missing despite requested BT.709 capture space.
Do not infer HEVC color mapping or native 10-bit precision from a surface format
and encoder profile setting. Known-pattern decode comparison remains required.

Installed build 14 from `/tmp/plank-macos-probes.wxoMoy`, executable SHA-256
`6bf918b462b7a51083c6c57891302da5e22e76db97192529ddff2810ea9dd4be`.
All seven sources compile with warnings treated as errors; signature, plist and
shell checks pass. No new permission request, input event or display change.
All temporary agents stopped, privileged SSH shell closed, Mac logged out.
Next request operator login for Aqua media/pattern tests. Linux and released
packages unchanged; source, plan and notes remain locally saved, uncommitted.

### Aqua animated-chart qualification and 4K display gate

The operator logged in. Build 14 repeated low-motion capture/encode in Aqua:
H.264 47/47 frames and HEVC 45/45, zero drops/overflow. These short static
samples prompted an owned animated-chart test, not a claim of low throughput.

Builds 15–18 added eight RGB bars, 32 grayscale samples and an animated marker.
Chart tests are desktop-only, non-key and mouse-ignoring, bounded to 900 frames
or 15 seconds. One captured frame is sampled read-only and one keyframe decoded
on a separate validation queue. The ordinary encode path still passes the exact
SCK IOSurface buffer to hardware-required VideoToolbox without CPU pixel access.
Apple-internal conversions/copies are not measured.

The first chart tests exposed real color-contract problems: BT.709 transfer
clipped near-black chart levels, and unlabeled HEVC input caused a roughly
ten-code-value mid-gray shift through VideoToolbox. Independent FFmpeg decode
confirmed this was in the bitstream, not just our validation decoder.
With an explicitly sRGB chart/capture/transfer contract, SCK 420v samples match
BT.709 matrix; x420 samples match BT.601 matrix. On this beta 420v still reports
a BT.709 transfer attachment, while x420 has no color attachments. The probe
sets measured input metadata (709 primaries/sRGB transfer, format-specific
matrix); VideoToolbox then emits BT.709-matrix/sRGB output. The HEVC reference
comparison maps only 40 diagnostic sample triples from 601 to 709; it does not
perform CPU image conversion in the encode path. This is experimental evidence
for this OS build, not permission to guess metadata in a production pipeline.

Build 18, 1920x1080 animated-chart results:

| Path | Frames | Drops / overflow | Complete-frame rate | Encode mean / p95 / max |
| --- | --- | --- | --- | --- |
| H.264 High 8-bit 4:2:0 | 900 / 900 | 0 / 0 | 57.567 fps | 9.378 / 10.856 / 17.807 ms |
| HEVC Main10 10-bit 4:2:0 | 900 / 900 | 0 / 0 | 57.444 fps | 12.364 / 13.938 / 22.845 ms |

Both exit 0, peak two frames in flight. Maximum source-chart errors in
8-bit-equivalent code values: H.264 0.710, HEVC 0.460. Decoded-versus-expected
sample errors: H.264 0, HEVC 0.147. Pinned FFmpeg 9.0.1 on linux-client-builder decoded
the same keyframes independently, matching VideoToolbox within one 10-bit code
value. ffprobe confirmed High/yuv420p and Main10/yuv420p10le respectively,
1920x1080, video range, BT.709 primaries/matrix and iec61966-2-1 transfer.
No files, packages or dependency changes were needed on linux-client-builder.

These are limited 40-point color and short throughput checks, not whole-image,
native 10-bit precision, sustained 60fps, network or glass-to-glass acceptance.
SCK displayTime was missing/future for 886/900 and 888/900 samples; its partial
positive-only timing is not overall capture latency. Moving decoder setup off
the capture queue removed observed diagnostic queue overflow in these runs.
Known-good build-18 executable SHA-256:
`f0e2bfddbb61689ad66081da384845d9a71a673adb091256bef580d0adac85c7`.

**4K remains failed, not qualified.** Build 19 requested an owned 3840x2160
output but observed 1920x1080 and stopped. Build 20 selected an exact 4K mode
with public CGDisplaySetDisplayMode, refusing mirror sets and touching only its
owned display. SCK then returned 4K frames, but samples did not match the chart.
Both source gates failed (~158 code values); no color/performance conclusion
can be drawn. Both also failed to confirm display removal within five seconds
before exit. Post-exit inventory showed one normal 1920x1080@60 main display
and no probe process. No persistent display configuration was saved.
AppKit chart placement, display references and headless/Screen Sharing display
ownership need isolated investigation; none is yet a proven cause.

Two failed 4K keyframes were deleted by exact path because they may have
contained desktop content. Build 21 stops on a failed source-chart gate before
decode/artifact creation. A 40-point check still cannot prove every pixel is
the chart; retain artifacts only on the dedicated development machine.
The operator clarified that they were not watching and were not connected to
Screen Sharing. Subsequent read-only IOConsoleUsers inspection found the user
session still logged in but `CGSSessionScreenIsLocked=Yes`, with a recorded
lock time of 18:42:06 local. This provides a concrete reason an ordinary desktop
chart could be hidden. It does not prove the state during both earlier runs or
explain the separate display-release check. Do not attribute this to an active
Screen Sharing viewer or declare the 4K capture implementation broken yet.
Next request an operator unlock, confirm unlocked state immediately before a
bounded chart test, and independently isolate the owned-display lifetime.
Do not resume the separately deferred input tests or bypass the lock screen.

Build 21 negative checks while locked: 1080p stopped after 30/30 frames, exit 6;
4K stopped after 31/31, no keyframe saved, removal check exit 7. The operator
said they had logged back in, but the pre-run IOConsoleUsers read still showed
locked. That read should have prevented the 4K run, not merely been printed;
make unlocked-state verification a real precondition for the next chart test.
No probe remains running. Next ask for actual desktop unlock with the viewer
kept connected, distinguish that from remote-access authentication, then verify.

All eight Objective-C sources compile with warnings as errors. Linux product,
packages, submodules, permissions and login policy remain unchanged. No persistent
agent/service is installed. Current installed build/hash and final verification
are in HANDOFF.md; all new macOS work remains local and uncommitted.

Primary API references for this phase:
- [SCK color matrix](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/colormatrix)
  documents applicability to 420v/420f, not x420; SDK 27's SCStream.h explicitly
  lists x420 as an output format.
- [SCK display time](https://developer.apple.com/documentation/screencapturekit/scstreamframeinfo/displaytime).
- [VideoToolbox compression](https://developer.apple.com/documentation/videotoolbox/vtcompressionsession-api-collection).
- [Temporary display mode selection](https://developer.apple.com/documentation/coregraphics/cgdisplaysetdisplaymode(_:_:_:)).

### Confirmed unlocked 4K tests and mode-lifetime isolation

The operator reports that exiting Screen Sharing ends their visible user session
and agreed to stay connected. Inspection confirmed a logged-in console session
with no screen-lock flag before the following tests. Keep that precondition;
do not infer unlocked state merely from successful SSH or remote authentication.

| Test | Frames | Drops / overflow | Complete-frame rate | Encode mean / p95 / max |
| --- | --- | --- | --- | --- |
| Build 21, 4K H.264 High | 900 / 900 | 0 / 0 | 57.019 fps | 44.196 / 51.756 / 58.720 ms |
| Build 22, 4K HEVC Main10 | 900 / 900 | 0 / 0 | 57.690 fps | 19.307 / 20.575 / 31.987 ms |

Both media results 0, peak three in flight. Source-chart maximum error was
2.065/1.815 in 8-bit-equivalent code values; roundtrip expected-output error
0/0.147 respectively. Pinned FFmpeg independently decoded the 4K HEVC keyframe:
all 40 sampled triples exactly matched VideoToolbox. Metadata confirms Main10,
3840x2160, yuv420p10le, video range, BT.709 primaries/matrix, sRGB transfer.
These short chart results are not sustained-footage, native 10-bit precision or
glass-to-glass qualification. H.264's measured callback time is materially
higher here; investigate separately before selecting a production default.

Both full tests still exit 7 because in-process owned-display removal failed.
Build 22 adds a scoped autorelease pool and a weak lifetime observation: the
CGVirtualDisplay object is destroyed, but the selected output remains online.
A standalone `display-mode-lifecycle.m` reproduces this without AppKit, SCK,
VideoToolbox or the chart. Creating/releasing a display without selecting a
mode removes it. Selecting a different mode via CGDisplaySetDisplayMode does
not remove it within five seconds after object destruction; process exit does.
An unchanged-mode selection can pass, so tests must force a real mode change.

Two rejected explanations were tested: session-scoped CGCompleteDisplayConfiguration
did not resolve the failure, and a dispatch timer running in CFRunLoopRun did
not resolve a real mode change either. Do not retain the session-policy variant
as a fix; it has been removed. That experiment changed only the owned virtual
display's session configuration, not permanent settings or physical displays.
One two-case same-process test also encountered transient zero-size replacement
display state; final diagnostic uses a fresh process per lifecycle.

This is a measured process-lifetime constraint, not a proven leak in capture or
encoding. Preserve the failed pre-exit gate. Next evaluate display-owner process
lifecycle against login/logout and resolution-change requirements; never use a
global display reset to make this test pass. No capture/input probe remains
running, no persistent service installed, Linux unchanged. The desktop was
unlocked at the final read-only check. Operator visual chart confirmation is
still outstanding; they had not been watching earlier runs.

### Display-owner lifecycle qualification

The operator saw one chart but did not watch every run. Record this as partial
visual confirmation, not a full visual pass. Continued lifecycle tests were
authorized; Screen Sharing remained connected and the console was unlocked.

An exact original-mode restore after a real change succeeded in restoring the
pixels but still did not remove the display when the object was released.
Two fixed geometry-identity experiments (new serial, then new product plus
serial) both read back their requested identity but initially selected 1080p,
not requested 4K. Both removed without a mode switch. Neither is a fix on this
beta; the ordinary helper still uses the original diagnostic identity. No
random identities, global reset or permanent configuration edits were added.
macOS can retain profiles for those two fixed identities; do not remove other
system profiles or claim opening a virtual display leaves no OS state.

The independent [go-macos/virtualdisplay report](https://github.com/go-macos/virtualdisplay/blob/a2a8097f7b29bd68ebf4862d1d7fe5f194e37d78/README.md)
describes comparable mode-change lifetime behavior on macOS 26.6.2, and an
identity-based strategy for initial mode selection. It informed experiments,
not copied implementation or a new dependency. Our identity experiment did
not reproduce its initial-size result on macOS 27. Revalidate each OS directly.

Added standalone `display-owner-lifecycle.m`: a persistent parent starts its
own executable as a child through NSTask. A private inherited pipe returns
bounded numeric display identity/geometry; no socket, credentials or screen
data. The child performs a real mode change. The parent independently verifies
that output and survives both normal child exit and SIGKILL of its exact child,
checking that the display disappears. Both cases passed. Each case is bounded
to twelve seconds, with an independently bounded child; timeout kills/reaps only
that child. No other application/service was terminated. Three further full
runs also passed: four normal exits and four forced terminations total, all
with live geometry verified and display removal observed from the surviving parent.

The current owner probe is `/tmp/plank-display-owner.frFtvw/display-owner-lifecycle`.
It compiles with SDK 27/target 27.0, ARC and warnings as errors. All ten sources
also passed compiler syntax checking. No warning flags were disabled: a shared
header's unused report helper was made static inline for the metadata-only
owner test. Installed signed media probe remains build 22 unchanged.

Next qualify capture and encoding in the parent while the child owns the display,
plus stop-capture-before-owner-exit ordering and resolution replacement. This
would be a child owned by the existing graphical agent, not another launchd
service or a reason to restart the main Host. Cross-login-session authorization,
input and production integration remain open; do not mark them passed from this
standalone display test.

Before wiring this boundary into capture, coordinate a true desktop logout and
repeat the owner test in LoginWindow. The operator must perform logout; merely
disconnecting Screen Sharing previously left a locked user session. No input
events or credential submission are part of that test.

### LoginWindow display-owner verification

The operator explicitly logged out. Read-only inspection confirmed console
LoginWindow with login-complete false, not a locked authenticated desktop.
The exact same owner executable (SHA-256
`18c66ab3e80ce4833994a3d9bd3ce7de4049e212f862a9569f15e31d0c18c5af`)
ran as root through the temporary `loginwindow` launchd domain, without code,
permission or signing changes.

Four complete runs passed: four normal exits and four SIGKILL cases. Every
case verified live resized geometry independently from the parent, child exit,
display removal and parent survival. All four runner exits were zero. Combined
with Aqua, that is sixteen passing cases across eight full invocations.
No key, click, credential, login submission, capture or encoded-frame output was
part of this test. Only the exact spawned test child was forcibly terminated.
This proves the tested display-owner process boundary in both graphical contexts;
it does not qualify capture across that boundary or login/logout handoff.

The temporary owner registration was absent afterward. The operator's desktop
remains logged out. Next integrate the ownership boundary into the capture probe,
test parent-side capture/encode, then coordinated desktop chart/replacement tests.
Installed media app remains build 22. No Linux runtime/package or persistent
service change; notes and probes remain local and uncommitted.

### Parent-side capture of a child-owned display

Build 23 integrated a bounded display-owner child into the signed media probe.
The parent independently verifies the returned display ID and actual mode,
captures that output through SCK, and hardware-encodes the original IOSurface
pixel buffer. Normal teardown stops SCK, finishes encoding and releases the
stream before control-pipe EOF requests owner exit. Removal must be observed
while the parent remains alive. No new launchd service, public endpoint, input
event, permission change or Linux code is involved.

LoginWindow 4K tests passed for both codecs. HEVC encoded 136/136 complete
frames, H.264 122/122, with zero overflow/drops. Mean/p95 encoder callback times
were 23.618/24.080 ms and 19.129/19.229 ms respectively. Both media result and
runner exit were zero. In each case the child exited normally and its display
was removed after media teardown. The mostly static login UI produced many idle
callbacks: these are not moving-content throughput or color qualification.
Neither mode maps/saves screen pixels.

Build 24 added two bounded qualification cases. Forced SIGKILL of only the
exact display-owner child after its first encoded frame passed: two submitted
frames finished encoding, the parent detected owner loss (stream result 8),
stopped capture and encoding, and verified display removal while remaining alive.
The expected failure is a test pass, not a successful continuing stream.

Same-parent 1080p H.264 → 4K HEVC replacement did not pass in builds 24/25.
The first stream completed and removed cleanly; the next owner reported mode
selection success, but the parent could not verify that display's actual mode.
Build 25 narrowed this to CoreGraphics returning a null mode for the new ID
despite online/active true. It rejected the replacement and removed the owner
cleanly. Do not relax the geometry gate or report requested dimensions as actual.
An ordinary SSH inventory during LoginWindow returned no displays and is not
a valid independent graphical-session comparison.

Build 26 tested public CGDisplayRegisterReconfigurationCallback notification;
it did not fix mode reporting, including for the first child output. That
experiment was removed, not layered into the media path. Build 27 uses live
CGDisplayPixelsWide/High and bounds to verify the owned output, then obtains
capture source pixels from SCContentFilter.contentRect multiplied by its
pointPixelScale. Both SDK-documented quantities are measured; requested sizes
are never used as substitute source dimensions. Actual IOSurface format and
dimensions remain checked on every frame. The child still selects an exact
60 Hz mode; the parent no longer claims an independent refresh-rate readback
when a CoreGraphics mode object is unavailable.

The first build-27 LoginWindow replacement test passed. In the same parent,
1080p H.264 captured/encoded 156/156 frames, then 4K HEVC 167/167. Both streams
had zero drops/overflow and verified SCK pixel geometry; both owners exited
normally and their displays disappeared after media teardown. This establishes
a first bounded resolution-replacement pass, not a sustained or cross-login-
session result. Desktop chart qualification of the new owner path remains next.

Two more build-27 replacement runs verified both geometries and all teardown
steps. One passed all media gates (154/154 H.264 and 153/153 HEVC); the other
failed the strict media gate with one HEVC queue-overflow frame despite 168/168
submitted frames encoding. Maximum callback was 51.092 ms in that failed run.
Thus two of three complete replacement runs passed, not three. No queue-depth
increase or performance workaround was added. Build 27 also repeated the owner
crash pass: 2/2 submitted frames, stream result 8, correct cleanup, test exit 0.
All eleven sources build with warnings as errors and verified signing. Current
build hash/output are recorded in HANDOFF. Desktop chart/color and sustained
moving-content tests remain separate gates.

### Read-only PCoIP resize observation

The operator resized the active PCoIP viewer smaller, paused, and enlarged it.
Only existing process metadata, imported symbols and display-related server log
lines were read on the reference Mac (Anyware 26.05.3, macOS 26.6.2). Nothing
was uploaded, built, injected, reconfigured or restarted there. The log follow
was stopped after both changes; raw logs/session identifiers are not committed.

Both resizes destroyed and recreated the software display rather than retaining
the same display ID. Observed geometry was 1708x1072 → 1440x932 → 1708x1072,
all logged at 60 Hz. The same existing media-server process and graphical
user-agent process survived throughout; this does not establish whether any
short-lived internal helper was involved between process snapshots.

The logged sequence for each resize was:

1. Destroy the previous virtual display; wait for its disabled notification.
2. The system's fallback 1920x1080 display briefly becomes active.
3. Create a fresh virtual-display descriptor with the same 4096x4096 maximum
   capacity, 641x401 mm physical size, and stable reported vendor/product/serial.
4. Supply the requested size as an initial supported mode before first activation.
5. Wait for the enabled notification; apply/publish the resulting topology.

Removal work took 22/27 ms; initial-mode/activation work took 279/296 ms.
From logged destruction to new-display readiness was approximately 333/352 ms.
These are display-management intervals, not measured visual interruption or
glass-to-glass latency. Its waits have explicit deadlines (2 seconds for
removal and 15 seconds for activation); they normally complete on notifications,
not by sleeping the full timeout. The larger request was 1710 pixels wide, but
PCoIP chose 1708 and logged a close-mode fallback. Do not copy that silent
size substitution into PLANK's strict qualification gates.

This evidence supports testing replacement with the desired initial mode and
a stable descriptor capacity, avoiding a later public mode switch when possible.
Our prior initial-mode experiments changed identities but did not qualify this
exact sequence. Test it independently on the dedicated macOS 27 development
Mac before changing the working child-owner path. Do not assume the older
reference OS behavior will transfer unchanged, that notifications fix our
mode-object issue, or that the child boundary is already unnecessary. No
proprietary implementation was copied or inferred solely from symbol imports.

### Isolated initial-mode/stable-capacity experiment

Added standalone `display-initial-mode.m`, not linked into the signed media
app. It holds maximum capacity at 4096x4096, keeps the original PLANK diagnostic
identity/physical dimensions unchanged, and applies only one requested initial
60 Hz mode with HiDPI off. It never calls CGDisplaySetDisplayMode or public
configuration transactions. This tests the relevant hypothesis from PCoIP's
logs, not a reconstruction of proprietary behavior. No random identities,
global preference reset, delayed reapplication or additional workaround.

Two LoginWindow runs sequentially created/released 1920x1080, 1440x932,
3840x2160 and 1708x1072 in one surviving process. Both matched the three smaller
sizes but selected actual 1920x1080 for the 4K request. Every object was released
and every output removed before the owner exited. Correct small sizes became
ready in roughly 25–48 ms; removal checks completed in roughly 4–63 ms.
The 4K case exhausted its five-second readiness deadline rather than accepting
a wrong size. These are probe lifecycle times, not media latency.

The second run launched a fresh read-only observer for each display, inheriting
the same graphical session. All four observers confirmed the actual mode
pixels/points at 60 Hz. For the failed request both were 1920x1080: it was not
a 3840x2160 Retina backing surface, nor merely the owner's missing mode object.
The observer creates no displays; the original process remains sole owner.
Its bounded lifetime and output are documented in the probe README.

Overall matrix exit was 7 for the resolution mismatch, with all cleanup gates
passing. Next repeat in an operator-unlocked Aqua desktop to determine whether
this mode selection is LoginWindow-specific. Keep the qualified build-27 child
owner and media code intact pending that comparison. Signed app hash remains
unchanged. Post-test graphical inventory found one fallback 1920x1080@60
display. No capture, input, TCC, SIP, login policy, persistent service, Linux
runtime, package version or release changed. All twelve sources passed SDK-27
warnings-as-errors syntax checks; standalone probe hash/path are in HANDOFF.

### Aqua comparison and Screen Sharing uncertainty

After operator login, console ownership and IOConsoleLocked=false confirmed an
unlocked Aqua session. The exact same observer-equipped initial-mode executable
gave the same result as LoginWindow: three smaller sizes correct; requested 4K
was real 1920x1080 pixels/points at 60 Hz. Every output removed while its owner
survived. Screen Sharing remained active, so this comparison does not isolate
its effect. It rules out an exclusively LoginWindow-observed failure, not all
session/display-policy influences.

The unchanged build-27 child-owner HEVC 4K chart path then passed: SCK reported
3840x2160 at scale 1, 864 submitted/encoded frames, zero overflow/drops, 57.790
complete fps, 19.279/20.547 ms mean/p95 callback time. Source and decoded
40-sample gates passed (1.815 and 0.147 code values in 8-bit-equivalent units).
Capture/encoder teardown completed before owner exit and output removal. The
new guarded chart keyframe has not yet been independently decoded with FFmpeg;
do not imply that older independent-decode results qualify this exact artifact.

The operator raised possible Screen Sharing interference and asked about login
without a connected viewer. Read-only inspection found one authenticated console
session and an active ScreensharingAgent; it did not prove a separate virtual
user session or a logout-on-disconnect policy. No automatic-login setting was
read back. Earlier observations included a locked authenticated desktop, so
coordinate a viewer disconnect and distinguish lock from logout before changing
session policy. SSH authentication alone is not a graphical-console login.
No automatic login, lock-policy override, credential injection or settings
change was performed. All probes are stopped.

### Rebooted auto-login desktop, no Screen Sharing

The operator enabled automatic login and manually rebooted the dedicated Mac,
then left Screen Sharing disconnected. Read-only checks showed a fresh unlocked
authenticated console and no Screen Sharing processes. No security policy was
changed by the agent. This is a temporary development setup; normal LoginWindow
acceptance still requires restoration/coordination, not an auto-login dependency.

Reboot cleared prior temporary probe builds and chart files. The standalone
initial-mode source/runner were uploaded again and rebuilt with SDK 27/target
27.0 and warnings as errors. The executable SHA-256 matched the earlier one
exactly. Its matrix again matched the three smaller sizes but selected actual
1920x1080 for requested 3840x2160. Independent fresh-process readback confirmed
pixels/points at 1080p, and all outputs removed. Thus an active Screen Sharing
connection is not necessary for the failure. This does not eliminate persisted
display preferences as a factor; no global preference reset was attempted.

The installed signed build-27 media app retained its exact hash and existing
capture permission after reboot. Both child-owned 4K chart cases passed:

| Case | Encoded/submitted | Overflow/drops | Frame rate | Encoder callback mean/p95 |
| --- | --- | --- | --- | --- |
| HEVC Main10 | 856/856 | 0/0 | 57.383 fps | 18.889/20.173 ms |
| H.264 High | 856/856 | 0/0 | 57.191 fps | 43.589/51.419 ms |

SCK source geometry was 3840x2160 at scale 1. Source sample error was 1.815
for HEVC and 2.065 for H.264 in 8-bit-equivalent units. Decoded comparison
errors were 0.147 and zero. Both stopped SCK, invalidated/released encoding,
closed the owner pipe and verified normal child exit/display removal while
the parent survived. The small animated chart is not sustained real-footage,
native-10-bit precision or glass-to-glass qualification; H.264's higher callback
latency remains an explicit optimization question.

Each new guarded keyframe was streamed over SSH to the retained pinned FFmpeg
on linux-client-builder for independent decode, with raw decoded data streamed back for
40-point comparison. No files/packages were installed on that builder. Both
decoded sample sets matched VideoToolbox exactly: zero difference across 120
component values each. ffprobe confirmed 3840x2160, HEVC Main10/yuv420p10le and
H.264 High/yuv420p, video range, BT.709 primaries/matrix, sRGB transfer. Current
artifact locations and replacement temporary source path are in HANDOFF.

### Reference 4K and isolated descriptor comparisons

Read-only reference inventory now confirms Anyware Virtual Display 1 at actual
4096x2160, UI 4096x2160, 60 Hz, online/non-mirrored. Agent logs agree: fixed
4096x4096 capacity and 641x401 mm physical size, initial 4096x2160@60 mode,
activation notification after 288 ms. The client topology request mentions
30 Hz, but the activated OS mode is 60 Hz; this is not a streaming-frame-rate
measurement. The media-server process is new relative to the earlier small-size
resize test. Therefore this proves initial native 4K activation, not clean 4K
replacement inside one surviving server. No captures, uploads or changes on
the read-only reference Mac.

Extended only the standalone initial-mode diagnostic and its bounded runner.
The first four-case matrix on the development Mac tested baseline 3840x2160,
the same request with 641x401 mm physical size, exact 4096x2160 at that size,
and baseline size with a 150 ms main-run-loop interval before first settings
application. Identity and capacity remained fixed. Every 3840 request became
1920x1080; the 4096 request became 1920x1012. A second four-case matrix compared
HiDPI off/on for both 4K dimensions using 641x401 mm. Results were unchanged.
Independent observers confirmed these were both pixel and point dimensions;
there was no hidden 4K Retina backing surface. Each readiness deadline expired
at about five seconds. All eight objects were destroyed and outputs removed
while the owner survived, with removal checks roughly 50–67 ms.

These comparisons do not resolve initial mode selection. They rule out the
tested physical-size, short-registration-interval and HiDPI variations as
standalone fixes, not every possible ordering or descriptor difference.
No system preference reset or new monitor identity was used; persisted policy
and OS-version differences remain possible. The referenced open-source
virtualdisplay report also describes mode persistence and mode-change lifetime
problems, but its macOS 26 observations cannot qualify our macOS 27 behavior.
Keep the already working child-owner/mode-selection implementation. SDK-27
warnings-as-errors compilation and runner syntax checks passed. Signed media
build 27, its hash, Linux code and package versions are unchanged. No media or
input test was performed in these eight cases. Current standalone hash is in
HANDOFF; tests stopped with fallback display only.

### Session-boundary preparation (builds 28–29)

Added a passive observer and opt-in guarded media modes, leaving the original
media qualification entry points available. Initial state uses the caller's
Security session identity and graphical-access bit, CG on-console/login-done
state and UID, and SystemConfiguration console UID. Missing/ambiguous state
fails closed. Initial code tried the documented CG console-set key, which was
unavailable on this session; it was not retained as a prerequisite. Build 28's
audit-ID-only approach could still classify an SSH process as a desktop because
CG returned console-user state. Capture permission refused it, so no media was
captured, but this exposed an inadequate initial session gate. Build 29 uses
`SessionGetInfo(callerSecuritySession, ...)` and `sessionHasGraphicAccess` from
the SDK's Security/AuthSession.h instead. Direct SSH execution now exits 2 at
initial identity validation; the properly bootstrapped Aqua agent passes.

Synthetic tests cover stable sign-in/desktop identities, login/logout changes,
different users/sessions, unavailable state and malformed numeric fields.
The passive observer uses SDK-declared console/user-change notifications with
a 500 ms fallback; guarded media revokes on either notification and rechecks
identity every 250 ms on its serial queue. Revocation is irreversible for that
probe. It stops new capture submissions, drains/invalidate encoding and retires
the owned display. No network output, account authorization, credential entry,
OS input, screen image persistence, login-policy change or persistent service
was added. This is preparation, not a continuous session-handoff controller.

Build 28's synthetic revocation passed with 2/2 encoded and no overflow, and its
ordinary guarded 4K run passed 467/467 with no overflow/drops. Build 29's first
synthetic run encoded 3/3 but had one startup overflow (58.035 ms max callback):
strict media gate failed, while ordered capture/encoder/owner/display cleanup
passed. A second run of the same build passed 3/3 with no overflow, max callback
33.016 ms and explicit transition result 10. Preserve both results. No buffer
or deadline increase was made. Build 29's ordinary 15-second guarded desktop
run passed 471/471, no overflow/drops, 31.984/54.576 ms mean/p95 callback. This
was an ordinary desktop with idle frames, not a controlled moving-chart
throughput or color test. Every run verified real 3840x2160 SCK surfaces and
hardware HEVC Main10, followed by capture/encoder stop and display removal.

Current installed hash/build/source and previous build-27 backup are in HANDOFF.
Full signed probe builds passed SDK-27/target-27 warnings-as-errors compilation,
signature/plist checks and shell syntax checks. Next requires operator logout:
strict positive LoginWindow identification is not yet measured, and continuous
logout/login notification ordering, agent replacement, input/transport continuity
and lock/fast-user-switch security require separate tests.

The original same-parent owner replacement mode also passed on build 29:
1080p H.264 followed by 4K HEVC, each 180/180 with no overflow/drops, actual
source geometry verified and full teardown/removal before replacement. This
regression check changes resolution inside Aqua; it does not authenticate,
log out or prove cross-session handoff.

### Build 29 in the real LoginWindow session

After operator logout, root ownership of the console and launchd's LoginWindow
domain confirmed a real logged-out state. The unchanged passive observer
positively classified sign-in with root UID and the graphical security-session
identity. No predicate relaxation or further signed rebuild was needed.

Guarded HEVC Main10 capture created a verified 1920x1080 owned display, passed
capture permission, selected exact SCK source geometry and hardware encoding,
then submitted/encoded 168/168 frames with zero drops/overflow. Encoder callback
mean/p95/max was 11.855/14.319/21.605 ms. The mostly idle sign-in screen is not
a throughput test. Stop/drain/invalidate preceded normal owner exit and display
removal. Synthetic revocation after first encoded output also passed: 2/2,
zero drops/overflow, expected stream result 10 and complete normal cleanup.
No pixels were stored, input posted, credentials entered or login policy changed.
Build 29 now has separate Aqua and LoginWindow endpoint passes. Actual
notification-triggered login/logout, a machine-level replacement controller,
transport continuity and input handoff are still unimplemented/unqualified.

### Guarded desktop after operator logout/login

The operator logged back in through Screen Sharing and stayed connected by
agreement; no reboot/automatic-login replacement was used. Launchd and the
passive observer confirmed Aqua with the authenticated desktop UID. Its security
session ID matched the preceding LoginWindow's, while UID and login state
changed. The guard's composite identity checks cover that distinction; a session
ID alone would not identify the same media authority across this transition.

Unchanged signed build 29 then passed guarded 4K HEVC Main10: SCK content
3840x2160 points at scale 1, exact x420/IOSurface geometry, hardware encoding,
45 submitted/encoded and 302 idle callbacks over 15.018 seconds, zero drops or
overflow. Callback mean/p95/max was 16.845/22.544/30.980 ms. The short complete-
frame PTS span of 0.817 seconds and mostly idle desktop do not qualify sustained
frame rate. Capture/encoder teardown and normal owner exit/display removal all
passed. This establishes fresh endpoint operation after a real logout/login,
not continuous handoff: no media agent was running across the transition itself.
No images, credentials or input were recorded/sent. Next implement the bounded
machine-level transition controller and coordinate its live test rather than
repeating isolated endpoint launches.

### Bounded machine-level controller (builds 30–31)

Implemented a temporary administrator-run controller using native console-state
observation and launchd graphical jobs. The installed signed executable is
hash/signature checked, helper paths are protected root-owned files, and the
operator explicitly designates one non-root desktop UID. The controller launches
no user shell and has no network endpoint. Each generation independently checks
its graphical identity, creates the existing child-owned 1080p/4K display, and
reports readiness only after its first correctly sized encoded frame. The old
worker must exit and its previously observed display must disappear before a
replacement starts. SIGUSR1 addresses the controller's exact launchd label for
orderly retirement; abrupt session teardown is distinguished as OS reclamation.
Missing final counters cannot qualify media. Queue limits remain unchanged.

Controller runtime is capped at 180 seconds, graphical media at 180, and the
private display child's abandonment deadline at 200 seconds. Existing short
qualification modes retain their previous bounds. Root-created temporary
directories contain plist and bounded diagnostic text only, with per-worker
output ownership; no captures or credentials are written. This controlled
same-account diagnostic environment is not production peer authentication.

Build 30's first 12-second controller run encoded 121/121 but had four startup
overflows (86.440 ms maximum callback). Retirement and independent process/
display removal passed; strict media failed. A repeat encoded 44/44 with no
overflow/drops and passed both lifecycle and media gates. An injected SIGKILL
of the controller's exact ready graphical job made it fail closed without
restarting into the unchanged session. The child observed pipe EOF, and the
controller independently verified both worker exit and display removal. This
was expected crash rejection, not graceful media drain.

Build 31 makes controlled retirement an expected successful handoff-worker
outcome rather than printing a misleading failed local boundary gate. Its
12-second controller test passed 75/75, zero drops/overflow, mean/p95/max
callback 18.805/24.590/37.909 ms, followed by orderly drain and independently
verified removal. Ordinary idle desktop content does not qualify throughput.
Seven pure controller tests pass on linux-host-builder and the Mac; real wrong-UID and
wrong-app-hash invocations were refused before a graphical job started. SDK-27
warnings-as-errors builds, signing/plist and Python/shell checks passed.
Post-test inventory shows only fallback 1080p. No Linux code or packages changed.
Current hashes, paths and retained diagnostic directories are in HANDOFF.

Next coordinate the first live logout/login run. No controller has yet spanned
both phases; media transport, input continuity, session authentication and
unattended/cold-boot product installation remain outside this prototype.

### First real logout and graphical verification correction (build 32)

The first controller run across operator logout correctly revoked the desktop
worker, drained capture/encoding and independently verified display removal.
It encoded 217/217 but had 42 overflows (mean/p95/max callback
51.484/98.643/108.728 ms): lifecycle cleanup passed, strict media did not.
The machine observer then announced sign-in before the new graphical worker's
identity was available. That worker refused before display creation. Build 32
waits at most five seconds for the same initial graphical identity predicates;
it does not retry capture or weaken the user/session checks. A direct SSH
negative test still refused after 5,005 ms without creating a display.

The next sign-in test captured successfully, but independent verification
failed because the background root controller enumerated zero displays.
The worker retired normally (2/2 encoded, no overflow/drops); this failed
verification is not recorded as successful independent cleanup. Inventory is
now a separate read-only, bounded temporary launchd job in the active graphical
domain. Empty/unbounded inventory remains an error. Only owned helper jobs are
removed; no persistent service or user security setting is changed.

With that correction, a 180-second LoginWindow run passed 1,706/1,706 encoded,
zero overflow/drops, mean/p95/max callback 13.689/14.751/22.261 ms. The normal
retirement path stopped capture, released the encoder, exited the owner and
independently verified old worker/display removal. This mostly idle sign-in
screen is not a sustained frame-rate or color-precision qualification.
Seven pure controller tests still pass. Actual sign-in→desktop replacement is
the next live test; no transport or input continuity claim follows from these
standalone media results.

### First complete sign-in→desktop controller pass (build 32)

One controller remained alive across the operator's actual login. Generation 1
captured 1080p sign-in and encoded 538/538 with no overflow/drops; callback
mean/p95/max was 13.580/14.941/24.439 ms. Its session-user notification revoked
capture. Capture/encoder stop and child pipe-EOF exit were observed; macOS
session reclamation completed the worker lifecycle before a normal parent
owner-cleanup summary, so the report correctly distinguishes OS reclamation.
The independent graphical verifier confirmed the previous display was gone,
and the old worker PID was no longer alive before replacement.

Generation 2 independently validated the authenticated desktop identity and
captured actual 3840x2160 through SCK into hardware HEVC. It encoded 266/266,
zero overflow/drops, callback mean/p95/max 31.774/47.940/58.968 ms. At the
180-second controller deadline it drained capture/encoder, normally retired
the owner and independently confirmed display/worker removal. Both final
lifecycle and strict media gates passed. Content was mostly idle, not a 60fps
performance test. No images, input, credentials or transport were involved.

The requested reverse logout did not occur within this run. All probe jobs
stopped; build-32 desktop→LoginWindow replacement still needs a fresh timed
test. Do not equate this one-way pass with a complete login/logout round trip,
remote authentication, input continuity or production Host readiness.

### Reverse desktop→sign-in lifecycle pass, media failure (build 32)

A fresh run began on the confirmed desktop, then the operator logged out after
the verified 4K first frame. The old worker revoked on identity change and
retired normally: capture stopped, encoder released, owner exited, and the
controller independently verified old worker/display removal. Desktop encoded
163/163 with 22 queue overflows and zero encoder drops. Callback mean/p95/max
was 44.603/89.383/104.671 ms. These aggregate counters do not establish whether
overflow happened at startup, during logout, or throughout the desktop segment.
Do not dismiss it as transition-only or silently increase the three-frame bound.

The next worker encountered the previously observed early sign-in announcement
and waited 243.830 ms for its strict graphical identity predicates. It then
created and captured actual 1920x1080 with hardware HEVC and became ready.
After observing the reverse transition, the controller was stopped through its
normal SIGINT handler. Sign-in encoded 227/227, zero overflow/drops, callback
mean/p95/max 13.551/14.716/21.557 ms, followed by orderly drain and independently
verified removal. Final lifecycle gate passed; strict media gate failed because
of the desktop overflow. The process exited nonzero as intended for that failure.

Both directions now have actual lifecycle evidence in separate runs. They do
not establish a zero-drop round trip, sustained 4K60, remote authentication,
or transport/input continuity. No code change or rebuild was needed this run.
All probes and root SSH stopped; the operator remains at sign-in. Next isolate
4K queue-pressure timing with bounded diagnostics rather than changing queue
limits or weakening the media acceptance gate.

### Bounded queue timing instrumentation (build 33)

Added 181 fixed one-second timing records only to the handoff qualification
mode. Records count complete SCK frames, application overflow and VT callbacks,
plus maximum encode-submit-call duration, submit-to-VT-callback time and
callback-to-serial-queue processing delay. All updates remain on the existing
serial queue; records print only after capture stops. No frame-by-frame logging,
tracing thread, pixel readback, new queue or encoder/session policy change.
The stop-relative timestamp distinguishes pre-stop activity from retirement;
the final bucket includes bounded drain. Existing strict media gates remain.

SDK-27 warnings-as-errors compilation, signature/plist checks and seven pure
controller tests passed. Uploaded source hashes match the local tree. Signed
build 33 passed a 125.6-second sign-in baseline: 1,285/1,285 encoded, zero
overflow/drops, callback mean/p95/max 12.857/14.622/22.928 ms, maximum submit
3.305 ms and callback-dispatch delay 4.646 ms. Summed timing counters exactly
match complete/encoded/overflow totals. Normal media/owner teardown and
independent worker/display removal passed. No desktop login occurred during
this run, so it does not explain the intermittent 4K issue.

All probes/root SSH stopped. Next obtain a logged-in idle 4K baseline before
requesting any logout, then compare timing around a coordinated transition.
Do not classify the previous 4K overflows as startup-only or logout-only without
that evidence. Current build/hash/temporary paths are in HANDOFF.

### Idle 4K overflow reproduced independently of logout

After operator login, two 60-second build-33 controller runs stayed in the same
desktop throughout. The first encoded 133/133 with two overflows in second 15;
the second encoded 137/137 with seven overflows in second 18. Both had zero
encoder drops, normal teardown, independently verified removal, and failed
strict media gates. Startup bucket zero had no overflow; retirement occurred
around second 57. Thus logout is not required to reproduce this failure.

In the respective overflow buckets, encoder callback maxima were 94.202 and
94.090 ms; submit-call maxima were 0.053/0.083 ms, and callback-dispatch maxima
0.062/6.380 ms. Most sparse steady-state frames took about 44 ms to callback.
The application dispatch delay does not account for the observed encoder wait;
these measurements do not isolate hardware execution from synchronization,
conversion, framework scheduling or encoder buffering. A short system sample
showed roughly 97% CPU idle, not evidence of sustained system CPU saturation.

The unchanged capture-independent synthetic encoder probe passed all four
H.264/HEVC 1080p/4K cases. Warm 4K HEVC callback mean/p95/max was
10.510/10.968/11.251 ms. That test uses a reusable synthetic surface, BT.709
metadata and a different bitrate, so it is not a controlled SCK comparison.

Extended only the standalone synthetic probe with a controlled 20 Mbps 4K
Main10 color-timing matrix. Identical ramp/content/cadence gave mean times:
BT.709 10.556 ms; sRGB transfer 10.468 ms; sRGB plus input 601/output 709
matrix conversion 13.970 ms. The final case's p95/max were 14.559/14.817 ms.
This matches the live metadata and bitrate, not SCK content or surface lifetime.
It measures timing, not new color-fidelity acceptance. Live metadata and queues
are unchanged. A subsequent serial synthetic cadence test, using the same
conversion, produced 15.322–15.744 ms callbacks during ten one-second waits.
Its fixed 1/60 synthetic PTS and reused surface intentionally differ from SCK;
this does not rule out effects from actual media timestamps or shared-surface
synchronization. Both standalone extensions compiled under SDK 27 with warnings
as errors, and all synthetic frames encoded successfully.

Neither synthetic comparison reproduces the live ~44/94 ms behavior. Next
isolate SCK source-surface readiness/lifetime and actual timestamp/cadence
interaction rather than increasing queues or changing the qualified color
contract. The SDK documents low-latency encoder selection and frame-delay
controls, but no such property was changed/tested here; HEVC applicability must
be measured rather than inferred from Apple's older H.264 low-latency example:
https://developer.apple.com/videos/play/wwdc2021/10158/

All probes/root SSH stopped. The user remains logged in. Signed app build 33
is unchanged; only the standalone synthetic probe source was extended. No
desktop screenshots, input, credentials, production packages or Linux code
were involved. Current paths and live failure logs are retained in HANDOFF.

### Capture-sample/timestamp isolation and native encoder comparisons

Builds 34–38 add mutually exclusive opt-in qualification modes. They do not
change default capture, encoder, source-color metadata, timestamps, queue limits
or session authority. No production Host/Client changes were made. All were
compiled with SDK-27 warnings-as-errors and verified signatures. Seven pure
controller tests and source whitespace checks still pass.

Separate 45-second idle desktop runs (about 42 seconds of actual media) gave:

| Mode | Encoded | Mean / p95 / max callback ms | Overflow / drops |
| --- | ---: | --- | --- |
| Baseline | 102/102 | 30.179 / 46.837 / 50.758 | 0 / 0 |
| Retain enclosing CMSampleBuffer until VT callback | 101/101 | 30.357 / 48.923 / 50.403 | 0 / 0 |
| Synthetic encoder PTS, 1/60 increments | 101/101 | 16.078 / 19.699 / 33.980 | 0 / 0 |
| Rebase actual PTS to first-frame zero | 102/102 | 29.275 / 47.099 / 54.965 | 0 / 0 |
| Native speed-over-quality property | 101/101 | 21.334 / 31.206 / 33.563 | 0 / 0 |

Every row passed normal drain/owner retirement and independent worker/display
removal. Short mostly idle passes do not erase the earlier intermittent overflow
failures. Retaining the entire sample made no material timing improvement in
this test; this does not rule out all surface synchronization effects. Synthetic
PTS changed encoding latency without changing pixel surfaces, but destroys real
frame timing and must never be promoted as an A/V streaming workaround. Merely
changing epoch did not help, implicating inter-frame timing/encoder interaction
rather than absolute timestamp magnitude. These are controlled clues, not a
complete proof of why earlier bursts overflowed.

A separate native low-latency encoder-specification request failed the current
HEVC Main10 setup with -12900 before capture. No codec/software fallback was
attempted. Normal owner cleanup and independent removal occurred, but the
controller correctly failed qualification for absence of a first encoded frame
(its cleanup-failure message refers to that gate, not an observed resource leak).
The test does not identify which property failed or establish that every possible
HEVC low-latency configuration is unsupported.

Speed-over-quality preserved original timestamps and improved idle timing. It
remains opt-in pending moving content, output-format, image-quality and transition
regressions. Build 38 adds a desktop-guarded speed variant of the existing animated
4K chart. The unchanged baseline was tested first and failed source-chart
verification: max reference error 158.185 in 8-bit-equivalent units. It encoded
30/30 with no overflow/drops then stopped (result 6); decoder/artifact creation
was intentionally skipped. Normal capture/encoder/owner cleanup completed.
No speed chart was run after the baseline failed. This is not evidence of an
encoder color regression—the captured source did not contain the expected chart.

Next inspect chart window visibility/geometry on the new owned display before
performing any quality comparison. Do not relax the chart reference check or
record arbitrary desktop keyframes. All probes/root SSH stopped; the user remains
logged into the desktop. Current installed hash/source/output paths are in HANDOFF.

### Owned-chart readiness and moving speed-priority comparison (builds 39–40)

Build 39 instrumented only the owned chart window's geometry. AppKit reported
visible before WindowServer listed that window; it subsequently appeared at the
correct 3840x2160 bounds and the baseline chart passed. This supports adding an
explicit readiness condition, but does not prove why the earlier uninstrumented
build-38 source check failed.

Build 40 waits at most three seconds for the owned window to be visible,
compositor-on-screen, associated with the requested display, and exactly match
that display's nonempty bounds. It pumps the main run loop in bounded slices.
Timeout closes the chart and fails; the existing captured-source/color guard
and two-second settling delay remain. No capture, color, encoder, queue or
default timing policy changed.

| 15-second animated 4K HEVC chart | Baseline | Speed priority |
| --- | ---: | ---: |
| Chart ready, ms | 16.913 | 17.320 |
| Submitted / encoded | 864 / 864 | 864 / 864 |
| Overflow / dropped | 0 / 0 | 0 / 0 |
| Peak in-flight | 3 | 3 |
| Measured frame rate | 57.790 | 57.726 |
| Callback mean / p95 / max, ms | 19.053 / 20.555 / 31.006 | 18.947 / 20.448 / 30.851 |
| Maximum decoded reference error, 8-bit equivalent | 1.815 | 1.815 |
| Maximum decoded versus source error, 8-bit equivalent | 0.147 | 0.147 |

Both passed source and decoded-color checks, normal capture/encoder cleanup,
owner exit and display removal. Independent ffprobe inspection of the guarded
synthetic keyframes through the retained linux-client-builder FFmpeg confirms identical
format: 3840x2160 HEVC Main10/yuv420p10le, video range, BT.709 primaries/matrix,
sRGB transfer. No builder files or packages were installed. The first ad hoc
ffprobe invocation omitted its private shared-library path and failed to load;
repeating with the documented per-command LD_LIBRARY_PATH succeeded. This is
not a build or dependency failure. Independent raw-pixel comparison was not
repeated for these two artifacts; decoded-color checks above use VideoToolbox.

The moving-marker chart does not show the idle timing advantage and is too
simple to qualify real-footage quality or sustained 4K60. Keep speed priority
opt-in pending longer mixed-cadence tests and session-transition qualification.
No native source-precision or glass-to-glass claim is made. SDK-27 builds with
warnings as errors, signature checks, seven pure tests and whitespace checks
pass. All probe processes and privileged SSH have stopped. Current app hash
and qualified artifact paths are recorded at the top of HANDOFF.

### Real idle-to-motion transitions (builds 41–42)

Build 41 added desktop-only 180-second baseline/speed chart entry points,
reusing the bounded long-run owner and timing buckets. Its animation group
held the marker position constant for nine seconds per cycle, but capture still
delivered ~58 fps: 10,370/10,370, no overflow/drops. This passed continuous
capture, not genuinely sparse cadence. Do not use it as the idle test.

Build 42 removes the animation entirely for nine seconds, then reinstalls it
for nine seconds. A main-run-loop timer owns these phases and is invalidated
on window close. Session authority, source validation, real timestamps and
three-frame queue limits remain unchanged. SDK-27 warnings-as-errors build,
signed installation and seven pure tests passed.

| 180-second actual mixed cadence | Baseline | Speed priority |
| --- | ---: | ---: |
| Submitted / encoded | 4,589 / 4,589 | 5,257 / 5,257 |
| Idle callbacks | 2,744 | 2,434 |
| Application overflow | 602 | 0 |
| Encoder drops | 0 | 0 |
| Callback mean / p95 / max, ms | 33.817 / 75.438 / 87.009 | 22.501 / 30.056 / 33.557 |
| Encoded bytes | 3,483,414 | 449,348,257 |
| Strict media result | FAIL | PASS |

Baseline overflows recur after motion restarts (e.g. seconds 16–19, 34–37,
52–55 relative to capture start). Submit and callback-dispatch delays remain
much smaller than encoder callback wait in those buckets. Speed priority has
no overflow at the same phase changes. This demonstrates a reproducible
improvement for this workload, not a complete explanation of framework internals.

Both initial source/decoded-color checks pass, with maximum decoded-reference
error 1.815 and decoded-versus-source error 0.147 in 8-bit-equivalent units.
Both stop capture, release the encoder, exit the owner normally and remove the
virtual display. Average frame rate across alternating idle/motion is not a
continuous 60 fps throughput measure. The speed variant emitted ~19.96 Mbps,
versus ~0.155 Mbps baseline, despite both being configured at 20 Mbps. Its
bandwidth use and real-footage quality must be evaluated together; the chart
does not establish equivalent compression efficiency.

Retain speed priority as the provisional interactive-preview candidate, still
opt-in. Do not tune additional properties before connecting the existing
transport/Client and measuring actual interaction. Coordinated login/logout,
complex footage, audio, long-soak and end-to-end latency gates remain open.
Raw local Git-ignored diagnostics and Mac synthetic artifact paths are in
HANDOFF. No production Host/Client or networking code changed.
