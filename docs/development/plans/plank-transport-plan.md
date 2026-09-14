# PlankTransport single-port transport experiment

## Status and isolation

`plank_transport` is an experimental, intentionally incompatible transport branch.
It starts from the annotated root tag `08.28_23` and these exact clean tips:

- root: `1e989068109e4050641960bf4f436d8ce5d5f93d`
- Host: `3b574f89aa33a0fb9a97bb03c4f9c1e77b275eff`
- Client: `870f68097ef7538bfc986e6c835b835172a1d8f1`

The root, Host, and Client repositories each have a pushed `plank_transport`
branch. Nothing from this experiment may be merged into `main` until the
acceptance gates below pass. Experimental packages and the client banner must
include `plank_transport` in their version so they cannot be confused with an
accepted PLANK build.

As of `.197.plank_transport`, the user has approved an intentionally incompatible
native-only cut and its first deletion candidate is implemented. The temporary
A/B selector is gone, Client audio/video can only enter through complete
KyProto-reconstructed frames and Opus packets, and the Host no longer binds the
superseded ENet control or GameStream video/audio data-plane listeners. The
remaining compiled legacy control and Host packetization implementation is a
separate bounded deletion; it is not a fallback or supported runtime mode.
HTTPS/PAM/display, RTSP setup, encoding-profile negotiation, and the decoder's
recovery/callback workers remain until they have explicit native replacements.

### True single-UDP-port control-plane cut

The accepted next architecture removes the remaining TCP HTTPS and RTSP
listeners. A PLANK connection starts and remains on one KyProto/QUIC
connection to the configured UDP port. The reliable data endpoint is created
first and carries the pre-session control exchange. Video, audio, and input
endpoints are not registered until that exchange has completed successfully.
This is one network socket and one QUIC connection, not TCP and UDP sockets
that happen to share a number and not a tunnel around the old protocols.

The pre-session exchange preserves the product security and ownership rules:

1. the Client completes a TLS 1.3 QUIC handshake and validates the received
   leaf certificate against the existing PLANK certificate profile;
2. no username, PAM response, input, or media is sent before certificate
   profile validation succeeds;
3. PAM challenge/response runs for every launch and delegates authorization to
   PAM/SSSD/FreeIPA, including the configured root-login policy;
4. the Host verifies active-desktop ownership, display topology, capture and
   encoding profile, and launch parameters;
5. only then do both peers promote the same connection by registering the
   KyProto video, audio, and input endpoints.

Certificate profile validation deliberately retains the existing product
model: no pinning, TOFU, persistent client trust, or client certificate is
introduced. The transport wrapper must fail closed before application secrets
or privileged messages can be queued. Short-lived availability queries use
the same certificate-gated reliable setup endpoint and close without promoting
the connection. An active launch keeps that connection and promotes it; it
does not reconnect through a second data-plane handshake.

The initial setup message family is bounded and versioned. It covers server
information, PAM start/challenge/response/result, display topology, launch,
session-ready, and structured error records. The reliable setup lane uses
strict request identifiers and a 64-KiB maximum record. Passwords and PAM
responses are transient, are never persisted or logged, and must be cleared
from owned buffers as soon as the response is submitted.

Standalone Stage 1 is complete. The probe and its two-machine saturation,
loss, role-authentication, and bounded-scheduler gates pass. Stage 2 added the
PLANK-owned Rust library, C ABI, authenticated product lifecycle, and
explicit per-bookmark A/B selector. Stage 3 now carries complete existing
encrypted video/FEC and audio/FEC packets over the plank_transport media connection.
The first interaction slice moves only the live bitrate request; input, cursor,
telemetry, setup, and Host-to-client control remain on their qualified paths.

## Purpose

Replace PLANK's externally visible multi-port GameStream transport
with one configured UDP port carrying native KyProto/QUIC setup, input, audio,
video, events, and telemetry. The final firewall surface is one UDP rule. The
eventual design removes the TCP HTTPS/RTSP listeners and every legacy ENet/RTP
listener rather than retaining a same-number TCP compatibility plane.

## Kyber provenance and license

The experiment may reuse Kyber components under AGPL-3.0-or-later. Preserve
Kyber copyright notices, license files, repository provenance, and source
availability. Kyber source must remain pinned to an exact commit. Do not copy
unattributed fragments or silently absorb Kyber history into a PLANK
file.

The first proof uses Kyber's `kynet`/Quinn transport and endpoint-routing
concept. PLANK retains its qualified packet formats, extended FEC,
profile negotiation, color pipeline, telemetry definitions, and input device
semantics. Kyber's fixed FEC and fully reliable input policy are not accepted
by implication.

## External architecture

The initial hypothesis was one mutually authenticated QUIC connection per
active PLANK session. Periodic-burst testing showed unacceptable
coupling between media congestion and reliable input, so Stage 1 must also test
two authenticated QUIC connections on the same UDP port: one for media and one
for interaction. This preserves the one-port firewall goal because QUIC
connection IDs demultiplex both through one server endpoint. The split is not
accepted architecture until it passes the same loss tests.

A short-lived bearer token issued by the authenticated HTTPS control plane
binds every QUIC connection to the accepted desktop owner and launch request.
The HTTPS response also supplies the expected certificate identity so the
data-plane connection cannot be redirected independently. Each connection's
authentication identifies its role, and a session may have at most one active
connection of each negotiated role.

