# macOS native video submission

Status: hardware VideoToolbox → Annex-B → existing native QUIC qualification,
plus a short real authenticated ScreenCaptureKit loopback test. Not yet playback
in the ordinary Client or a release package.
The Linux Host, native transport ABI and networking policy are unchanged.

`host/macos/media/native-video.m` accepts one ready HEVC sample with exact
negotiated even dimensions, no frame reordering and a numeric nonnegative PTS.
The converter prepends VPS/SPS/PPS to keyframes and replaces four-byte NAL
lengths with Annex-B start codes in one compressed-buffer copy. It validates
NAL bounds/header fields, VCL presence and sync/IRAP agreement. It rejects
malformed or oversized data (64 MiB, matching the transport ceiling).
This parsing does not independently prove SPS color/bit-depth semantics; the
encoder contract and exact-profile Client decoder gate remain required.

Pixel buffers are not mapped, scaled, converted or downloaded by this adapter.
There is one application compressed-data copy for conversion and another copy
owned by the native transport enqueue. Do not call this zero-copy networking.
The qualification test alone CPU-fills a synthetic x420 surface; that is not a
change to the qualified IOSurface-based capture/encoder input path.

The serial capture owner supplies an activated authentication lease and a
borrowed native endpoint. There is no additional thread or private frame queue.
PTS becomes microseconds, frame numbers start at one, and host-processing
latency retains the existing ABI's tenths-of-millisecond unit. Duplicate or
decreasing timestamps are rejected. Native enqueue is ordered against explicit
lease revocation; no later submission succeeds after completed revocation.

The sender starts in needs-keyframe state. Native receiver recovery requests
must call `requestKeyFrame` on the same serial queue. The owner must force the
next VideoToolbox keyframe while `needsKeyFrame` is true. Dependent frames are
withheld and their frame numbers counted. A native send-queue replacement also
requests a subsequent keyframe; the transport's DROPPED return means it replaced
an older queued frame, not that the current frame was never enqueued.
No retry queue is added. Fatal conversion/transport failures require teardown.

The owner must stop submissions and release the adapter before destroying its
endpoint. The adapter also invokes the owner's topology-validity predicate before
conversion and enqueue. Session revocation alone does not stop SCK or destroy
sockets; the coordinator below owns that responsibility.

## Capture and stream owner

`preview-session.m` validates the exact launch tuple, claims authorization and
creates one native endpoint. A 20-ms dispatch source on its serial queue checks
authorization/topology/endpoint state and drains at most eight native control
records per tick. No per-frame timer or blocking receive thread is added.
Only authenticated QUIC READY activates capture. Startup has a five-second
deadline; a static desktop's idle callbacks do not cause ordinary disconnection.
Capture is driven by SCK rather than a synthesized 60-Hz timestamp sequence.

Disconnect, desktop/topology replacement, invalid controls, startup failure or
explicit revocation first revoke the lease, then close the native endpoint.
Capture/encoder callbacks drain before endpoint memory is released. If a
framework stop callback stalls, QUIC still closes; the owner remains Stopping
instead of claiming successful cleanup. Machine-service recovery for permanently
hung Apple APIs remains a release gate. Abandoning an owner also revokes and
queues capture drain without a dangling endpoint pointer.

`screen-capture.m` requires existing TCC consent, selects the exact display,
checks SCK's actual pixel geometry and retains at most three encoder submissions.
It requests x420 IOSurfaces, hardware-required HEVC Main10, no reordering, and
the speed-priority property qualified against mixed idle/motion in probe 42.
It preserves actual SCK timestamps. The provisional SDK-27 x420 source contract
is BT.601 matrix/sRGB; VideoToolbox produces limited BT.709/sRGB output. This
must be requalified against final macOS 27 and representative content.
No CPU pixel map/download/color conversion is introduced. The output cursor is
embedded in pixels for this video-only preview; audio and input remain absent.

