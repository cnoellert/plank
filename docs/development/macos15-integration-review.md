# macOS 15 Client: integration review and contribution plan

This is the current synthesis of the experimental Client work. Detailed,
chronological evidence remains in [the development record](macos15-client.md)
and [HANDOFF](../../HANDOFF.md). Private recordings, workstation identities,
credentials and raw logs are excluded from this document and PR attachments.

## Status and scope

The operator has exercised an Apple Silicon/macOS 15 Client against a Linux
NVIDIA/X11 Host, using one standard-density external display and one Retina
built-in display, with a USB Wacom tablet and Autodesk Flame. The hardware Host
runs Rocky 9.5; Host packages were built in an isolated pinned Rocky 9.7
container. That does not qualify Rocky 9.5 as a supported release platform.

The accepted development pair is Client 1.0.126 / Host 1.0.125. The separate
`codex/macos15-pr-review` branches reconcile current upstream and reduce the
effect of Mac-specific fixes on Linux. Their latest candidate is 1.0.128, which is
not yet live-accepted. Neither branch is a published release or a blanket
replacement qualification for an existing remote desktop product.

No macOS Host support for macOS 15 was added. The default Client target remains
27.0; 15.0 requires `PLANK_MAC_CLIENT_MIN_MACOS=15.0`. Windows support, generic
USB redirection, arbitrary monitor arrangements and per-monitor Linux desktop
scaling are outside this contribution.

## Upstream reconciliation

Review bases were fetched directly from the maintained repositories:

| Repository | Upstream reviewed | Local contribution / integration |
| --- | --- | --- |
| `instinctual/plank` | `cb01cfe` (`main`) | Earlier snapshot `50a05e1`; publication-time integration `9b495ee` |
| `instinctual/plank-client` | `86682b5` (`main`) | Accepted `0f57be3`; platform scoping `9c1af82`; publication-time integration `d9ad2b1` |
| `instinctual/plank-host-linux` | `9329784a` (`main`) | `d96eb476` |
| `instinctual/plank-common-c` | `b965055` (`plank/client`) | `0c82257` |
| `instinctual/plank-libvirtualhid` | `93d57db` (`plank/main`) | `b0cc3c8` |

The Client's upstream Retina commits `509f2fc` and `6f0c252` had already been
cherry-picked with attribution. Their merge conflicts were reconciled while
retaining native Spaces, the Mac-only tablet cursor and the measured macOS 15
camera margin. The initial review preserved upstream's Quit bridge (`c56b0a1`).
Upstream advanced during PR publication and replaced that bridge with explicit
MacApplication exit ownership and captured Command-Q handling. Client `d9ad2b1`
merges `86682b5`, retaining that replacement alongside Wacom cleanup/focus and
our display routing. Root `9b495ee` merges `cb01cfe`, including the new mandatory
native suites, runbook and release history. The root integration retains
upstream's dependency caching, build workflow, release notes and signing policy. No `ours`/`theirs` whole-tree replacement,
force push, production branch reset or rewrite of upstream history was used.

Upstream's open clipboard contribution is independent and was not merged.
All five bases were unchanged at the first publication check. The later
root/Client updates above were reconciled after GitHub reported conflicts.
Refresh bases again before final merge.

## What changed, and why