The first QUIC bidirectional stream authenticates the session and negotiates
the transport version, feature set, maximum application datagram size, and
logical endpoints. Endpoint identifiers are scoped to the authenticated QUIC
connection and may never be reused within it.

Initial logical endpoints are:

| Endpoint | Direction | Delivery policy |
| --- | --- | --- |
| session control | bidirectional | reliable stream |
| critical input | client to Host | reliable stream |
| replaceable input motion | client to Host | sequenced datagram |
| raw-HID Wacom reports | client to Host | sequenced datagram plus reliable state transitions |
| cursor shape/state | Host to client | reliable stream |
| cursor position | Host to client | sequenced datagram |
| video | Host to client | datagram with PLANK FEC |
| audio | Host to client | sequenced datagram |
| telemetry | bidirectional | reliable stream or replaceable datagram by metric |

The initial integration keeps the current single encoded video canvas. A
future experiment may allocate one video endpoint per Host display, but that
must not be combined with the first transport replacement.

## Scheduling and backpressure

Sharing a QUIC connection must not allow a video burst to delay control,
input, or audio. Application scheduling order is:

1. disconnect and session control;
2. critical keyboard, button, and pen-state transitions;
3. current pointer and pen motion;
4. audio;
5. cursor updates;
6. video;
7. non-urgent telemetry.

Only bounded queues are allowed. Replaceable motion and cursor-position
queues hold the newest state, not a history. Video must drop work before
building latency, following the existing PLANK acquisition/drop
policy. QUIC congestion feedback must never silently rewrite the bookmark or
toolbar encoder target.

## Input invariants

Keyboard transitions, mouse button transitions, pen tip transitions, pen
button transitions, configuration changes, and disconnect commands must not
be lost. Mouse and pen position reports are replaceable by a newer report.

Raw-HID Wacom forwarding needs an explicit transition safeguard because a HID
report can combine position, pressure, tip, and buttons. The experimental
transport must either duplicate state-changing reports on the reliable input
endpoint or acknowledge/repeat them until a later report proves the same
state. It must preserve the existing device identity, pressure, Tablet
Margins, suspend/reattach lifecycle, and Flame cursor behavior.

## Datagram and MTU invariants

QUIC DATAGRAM payloads must fit the transport's reported maximum datagram size
and the PLANK configured/path MTU after IP, UDP, QUIC, endpoint, media,
and FEC headers. Do not rely on IP fragmentation. FEC shard sizing is derived
from the resulting payload budget rather than a hard-coded Ethernet MTU.

Automatic mode derives this policy from the route selected for the active
bookmark, not from the destination address class. The Client opens the selected
Host address, asks the kernel which local source address was chosen, and matches
that address to its network interface. An exact Linux
`ztXXXXXXXX` interface name or a human-readable name beginning with
`ZeroTier` selects the qualified ZeroTier policy. Other virtual/VPN interfaces
remain classified as VPNs for unrelated behavior but do not inherit ZeroTier's
encapsulation assumptions. The classification is repeated for each new
connection so route changes do not persist in bookmark state.

An administrator or user can instead set a global manual override in Client
Network Settings. Its value is the exact maximum complete QUIC UDP payload,
excluding outer IP and UDP headers, and is applied on every route. This direct
transport value avoids the ambiguity of the retired physical-MTU-to-GameStream-
packet-size calculation. Zero selects Automatic; explicit values must be from
1200 through 65527 bytes and must fit the known interface budget below.

For both Automatic and manual settings, the selected interface's current MTU
is read on each connection. Subtract 28 bytes for IPv4/UDP or 48 for IPv6/UDP,
then the existing 20-byte safety margin. Automatic takes the smaller of that
budget and its route ceiling (1344 for ZeroTier, 1452 otherwise). For example,
ZeroTier MTU 1310 selects 1262 bytes on IPv4 or 1242 on IPv6; MTU 2800 retains
1344. A manual override may replace the automatic ceiling but cannot exceed
the known interface budget. An unavailable MTU retains the previous fallback:
1344 for identified ZeroTier, 1200 otherwise, or the valid manual override.

A known interface below 1248 bytes (IPv4) or 1268 (IPv6) cannot fit QUIC's
1200-byte minimum plus this safety policy. Reject it before launching the Host
session, with a clear error; do not clamp up to 1200 and send oversized packets.
An oversized manual setting is also rejected. The selected size stays fixed
for the connection. This is an interface-based ceiling, not end-to-end path
MTU discovery: smaller downstream limits still require administrator handling.

Regression coverage lives in Client `tests/planknetwork` (data rows and an
exhaustive interface-budget invariant) and root
`tests/packaging/test-client-interface-mtu.py` (launch/transport wiring).
The existing native FFI loopback runner accepts
`PLANK_LOOPBACK_CLIENT_MTU=1262` to exercise media/FEC and control with a smaller
Client-advertised limit while leaving the server policy unchanged. Its final
peer-closure assertion is a separate lifecycle gate; report any failure rather
than treating successful media delivery as a complete suite pass.