The bookmark supplies bitrate; live control updates both VT and native QUIC.
VT's one-second data-rate ceiling is twice the target, and that ceiling is also
reported as the transport peak budget. It is not a one-second application queue
or a constant instantaneous rate guarantee. Quality and latency with this ceiling
need longer content tests. Host-processing metadata currently measures encoder
submission through transport enqueue, not glass-to-glass or SCK capture age.

## Qualification

`scripts/build-macos-native-video.sh` builds with SDK/minimum 27 and warnings as
errors using the retained verified native Rust archive. It tests actual hardware
HEVC Main10 at 1080p and 2160p through actual native QUIC loopback. Each case
encodes 12 synthetic frames, deliberately withholds one dependent frame, then
receives 11 byte-identical payloads, including a forced recovery keyframe.
It checks timestamps, frame-number gaps, latency, malformed sample rejection,
pending-lease rejection, duplicate timestamps and desktop revocation.

Synthetic test authentication is linked only into this standalone binary; it
has no real desktop capture, external listener or product bypass. Ephemeral TLS
uses exact certificate pinning and the lease's random in-memory token. A 30-second
alarm bounds each case. Private keys are removed by the runner. Only synthetic
keyframes are retained for independent FFmpeg decoding/color inspection.

These checks prove integration and recovery ordering, not sustained 60-fps
performance, packet-loss tolerance, hardware Client decode/presentation, input,
audio or the required LoginWindow lifecycle.

The additional lifecycle suite uses a synthetic capture implementation but actual
native QUIC. It covers invalid tuples, peer/replay rejection, live bitrate/PLD1
acknowledgement, disconnect, authority/topology loss, bad controls, startup
failure/timeout, launch-delivery cancellation, owner abandonment and delayed
capture drain. Authenticated HTTPS qualification checks launch validation and
replay too. The real Aqua variant has received live HEVC frames, applied a bitrate
change and disconnected cleanly, without storing any desktop pixels.

## Ordinary Client integration — remaining gates

The Client has a typed schema-1 request/manifest helper and common-c now has
explicit service flags. The Linux PLS1 response still requires audio and local
cursor support; its caller selects audio/input/local-cursor. The Mac manifest
selects none of those services, while retaining the documented bitrate control.
Common-c skips absent audio/input workers and balances failure cleanup. The Qt
Client also skips the native audio receiver when audio was not negotiated.
These changes pass standalone state-machine/manifest tests and a full
uninstalled Ubuntu Client build. They do **not** remove the Mac readiness gate.

Complete these boundaries before making a testable Client candidate:

1. Add authenticated `NvHTTP` POST `/plank/launch`, keeping credentials/tokens out
   of URLs/logs and preserving the authenticated TLS leaf fingerprint for QUIC.
   Consume the HTTP token on launch; do not redirect or automatically retry the
   one-shot request. Validate the manifest before starting the native endpoint.
2. Feed the fixed capture's **pixel** dimensions into Session decode and
   presentation geometry, not its logical-point bounds or the Client monitor's
   resolution. Do not invoke Linux host-layout mutation for this capture.
3. Use the manifest's exact Main10 profile for decoder qualification and local
   SERVER_INFORMATION. Public discovery's zero capabilities remain honest;
   only authenticated launch establishes this experimental stream capability.
4. Skip the Linux PLS1 setup exchange for this typed preview only. Do not bypass
   Linux's response checks or local-cursor requirement globally. Avoid the
   current unconditional audio-device test for this explicit video-only launch.
5. Keep the compositor cursor and toolbar locally usable, disable remote input
   forwarding for the preview, and accept the cursor embedded in captured
   pixels without waiting for separate cursor events. Do not start raw-HID
   forwarding or hide the local pointer on the strength of a platform name.
6. Qualify failure/cancellation, disconnect, reconnect with fresh authorization,
   topology replacement, real decode/presentation and live bitrate control.
   The Mac runner is still loopback-only; expose only a deliberate authenticated
   development listener for the actual Client test, not public discovery flags.

Only then remove the early Mac Session gate, build a new versioned DEB on
linux-client-builder, and install that exact artifact on the authorized test target.
Audio, general input and LoginWindow transitions remain subsequent Mac product
gates, not capabilities supplied by this video-only preview.