| Area | Change | Evidence and remaining limits |
| --- | --- | --- |
| Experimental build target | Explicit macOS 15 Client target; reject unsuitable SDK/dependency minimums; self-contained ad-hoc development app | ARM64 target, dependency closure, version and signatures checked; distribution signing/notarization remains separate |
| Metal presentation | One decoded canvas supplies two cropped Metal surfaces, each sized in its own backing pixels; toolbar remains on the primary surface | Hardware/software pixel readback and mixed-density geometry tests; longer playback/pacing and display color acceptance remain open |
| Retina geometry | Separate logical desktop size from backing pixels and panel-native modes; use the actual camera-safe fullscreen viewport | macOS desktop-size matching accepted; measured five-point additional margin is limited to macOS 15; Retina-detail end-to-end acceptance remains incomplete |
| Native fullscreen | Native Spaces on both screens; initialize SDL policy before video initialization | Operator accepts fullscreen behavior, hidden menu bars and cross-display interaction; perceived speed improvement is not a benchmark |
| Fullscreen lifetime | Leave/synchronize a secondary Space before hiding it; one-output Mac sessions allocate one surface | Three native AppKit cycles and Metal readback pass; operator accepts dual fullscreen/windowed cleanup; physical single-output live case remains unobserved |
| Mouse routing | Map captured Cocoa drag coordinates across mixed-density windows; enable Cocoa automatic capture | Both-direction held drags accepted |
| Input order | Coalesce only adjacent motion events in SDL and common-C; preserve motion before button/key barriers | Actual native input-worker regression plus live cross-display drags; this intentionally affects shared Client input ordering |
| Follow focus | Transfer focus between owned fullscreen surfaces on hover without interrupting a held mouse drag | Immediate right-click and cross-display drag accepted; local app switching is not replaced by a global focus policy |
| Wacom | Mac IOKit USB raw-HID capture, exclusive ownership, descriptor/report forwarding and protocol control replies; preserve existing device-family allowlist | Pressure and pen focus accepted in earlier exact candidates; later binaries need permission and pressure checks; Bluetooth and general USB passthrough are not included |
| Tablet cursor | Use fresh Host cursor position for tablet focus and a passive Cocoa cursor overlay | Pressure/focus live evidence and report parsing tests; no Host proximity/distance tuning was made |
| Pause/F15 | Map portable Pause separately to Linux `KEY_PAUSE` and `XK_Pause` | Host saw 23 complete Pause pairs; operator confirmed expected Flame action; F15 retains its own mapping |
| Bookmark controls | Preserve Host layout and Native/Scaled-Span controls; add separate Retina size under Match client displays | Existing scaling meanings retained; macOS desktop size versus Retina pixel detail is explicit |
| Automatic matching | Negotiate bounded even-sized modes for physical-startup Hosts; generate temporary real modes and verify XRandR/Mutter/panning | Helper success/failure tests plus actual matched layout tests; no permanent Xorg or global DPI change |
| Primary display | Carry an optional primary index and retain the Host connector assigned to the Client primary | XRandR/Mutter and Flame launch evidence; operator confirmed expected external-display launch |
| Restoration | Save MetaMode and primary property, read back restoration, remove lease-owned modes only after release | Exact restoration and owned-mode removal observed; abrupt-failure/timeout recovery still requires dedicated testing |

## Compatibility and privilege boundaries

- Protocol schema stays at 13. Optional bits `0x400000` and `0x800000` negotiate
  bounded matched modes and primary output. Older Hosts retain preset matching;
  omitted primary negotiation retains existing output ordering.
- The internal supervisor/worker display request becomes `SC-DISPLAY-4`; all
  parts ship together in one Host RPM. Mixed old/new internal workers are not
  an upgrade compatibility promise.
- Headless startup still accepts qualified EDID presets only. Arbitrary even
  dimensions are limited to negotiated physical-startup leases, one or two
  horizontal outputs, at most 8192 canvas pixels in width.
- The display helper runs as the attested desktop owner with fixed executable
  paths and argument arrays. Client input cannot supply shell code or modelines.
  The supervisor retains PAM ownership, lease and restoration responsibility.
- The helper's systemd sandbox permits the attested user's runtime directory
  read-only so Xauthority and the desktop bus can be reached. This permits
  socket interaction as that user; it is not a claim that D-Bus is read-only.
  Home directories remain hidden; network families remain restricted to UNIX.
- Mac raw Wacom requires normal Input Monitoring authorization. No credentials
  are persisted by this contribution and no privacy database bypass is included.
- Authentication, certificate verification, exact video profile negotiation and
  Linux capture/encoder implementations were not replaced.

## Regression review findings