On the qualified ZeroTier 1.16.2 route, the physical UDP payload boundary is
1432 bytes and an extended ZeroTier frame consumes 51 bytes beyond the inner
IPv4/UDP packet. The Client therefore advertises and probes no more than a
1344-byte complete QUIC UDP payload (or less on a smaller interface):

- `1344 + 28 + 51 = 1423` bytes on the physical ZeroTier UDP payload, leaving
  nine bytes below the observed boundary;
- up to 1306 bytes remain after a conservative 38-byte QUIC DATAGRAM budget;
- KyProto's 26-byte video FEC header then leaves a 1280-byte RaptorQ symbol.

The fixed ceiling is applied to the Client's Quinn endpoint and to its QUIC
`max_udp_payload_size` transport parameter. The latter also limits Host-to-
Client packets, so the server does not need to infer the Client's route. Zero
in the versioned transport ABI retains Quinn's default policy, but rejected
Client settings must never reach that ABI as zero. Values below
1200 or above 65527 are rejected. The retired Client physical-MTU preference
is replaced by the exact QUIC-payload override; common-c
`packetSize`/`streamingRemotely` fields are not part of the native transport
and must not be restored.

The toolbar's `Incoming video packet loss (before FEC)` remains a video-layer
measurement. QUIC connection loss includes packets belonging to other logical
endpoints and is a separate diagnostic metric.

## Implementation stages

1. Build a standalone loopback and two-host QUIC probe. It must authenticate,
   multiplex reliable streams and datagrams, report negotiated datagram size,
   sustain at least 150 Mbps of synthetic video traffic, and prove that
   critical input remains bounded during saturation and loss.
2. Add an explicit experimental data-plane selection for qualification. This
   temporary A/B stage completed at `.193.plank_transport` and is superseded by the
   approved native-only cut.
3. Carry the existing video, audio, control/input, cursor, and telemetry
   payloads over QUIC while retaining the current HTTPS and RTSP setup.
4. Qualify the data plane against the existing PLANK baseline.
5. Replace RTSP setup with authenticated HTTPS session endpoints and retire
   the obsolete external listeners on the experimental branch.
6. Remove the A/B path on `plank_transport` while preserving `main` and the
   `08.28_23` rollback tag. Merge only after the native-only acceptance matrix
   passes.

## Stage 1 evidence

The probe pins Kyber `kymux` release `0.28.0` at commit
`10e96fafba59ff0327afb3d0ac0cb5f3c77bd664`. Its resolved Quinn set is
`quinn 0.11.11`, `quinn-proto 0.11.17`, and `quinn-udp 0.5.15`.

The released `quinn-proto 0.11.17` aborted the first 5 percent loss run because
its DATAGRAM send-buffer refactor could both omit the newly queued datagram
from its capacity check and decrement buffered payload bytes twice while
pruning. The probe now uses an auditable vendored copy of that exact crate with
the narrow accounting backport, original licenses, crates.io VCS provenance,
and a focused regression test. It does not upgrade Kyber to Quinn's unreleased
0.12 API.

Two-machine tests sent a paced 150 Mbps synthetic video lane and 200 Hz audio
from hardware-test-host to the Development NUC, while the client sent 1 kHz replaceable
motion and 200 Hz reliable critical input. Loss was independently random and
applied only to the exact Host-to-client UDP probe flow. Results were:

| Controller | Loss | Delivered video | Critical-input p99 | Result |
| --- | ---: | ---: | ---: | --- |
| CUBIC | 0% | 149.99 Mbps | 1.63 ms | complete |
| CUBIC | 1% | 148.61 Mbps | 2.86 ms | complete |
| CUBIC | 5% | 86.71 Mbps | 29.05 ms | complete after accounting fix |
| CUBIC | 10% | 33.87 Mbps | 44.46 ms | complete after accounting fix |
| BBR | 5% | 140.16–140.22 Mbps | 6.81–11.79 ms | complete twice |
| BBR | 10% | 133.21 Mbps | 18.29 ms | complete |

The BBR delivered rates closely track the maximum possible after the injected
drops (142.5 and 135 Mbps). Upstream Quinn labels its BBR implementation
experimental, so these results qualify it for continued investigation rather
than product acceptance. The probe's explicit `quinn-bbr` feature selects it;
disabling default features restores the upstream CUBIC control run.

Periodic bursts are materially harder than independent random loss. At a
nominal 5 percent periodic burst, BBR delivered 139.40 Mbps with 11,405 video
and 143 audio sequence gaps, no stale datagrams, and 94.90 ms reliable-input
p99. At a nominal 10 percent periodic burst, it delivered only 89.24 Mbps with
65,355 video and 800 audio gaps, no stale datagrams, and 1.625 seconds
reliable-input p99. All 2,001 critical events ultimately arrived in both runs,
but that latency is unacceptable. A single shared QUIC connection is therefore
not qualified.

The next Stage 1 experiment is a media/interaction connection split on the same
UDP port. That split passed the identical tests:

| Layout | Periodic burst | Delivered video | Critical-input p99 | Video/audio gaps | Stale state |
| --- | ---: | ---: | ---: | ---: | ---: |
| one connection | 5% | 139.40 Mbps | 94.90 ms | 11,405 / 143 | 0 |
| two connections | 5% | 140.38 Mbps | 7.81 ms | 10,005 / 125 | 0 |
| one connection | 10% | 89.24 Mbps | 1,625.22 ms | 65,355 / 800 | 0 |
| two connections | 10% | 133.35 Mbps | 8.45 ms | 17,340 / 198 | 0 |

All 2,001 reliable critical-input records completed in every run. At 10
percent, the interaction connection independently reported 727 lost packets
without inheriting the media connection's 15,649 lost packets or congestion
window. The split preserved the expected post-loss media rate and reduced p99
input latency by about 192 times compared with one connection.

The two-connection/single-port layout is now the leading Stage 1 architecture,
and its first security gate passes. Connection role is an explicit protocol
field, either role may arrive first, and the server rejects duplicate media,
duplicate interaction, unknown role, invalid token, and mismatched
cross-session-token connections before lane startup. It still needs bounded
application queues and explicit audio/video scheduling tests; those are the
next gate below.

The bounded media scheduler gate also passes. Its fixed capacities are 64
video datagrams and eight audio datagrams, audio is always dequeued first, and
overflow evicts the oldest queued item in that lane. Unit tests prove capacity,
freshness, and priority. At 150 Mbps loopback the queue high-water was 22
packets with no eviction. At 10 percent periodic burst across hardware-test-host and the
Development NUC, the high-water was 33 packets (about 2.1 ms of 1,200-byte
video), application audio/video drops remained zero, delivered video was
133.02 Mbps, input p99 was 8.57 ms, and all 2,001 critical events arrived.

The user-requested 200 Mbps headroom qualification also passes across hardware-test-host
and the Development NUC. This is a transport stress ceiling above the current
150 Mbps product control range; it does not change that range. All cases used
the two-connection layout, BBR, a 10-second run, and the deterministic
periodic-burst pattern for nonzero loss:

| Injected loss | Delivered video | Critical-input p99 | App video/audio drops | Queue high-water | Critical records |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0% | 197.33 Mbps | 1.71 ms | 0 / 0 | 32 | 2,001 / 2,001 |
| 5% | 187.59 Mbps | 8.07 ms | 0 / 0 | 44 | 2,001 / 2,001 |
| 10% | 177.24 Mbps | 8.63 ms | 0 / 0 | 45 | 2,001 / 2,001 |

The 5 and 10 percent delivered rates remain close to their nominal 190 and
180 Mbps post-loss ceilings. The worst 45-packet high-water is about 2.2 ms of
1,200-byte video at 200 Mbps, remains below the fixed 64-packet bound, and did
not cause stale delivery or application eviction.

Stage 1 is therefore complete as a standalone proof. This does not qualify BBR
or QUIC for production: Stage 2 must retain an explicit A/B data-plane choice,
carry the real PLANK payloads and FEC, and reproduce the same evidence
before any old listener is removed.

## Stage 2 integration boundary

`protocol/plank-transport` is the PLANK-owned Rust boundary
around pinned Kynet/Quinn. Its versioned C ABI uses an opaque endpoint handle,
copies all configuration at creation, owns its Tokio runtime and worker
threads, exposes synchronous start/wait/state/stop/error operations, and never
calls C++ while holding a Rust transport lock. This keeps Rust async ownership
out of the Host and Client event loops.

The first boundary implementation establishes and holds the two authenticated
roles on one UDP listener but intentionally carries no product payload. A real
C11 caller passes the public header, links the release static library,
establishes both roles with certificate pinning, observes both endpoints in
`READY`, and tears them down cleanly. The original saturation probe imports
the same authentication implementation and continues to pass its 150 Mbps
loopback and complete role-security matrix.

The Host and Client link this library directly. The temporary per-bookmark
`legacy`/`plank_transport` selector served its A/B qualification purpose through
`.195.plank_transport` and is now removed: protocol version 10 requires the native
PlankTransport path. An authenticated launch returns a per-launch random token and
the TLS leaf-certificate SHA-256 fingerprint, then establishes both
role-authenticated QUIC connections. The endpoint lifetime follows the stream
session and is stopped on disconnect, failed launch, and reconnect. Launch
credentials are never persisted or written to the log.

The original Stage 2 candidate was deliberately handshake-only. Protocol 10
and `.197` are now native-only: video, audio, input, cursor/HDR events,
recovery, bitrate control, liveness, and termination use KyProto. Client legacy
media receivers and the Host's legacy data-plane listener startup are deleted.
RTSP remains only as session setup, while common-c recovery and callback
workers retain the existing decoder contract.

The first real package A/B is complete with `0.1.0-0.184.plank_transport`. The Host
and Development NUC Client established both authenticated roles on UDP 47989,
then ran the unchanged 3840x2160x60 legacy payload path at about 59.8 rendered
FPS with zero reported packet loss and clean endpoint teardown. The candidate
also includes a regression gate for conventional DER certificate SHA-256 byte
order after the preceding candidate exposed an inherited reverse-order hex
formatter.