| Finding | Resolution / gate |
| --- | --- |
| Upstream advanced while local development continued | Separate integration branch incorporates current main and preserves the Quit bridge and cache work |
| Cocoa automatic capture had changed every SDL platform | Review Client scopes automatic capture to macOS; Linux retains upstream's disabled setting |
| Native Space exit sequence and one-host-output policy affected Wayland | Review Client limits those policies to macOS and retains upstream Wayland show/fullscreen ordering |
| Dependency cache omitted the new target selector | Cache fingerprints include target policy source and the selected 15.0/27.0 target; tests prove separation and default preservation |
| CI path test compared symlinked and canonical Mac temporary paths | Fixture now resolves the path, matching production behavior; no production path change |
| Intermittent remote left-click loss | Cause unresolved. Relaunch/recovery and released-button traces are evidence of recovery, not a permanent fix; operator parked investigation |
| Shared input queue and Host layout changes have a wider effect than Mac-only code | Explicit Linux build/hardware gates below remain required; Mac acceptance does not clear these gates |

The review is not a guarantee that no regression exists. Native Metal lifetime,
raw-HID hotplug and timeout paths, and Host restoration failure handling remain
the highest-value additional review/test areas. In particular, exercise helper
termination and failed restoration before trusting recovery in unattended use.

## Verification record

Accepted Client 1.0.126 was built from clean root `b0fb4acd` and Client `0f57be38`.
It passed 84 Qt cases, five fullscreen checks, the native input-worker ordering
check, 106 Mach-O target checks, dependency closure and ad-hoc signatures.
The native two-display probe passed three Space exit/hide/reentry cycles and
14 GPU readback cases. Its executable SHA256 is
`f094e779e6ed1f7b390c99fcfd40b70a0d6c159d9c746bff2a4e8d07fdc5db64`.

Host 1.0.125 was built from clean root `7c63f4bd` / Host `d96eb476`. The RPM SHA256
is `243025b6f79ee1b7577047bfdc668f88a59f4668edd041a60d33a7752eac3ac2`.
Twenty display-helper tests, earlier focused Host topology/session tests,
package validation and installed-file comparison passed. Configuration and
certificate hashes were preserved. Live helper trials covered single,
desktop-size and Retina-size layouts with primary identity and restoration.

The review snapshot passes seven portable CTest suites, 38 CI tests and seven
fullscreen/platform guards. New commits in all five repositories pass the
repository privacy checker with checksum-verified Gitleaks 8.30.1 and a private
deployment denylist. These checks cover the proposed commit ranges; they do not
certify unrelated upstream history, private recordings or binary distribution.
Integration package results are recorded in HANDOFF and its artifact manifest.

The clean review build at root `50a05e1` / Client `9c1af82` also passes all 84 Qt
cases, seven fullscreen/platform guards, native input ordering, 106 Mach-O
checks, dependency closure and ad-hoc signatures. Candidate executable SHA256:
`96807fe329b4e24e0a5e6e08785b0f4e831ea0abb853de0f7d6a4d4892a87442`.
It is retained under `artifacts/development/macos15-pr-review/` and has not
replaced the accepted running app. The first fresh-checkout build lacked the
pinned kymux submodule; initializing that exact dependency resolved the build
failure. No product code or dependency pin was changed to bypass it.

The publication-time reconciliation was rebuilt from clean root `9b495ee` /
Client `d9ad2b1` as 1.0.128-macos15-pr-review. All 101 Qt results pass, including
upstream's nine shortcut/eight application-lifecycle results. The native input
worker, seven fullscreen guards, three Quit lifecycle guards, seven portable
suites, 38 CI tests and all 106 Mach-O targets pass. Dependency closure,
build-path checks and ad-hoc signatures pass. Executable SHA256:
`3fcabb629d9c1159921ac22e7ebb4c1f1e37e9bfe7b17d113413c00e0b546802`. Artifact:
`artifacts/development/macos15-pr-publication/`; this build has not been deployed.
New merged Client/root ranges pass privacy checks. The earlier 1.0.127 build
remains historical evidence and is not the current PR-head binary.

## PR structure and merge order

Five linked **draft** PRs are open; do not merge the root before its dependency commits
are available from the canonical upstream submodule URLs.