The user manually installed the same candidate on the End-User NUC. The first
WAN attempt proved that HTTPS launch could succeed while the routed ZeroTier
firewall still filtered UDP 47989: a comparative UDP 47998 probe arrived at
hardware-test-host while a UDP 47989 probe did not. After the user allowed UDP 47989, both
authenticated plank_transport roles reached `READY`. At a 150 Mbps encoder target,
the unchanged legacy media path sustained about 140.1 Mbps across a ten-second
ZeroTier sample with no local interface drops. This remains coexistence and
lifecycle evidence only; no product payload is carried by QUIC yet. The host
RPM firewalld service now explicitly declares both TCP and UDP 47989, with a
packaging regression assertion, while administrator-managed routed-network
policy remains outside the package.

## Stage 3 video-lane evidence

Candidate `0.1.0-0.186.plank_transport` carries each complete existing encrypted
video/FEC packet inside one QUIC DATAGRAM. The Rust boundary does not parse,
repacketize, decrypt, or regenerate FEC. The initial UDP 47998 association ping
remains so the unchanged RTSP/GameStream setup can complete, but packet capture
proved that real video bytes moved to UDP 47989: an eight-second sample saw 998
media packets and 1,993,421 payload bytes on UDP 47989 while UDP 47998 carried
only 15 fixed 20-byte association packets.

The first `.185` real stream revealed that a 64-packet Host submission queue
could be filled by a single 4K IDR/FEC burst. It dropped 31 packets at startup,
causing one recoverable startup-frame failure despite zero QUIC loss. `.186`
raises only that C-ABI handoff queue to 512 complete packets, still below 1 MiB
at the negotiated packet size. The standalone media scheduler remains bounded
at 64 datagrams; this is not a request to accumulate congestion latency.

A matching `.186` Host and Development NUC Client then completed a 90-second
3840x2160x60 NvFBC-to-NVENC HEVC 10-bit 4:4:4 identity session with a 150,000
Kbps requested/applied target and 225,000 Kbps permitted encoder peak. The
static test image encoded at only about 0.65 Mbps, so this validates the maximum
control setting and real product packet-burst behavior rather than sustained
150 Mbps content. End-of-session counters matched exactly at 15,521 packets
and 20,860,224 bytes. Host submission drops, transport-send drops, Client
receive drops, QUIC packet loss, FEC recovery, and unrecoverable FEC were all
zero; Host queue high-water was 77/512 and Client receive high-water was 25.

The separate 10-second 200 Mbps saturation probe delivered 199.989 Mbps over
the same split-connection Kynet/Quinn design. It carried 208,322 video packets,
2,001 audio packets, 10,001 motion samples, and all 2,001 critical-input
records with zero application drops, zero sequence gaps, zero stale state,
zero QUIC loss, and 0.127 ms critical-input p99 on loopback. This remains a
transport headroom gate; the product control maximum remains 150 Mbps.

The user visually accepted `.186` on the End-User NUC. The observed one-output
hardware-test-host launch was not a plank_transport display regression: its launch request logged
`policy=match-client`, resolved one 5120x2160 client display to `single`, and
used the exact bitrate stored in the separate `hardware-test-host-NG` bookmark. After that
bookmark was changed to `physical`, both hardware-test-host physical displays worked
properly. Host discovery continued to report the expected 3840x2160 plus
1280x2160 outputs.

## Stage 3 audio-lane evidence

Candidate `0.1.0-0.187.plank_transport` carries each complete existing encrypted
audio RTP or audio-FEC packet inside the media QUIC connection. The Rust
boundary preserves the packet bytes and uses a separate eight-packet audio
queue ahead of video's bounded queue. The existing UDP 48000 association ping
remains only for unchanged RTSP/GameStream setup; no audio payload is sent on
that socket when plank_transport is active.

The versioned transport ABI is now version 3. Its media scheduler identifies
video as lane 1 and audio as lane 2, always dequeues audio before video, and
reports independent packet, byte, drop, and queue-high-water counters. The C
FFI loopback byte-validates one audio packet and two video packets, including
per-lane statistics. Eight Rust tests, strict Clippy, the C FFI loopback, the
Host and Client package gates, and the full 16/16 root qualification suite
pass.

A real 80-second Development-NUC-to-hardware-test-host session used a 3840x2160x60 NvFBC
8-bit-source/up-converted to NVENC HEVC 10-bit 4:4:4 identity path. Host and
Client teardown counters matched exactly at 13,753 video packets / 18,484,032
bytes and 21,715 audio packets / 7,643,676 bytes. Both audio queue high-water
marks remained small (Host 3/8, Client 6/64); audio submission, transport,
receive, and video receive drops were zero. QUIC reported zero lost packets.
The client sustained 59.96 network, decode, and render FPS with zero FEC loss
or recovery.

A bounded ten-second packet capture observed 2,397 Host-to-client and 1,109
client-to-Host QUIC datagrams on UDP 47989. UDP 48000 contained only nineteen
client-to-Host 20-byte association pings at roughly 500 ms intervals and no
Host-to-client media packets. This proves the new audio payload lane is using
the selected single data port while setup compatibility remains unchanged.
The user confirmed that audible output and observed A/V behavior are good.
This closes the audio gate for the next narrow interaction slice; the later
long-duration drift and RSS acceptance gates still apply before a merge.

## Stage 3 interaction-control foundation

Candidate `0.1.0-0.188.plank_transport` raises the versioned transport ABI to 4 and
adds bounded reliable client-to-Host control records on the independent
interaction QUIC connection. Each record carries one complete existing
encrypted GameStream control packet. The client queue holds 64 commands,
never evicts an accepted command, and returns explicit backpressure when full;
Host receive overflow fails the connection closed. A 64 KiB record limit and
fixed magic/length framing bound memory and reject malformed or truncated
records.

The initial product integration diverts only `IDX_SET_VIDEO_BITRATE` after the
existing control packet has been encrypted. The Host submits the reconstructed
packet to the same decrypt, range-validation, encoder-update, and applied-rate
acknowledgement handlers used by ENet. Keyboard, mouse, Wacom, cursor,
telemetry, control acknowledgements, and every other control message remain on
their existing paths. Ten Rust tests, strict Clippy, and a real C FFI loopback
that byte-validates video, audio, and reliable control pass.

Clean `.188.plank_transport` Host and Client packages passed all package gates and
were installed on hardware-test-host and the Development NUC; the user manually installed
the matching Client on the End-User NUC. A 4-minute-55-second 5120x2160x60
session applied eight toolbar changes spanning 50.5 to 150 Mbps. Including the
initial 50 Mbps request, the reliable interaction path delivered exactly nine
records / 288 bytes, with zero send-full events, zero receive overflow, queue
high-water one, and zero interaction-connection QUIC loss. Every requested
value reached the existing Host validation/encoder path and returned the
matching legacy applied-rate acknowledgement. The final 111.5 Mbps setting was
confirmed as a 111500 Kbps target and 167250 Kbps peak.

Media application counters also reconciled exactly at both endpoints:
1,396,189 video packets / 1,787,121,920 bytes and 74,397 audio packets /
26,187,732 bytes, with no media queue drops. The Host transport reported 105
recovered media QUIC losses, but every submitted application packet arrived
and the Client's final pre-FEC loss statistic was 0.00 percent. Explicit
disconnect stopped both connections cleanly. The full root qualification suite
passes 16/16. This accepts the first interaction slice. Next, carry the
bitrate-applied acknowledgement on the reverse reliable interaction direction
before moving any keyboard, mouse, or Wacom traffic.

Candidate `0.1.0-0.189.plank_transport` makes the interaction framing bidirectional
and moves that one existing bitrate-applied acknowledgement to the reverse
Host-to-client direction. It does not add a second parser: the common-c control
receive thread polls the external receiver and submits the complete encrypted
packet to the existing decrypt, sequence validation, asynchronous callback,
and toolbar-confirmation path. Both roles run their reliable sender and
receiver concurrently on the same bidirectional interaction stream. The ABI
is version 5; both directions retain 64-record bounded queues and fail-closed
overflow behavior.

A 2-minute-33-second 5120x2160x60 End-User session applied the initial 50 Mbps
target and toolbar changes to 150 and 52.5 Mbps. Client-to-Host counters
matched exactly at three records / 96 bytes, and Host-to-client counters
matched at three acknowledgements / 120 bytes. Both send/receive queue
high-water marks were one; send-full, receive-overflow, and interaction QUIC
loss were zero. The Client logged all three exact requested/applied/peak
triples. Media counters also matched exactly at 527,312 video packets /
674,959,360 bytes and 38,965 audio packets / 13,715,676 bytes with no
application queue drops. Client pre-FEC loss and video FEC recovery were zero,
and explicit toolbar disconnect stopped both connections cleanly. Ten Rust
tests, strict Clippy, the bidirectional C FFI loopback, clean package gates,
and the full 16/16 root qualification suite pass.

This accepts the bidirectional bitrate request/ack pair. The next narrow slice
is the remaining non-input control/recovery family: IDR requests,
reference-frame invalidation, loss reports, and the minimum stream-health
messages required to preserve their ordering. Keyboard, mouse, Wacom,
raw-HID, and cursor traffic remain on their qualified transports until a
separate latency-focused stage.

## KyProto-native conversion checkpoint

The user approved replacing the transitional encrypted GameStream packet
tunnel with Kyber-native protocols before merging this branch. ABI/protocol 6
uses one authenticated KyProto connection with stock Quinn congestion control,
`VideoProtocol::UnreliableFec`, `AudioProtocol::UnreliableFec`, reliable input,
and reliable data. Kyber owns media packetization, RaptorQ, ordering, and QUIC;
PLANK does not add RTP, media AES, or Reed-Solomon to native video or
audio.

The first synchronized product slice branches the Host at complete encoded
H.264/HEVC Annex-B frames and raw Opus packets. The Client submits KyProto's
reconstructed frames and packets directly to the existing decoder and audio
renderer. Existing capture, encoding, exact profile/color negotiation,
decoding, presentation, PAM, display management, input, and cursor semantics
remain unchanged. The bitrate request and acknowledgement use KyProto reliable
data; remaining recovery/control and input traffic is still transitional.