1. **[common-C #3](https://github.com/instinctual/plank-common-c/pull/3):** ordered absolute mouse packets (`0c82257`), base `plank/client`.
2. **[libvirtualhid #1](https://github.com/instinctual/plank-libvirtualhid/pull/1):** Pause mapping/tests (`b0cc3c8`), base `plank/main`.
3. **[Client #3](https://github.com/instinctual/plank-client/pull/3):** macOS presentation, input, Wacom and display negotiation; depends
   on common-C. Retains current upstream Quit lifecycle/Command-Q and Retina fixes.
4. **[Linux Host #2](https://github.com/instinctual/plank-host-linux/pull/2):** bounded matching, primary binding and internal request update;
   depends on libvirtualhid and must ship with the root's display helper.
5. **[Root #4](https://github.com/instinctual/plank/pull/4):** coordinated gitlinks, helper packaging, protocol documentation,
   optional Mac target/build gates and evidence; depends on Client and Host.

The two leaf changes are small and independently reviewable. Host and root
display-helper packaging are one deployment unit even though their source PRs
are separate. Do not install a Host submodule build without its matching helper.
Do not change canonical `.gitmodules` URLs to personal forks as a merge shortcut.
Maintainers may choose to separate target support from functional changes further.

Contributor forks and branches were created and pushed in the dependency order
above. All five PRs target the reviewed upstream branches and are draft. Bodies
and publication links are in [pr-drafts](pr-drafts/README.md). No upstream merge,
release or installed-binary change was performed. Initial GitHub inspection reported no conflicts, then root/Client conflicts
appeared as upstream advanced. The publication-time integrations above resolve
that overlap with normal merges. GitHub hosted-build and privacy workflow runs report `action_required` with
no jobs executed; maintainer action and hosted CI remain pending. Local
build/test evidence does not clear dependency or hardware qualification gates.

## Required gates before merge/release

- Rebuild from final exact root/submodule revisions after dependencies land.
- Build Linux Host on Rocky 9.7 and Linux Client on Ubuntu 26.04 using qualified
  builders; test shared motion ordering and existing virtual-display workflows.
- Rebuild the default macOS target and test existing single-display, Mac Host
  matching, native Quit and Wacom behavior on a supported newer Mac. That
  hardware is currently unavailable to this fork's test setup.
- Exercise both Retina options, physical single-output and matched dual-output
  presentation, repeated transitions, primary identity and exact restoration.
- Complete the recovery matrix below. Keep unresolved mouse-click recurrence
  visible; do not silently close it because other tests pass.
- Qualify code signing/permission continuity and actual distribution packaging
  separately from ad-hoc development builds.
- Require independent maintainer review, including the shared input queue,
  Metal lifetimes and authenticated Host lease/sandbox changes.

## Next live recovery matrix

| Scenario | Expected result | Status |
| --- | --- | --- |
| Normal disconnect/reconnect | Both displays and primary recover; audio, clicks and pressure resume; no abandoned lease | Earlier single-display reconnect accepted; current combined case pending |
| Dual fullscreen to windowed | One visible stream window; secondary Space removed | Accepted on 1.0.126 |
| Physical single output to fullscreen | Only target display gets a stream window | Pending live check |
| One output to Match client displays | Correct dimensions/order/primary connector; no old windows | Helper evidence exists; combined recovery check pending |
| Brief transport interruption | Existing bounded reconnect flow recovers or offers clear timeout controls; no held input | Pending |
| Client sleep/wake | Explicit recovery outcome, current display geometry and working input/audio | Pending; coordinate sleep with operator |
| Wacom unplug/replug | Local ownership releases; Host device and pressure recover without Client restart | Pending; physical operator action required |
| Interruption while a button/key is held | Host receives release/cleanup; no stuck state after recovery | Pending controlled fixture |
| Clean/abrupt Client exit | Host restores layout and cleans lease/input resources | Clean restoration observed; abrupt combined case pending |

Use throwaway windows and a saved workspace checkpoint. Start with normal
disconnect and single-output checks, then controlled transport loss. Do not
restart the display manager, reboot the working Host or interrupt unrelated
network applications to simulate a Client connection failure. Reuse the accepted
artifact for baseline checks and compare the integration candidate separately.