The wrapper uses bounded queues and independent wakeups for video, audio,
input, and data. This independent-lane requirement follows a reproduced race
where a shared notification could wake the wrong sender and strand a queued
frame. After the fix, twenty consecutive encrypted native C ABI loops passed
with exact 192-KiB key-frame, Opus, Wacom-like input, and bidirectional data
payloads. Eleven normal Rust tests and strict Clippy pass. Clean
`.190.plank_transport` packages passed their gates and a real 3840x2160 HEVC Rext
10-bit 4:4:4 session delivered exact matching native counters with no
application, QUIC, or KyProto drops. It exposed one remaining architectural
mismatch: common-c still launched idle legacy UDP receiver threads, whose
ten-second first-traffic watchdog could not observe direct KyProto frames.
`.191.plank_transport` explicitly selected a native-media lifecycle and therefore
does not bind, ping, start, stop, or consult those legacy media workers. The
obsolete transitional encrypted/FEC packet-receiver callbacks are removed;
the ordinary legacy bookmark path retains its receiver and traffic flag only
for temporary A/B testing. Its first live launch exposed two boundary errors:
native Opus was unnecessarily gated on common-c's direct-submit capability,
and Host capture still waited for legacy audio/video association pings.

`.192.plank_transport` accepts native Opus on its already-dedicated submission
thread and starts native Host capture without the legacy media pings or socket
QoS. A real 3840x2160x60 run lasted 84 seconds and ended with exact matching
Host/Client counters: 4,573 video frames / 404,142,526 bytes and 15,336 Opus
packets / 4,907,520 bytes. Application queue/receive drops, KyProto drops, and
QUIC packet loss were zero, and the 52.5 Mbps bitrate request/ack matched. No
first-traffic timeout, media-ping timeout, or audio-start failure occurred.
This accepts the native media lifecycle gate. Recovery/control semantics and
input/cursor migration are next.

Protocol 10 and candidate `.197.plank_transport` complete the native-only runtime
cut. The Client no longer has a data-plane selector or starts legacy ENet,
UDP media receivers, RTP/AES/Reed-Solomon reconstruction, or media watchdogs.
The Host binds only the HTTPS/TCP control endpoint and the authenticated
KyProto UDP endpoint; it no longer binds legacy ENet control or UDP media
ports. A real 3840x2160x60 NvFBC-to-x264 High 10 4:4:4 identity run matched
Host and Client native counters with zero media, QUIC, or KyProto drops.

The `.198.plank_transport` bounded deletion removes the now-unreachable Host
packetization implementation itself. `stream.cpp` submits complete encoded
H.264/HEVC frames, raw Opus packets, typed native control, native input, and
native events directly to the PlankTransport endpoint. Legacy RTP headers, media
AES, Reed-Solomon/FEC shards, ENet control-server state, association-ping
state, UDP send batching, and their per-session fields remain absent. Package
gates reject those implementation symbols so a later refactor cannot quietly
restore a second data plane. This deletion does not change HTTPS/PAM/display
or profile negotiation, which remain product control-plane responsibilities.

The following `.199.plank_transport` build-system cut removes the Host's unused ENet
and nanors/Reed-Solomon initialization, wrappers, source lists, includes,
subproject, and link target. Host RTSP now includes only common-c's public
stream and parser declarations instead of its broad private implementation
header, eliminating the last transitive ENet include while preserving the
existing setup negotiation. The complete Host links without either dependency,
and package gates reject their first-party source or CMake wiring.

The `.200.plank_transport` source checkpoint removes the retired
`concat_and_insert` packet-construction fixture, so the focused Host unit
target no longer references the deleted packetizer helper. A package gate
keeps both the helper and its obsolete test from returning.

The `.201.plank_transport` synchronized Client/common-c cut removes nanors and the
unreachable RTP audio/video FEC queues from source, submodules, qmake,
packaging, licensing, and provenance. Kyber remains the only media FEC owner.
The cut intentionally retains ENet until native recovery/callback needs are
separated from the dormant mixed RTP/RTSP adapter; it does not disguise that
larger refactor with new shims. A clean Development NUC package passed all
absence, Qt, runtime, SDL3 PipeWire, and install-policy gates. Its live session
against the `.200` Host reconciled 1,184 native video frames and all but the
single final timed-shutdown audio packet, with zero queue, receive, QUIC, or
KyProto drops. The next dependency cut must first inventory and isolate the
remaining ENet, RTSP, recovery, and callback boundaries.

The `.202.plank_transport` cut completes that inventory and deletes ENet from the
Client/common-c dependency graph. RTSP setup remains TCP; native KyProto owns
control, input, media, and typed events. Common-c retains only the decoder's
native IDR/reference-invalidation workers and asynchronous HDR, Wacom,
bitrate, and cursor callback dispatch. ENet source, submodule/build wiring,
platform lifecycle, control/input fallbacks, receive/loss workers, and
obsolete ENet/GameStream-FEC SDP attributes are absent and package-gated. A
clean Development NUC build, install, 19/19 root tests, and a 40-second
3840x2160 live run passed with exact video/audio counters and zero media,
QUIC, or KyProto drops.

The first End-User NUC `.202` WAN acceptance run found an unresolved
5120x2160x60 failure that blocks merge. With NvFBC, NVENC HEVC 10-bit 4:4:4,
and a 50 Mbps target, audio remained real-time while visible video advanced
frame-for-frame at roughly 1--2 FPS and progressively fell behind, interrupted
by brief normal-motion intervals. Host and Client still reconciled all 29,694
video frames, application queues remained essentially empty, and measured CPU,
GPU, decode, and renderer-call load had ample headroom. The media direction
reported 1,243 QUIC packet losses and the Client reported two KyProto drops,
but stock RaptorQ recovery and its 50 ms missing-sequence buffer cannot be
changed on aggregate evidence that does not locate content age. Reboot hardware-test-host
manually and repeat the exact test first. If reproducible, timestamp and hash
distinct frames at capture, encoded output, KyProto reconstruction, and actual
presentation before changing transport, FEC, capture, or decoder behavior.

Candidate `.209.plank_transport` completes the bounded RTSP implementation deletion
after native QUIC setup was accepted in `.208`. Host session ownership now
lives in `session_stream`; the Host and common-c no longer compile an RTSP
server/client, parser, SDP generator, setup cipher, RTSP URL, `rikey`, or
`rikeyid`. Native setup is mandatory and fails closed. HTTPS remains only for
authorized workstation discovery, PAM/login, topology/display preparation,
and launch authorization; this checkpoint does not yet consolidate those
product control-plane operations onto QUIC.

Clean Host and Client packages passed their source, dependency, version,
runtime, no-autostart, and RTSP-absence gates. Root qualification passed 18/18,
and the PlankTransport-enabled Host test executable passed all 18 focused color,
configuration, retained-input, and raw-HID tablet tests. A repeat 99-second
3840x2160x60 NvFBC-to-x264 High 10 4:4:4 identity run sustained 59.77 decoded
and 59.74 rendered FPS. It delivered 5,639 video frames and 18,384 Opus
packets with zero receive/send-queue drops, zero reported network frame loss,
zero QUIC loss, and zero KyProto drops. Host/client audio and input counters
matched; the Host produced one final video frame while the Client performed
its orderly shutdown. TCP 48010 remained absent before, during, and after the
session.

The user manually installed `.209.plank_transport` on the End-User NUC and reported
that the WAN result looks good, accepting the RTSP-removal checkpoint. The next
bounded cut is TCP-port consolidation: replace unauthenticated HTTP on TCP
47989 with certificate-first HTTPS on that same base port and retire the
separate HTTPS listener on TCP 47984. The retained PAM, ownership,
topology/display, and launch-authorization control plane remains on HTTPS.
Native Kyber/KyProto continues on UDP 47989. This produces one externally
configured port number without coupling the working product control services
to a larger rewrite.

Candidate `.210.plank_transport` completes that cut. The Host now serves only HTTPS
on TCP 47989 and native Kyber/KyProto on UDP 47989. The Client performs the
PLANK self-signed certificate-profile validation from first contact,
uses HTTPS for discovery, PAM, topology, and launch, and has no plaintext URL
or distinct HTTPS-port state. Connectivity testing and packaged firewall
policy expose only TCP/UDP 47989. Existing bookmarks already held that base
port and required no migration.

Clean packages are installed on hardware-test-host and the Development NUC. TLS 1.3
serverinfo advertised both `HttpsPort` and `ExternalPort` as 47989, while a
plaintext request on the same socket received no HTTP response. Idle listener
inventory showed only TCP 47989; a live session added only UDP 47989. TCP
47984/48010 and UDP 47998/47999/48000 were absent throughout. An existing
bookmark and an immediate fresh direct-address session both authenticated,
prepared the display, negotiated native setup, streamed 3840x2160x60 H.264
High 10 4:4:4 identity with PipeWire audio and raw-HID Wacom initialized, and
restored the physical MetaMode at teardown. Across the longer run the Client
received 3,885 frames at 59.68 decode FPS and 59.57 rendered FPS with zero
media drops, QUIC loss, or KyProto drops. Root tests, focused Host tests, and
the NvFBC/NVENC/Wacom/PAM hardware qualification all pass.

The one-port-number objective is therefore implemented and locally accepted.
Keep the experiment unmerged pending the user's `.210` End-User NUC/WAN check
and the remaining acceptance matrix. Any later replacement of the retained
HTTPS product control plane is a separate architectural boundary; it must not
be smuggled into this completed port consolidation.

## Acceptance gates

- all qualified capture and encoding profiles, including exact 10-bit 4:4:4;
- 10 to 150 Mbps bookmark targets and live toolbar changes;
- current random-loss staircase through 10 percent and comparison with the
  retained first-freeze/FEC baseline;
- keyboard, mouse buttons, scroll, NumLock, local cursor, and toolbar input;
- Wacom hover, pressure, tip, buttons, Tablet Margins, reconnect, focus,
  suspend/reattach, and Flame restart;
- audio synchronization, long-duration drift, and multi-hour RSS behavior;
- single- and dual-monitor Native and Scaled-Span sessions;
- login-to-desktop transition, reconnect, Host reboot, timeout, and explicit
  disconnect behavior;
- no material regression in client/Host CPU, decode time, input latency,
  visual quality, or encoder-target behavior;
- malformed framing, unknown endpoints, invalid/expired tokens, replay,
  certificate mismatch, queue exhaustion, and teardown security tests;
- packet capture proving that only the selected TCP and UDP port remain after
  full control-plane consolidation.

## Build discipline

Pin the Rust toolchain and every Cargo dependency. Retain a canonical local
Kyber repository and Cargo source cache on each build machine; clean Git
worktrees must not redownload dependencies. Extend the release build runbook
before producing a candidate package. Do not build on or remotely install the
End-User NUC.
