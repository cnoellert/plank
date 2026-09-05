# Output Topology and Selection

## Scope

Protocol version 13 describes the host desktop after operating-system
authentication and lets the client select one capture output or a scaled span
of the complete desktop. Topology is not available through unauthenticated
discovery. The same topology snapshot must drive capture, presentation, cursor
placement, normalized mouse/touch input, and Wacom mapping for the lifetime of
a stream.

## Feature Negotiation

The host returns `schema_version: 13` and a numeric `feature_flags` field from
`GET /plank/topology`. Version 13 defines these bits:

- `0x1` — output topology publication
- `0x2` — stable selected-output launch
- `0x4` — unified absolute-input geometry
- `0x8` — aspect-preserving scaled desktop span
- `0x10` — topology-generation binding at launch and during streaming
- `0x20` — host-layout and virtual-output metadata
- `0x40` — composite-stream source rectangles for local presentation
- `0x80` — exact host-layout binding at launch
- `0x100` — independently selected modes for virtual outputs 1 and 2
- `0x200` — bounded host-layout activation while GDM owns the active seat
- `0x400` — temporary physical-display leases with exact disconnect restoration
- `0x800` — exact per-session capture-source selection and acknowledgement
- `0x1000` — exact per-session encoder-backend and encoding-mode selection
- `0x2000` — NvFBC 8-bit source expansion into HEVC 10-bit 4:4:4 direct NVENC
- `0x4000` — one fixed complete QUIC UDP payload ceiling for both endpoints
- `0x8000` — authenticated transfer of the one active PLANK session between clients
- `0x10000` — explicit GDM-to-user desktop handoff notice on the native control channel
- `0x20000` — authenticated desktop stage for reconnect progress

### Expected desktop handoff status

With `0x10000`, Host-to-Client `PLD1` control type 7 has no payload. Its exact
wire vector is `50 4c 44 31 00 07 00 00`. The root supervisor issues a private
`PLANK-DESKTOP-HANDOFF-1` record only when replacing its greeter worker with a
confirmed active user desktop. The root-authenticated inherited channel lets
that worker announce the handoff before invoking its normal SIGTERM path;
the existing bounded supervisor shutdown remains the fallback. No credentials
or new network listener are introduced.

The notice is advisory: it cannot authorize a session, trigger a reconnect,
transfer ownership or substitute for fresh PAM and topology validation. A
Client accepts only a zero-length notice from the authenticated Host channel
advertising this feature. It is consumed by the next transport close within
five seconds, producing neutral `Opening your desktop...` text. Without the
notice, reconnect shows `Connection interrupted - reconnecting...`. If the
existing unreachable decision timeout expires, status changes to `Workstation
is taking longer to respond...` and the existing Wait/Disconnect policy applies.
Success clears the notice and restores the normal status color. An abrupt X
failure can prevent delivery; it must fall back to ordinary reconnect, never
guess from the previous screen or suppress a real timeout.

With `0x20000`, a successful PAM HTTPS response additionally includes
`desktop_stage`: `greeter`, `user`, or `unknown`. It is never included in a
challenge or denied response, nor in public discovery. The worker reports a
concrete stage only when its supervisor-attested session ID, UID and class
match the currently active eligible local seat0 X11 session. A closing,
missing, replaced or unmatched session reports `unknown`.

Logout can destroy the desktop X server before its worker sends any final
packet. During reconnect, a successful reauthentication reporting `greeter`
therefore changes the Client status to neutral `Returning to the sign-in
screen...` while topology, launch and transport are restored. Until that
confirmation, ordinary interruption status remains; neither a network outage
nor a lost X server is assumed to mean logout. A greeter-to-greeter recovery
may use the same wording. The notice is UI-only, carries no user/session
identity, grants no access, and does not change any PAM, desktop-ownership,
shutdown or launch checks. Rendering updates stay on the SDL event thread.
The existing timeout always takes precedence, even if reauthentication finishes
late; completion clears the pending status. No Xlib fatal-handler work, extra
worker, polling loop or fixed delay is introduced.

The client sends `plankProtocolVersion=13`, `plankFeatureFlags`, `plankDisplayMode`,
`plankHostLayout`, `plankVirtualMode1`, and `plankVirtualMode2` on `/launch`. A client negotiating `0x10`
also sends the exact
`plankTopologyGeneration` returned by the topology endpoint. `single-output` also
requires `plankOutputId`; `scaled-span` captures the desktop bounds and omits it.
An output ID is opaque to the client. Linux/X11 IDs use the current
`x11:<connector>` form, for example `x11:DP-2`; enumeration indices are never
sent as stable IDs.

## Topology Document

The document contains a monotonically changing `generation`, the bounding
desktop rectangle, a `layout` object, and an `outputs` array. `layout.kind` is
`physical`, `single`, or `dual-horizontal`; `layout.virtual_modes` is empty for
a physical layout, contains one administrator-qualified mode for `single`, and
contains the independently ordered primary/secondary modes for
`dual-horizontal`. `layout.startup_kind` reports the concrete boot topology:
`physical`, or `single` for the safe 1920x1080 baseline created by the
administrator's `virtual` policy. `layout.allowed_kinds` explicitly lists the
layouts a bookmark may request. A physical startup lists physical, single, and dual-horizontal; a
virtual startup lists single and dual-horizontal. The current layout can
therefore be virtual while its startup remains physical during a session
lease. The layout also publishes whether the current geometry is virtual and
its output count. Each connected output carries its
opaque `id`, user-facing `name`, desktop `x`/`y`, pixel `width`/`height`,
clockwise `rotation`, `refresh_millihz`, and `primary` state. Coordinates may be
negative. Unknown refresh is zero. Each output also carries `virtual` and a
`configured_mode` and a `source_rect` in composite-source coordinates. Version 13 currently makes the
source rectangle identical to the output rectangle relative to the desktop
origin; keeping it explicit avoids inferring monitor boundaries from a wide
encoded frame.

Each bookmark also sends `plankCaptureSource=nvfbc` or
`plankCaptureSource=x11-native10`. The host echoes the accepted value as
`PlankCaptureSource`; the client fails the launch if it is absent or
different. The client also sends `plankEncoderBackend=software-cuda` or
`nvenc-direct` and an exact `plankEncodingMode`. The host echoes both values as
`PlankEncoderBackend` and `PlankEncodingMode`; a missing or
different acknowledgement fails the launch. `x11-native10` is experimental
and accepts only a 10-bit 4:4:4 identity profile. It never falls back to NvFBC
or accepts an 8-bit profile. Its x264 path converts a same-size packed RGB10
canvas directly to planar GBR10, or performs center-aligned bilinear scaling
and plane generation in that same CPU pass when the negotiated encode size is
different. See `protocol/encoding-profiles.md` for the exact allowed tuples.

Protocol version 13 has one data plane: native PlankTransport. The removed
`plankDataPlane` request and `PlankDataPlane` acknowledgement are not
accepted compatibility switches. Every successful launch returns a PlankTransport
port, canonical TLS certificate SHA-256 fingerprint, and canonical one-use
session token; missing or malformed native credentials fail the launch.
The client also resolves its active route and sends
`plankQuicUdpPayloadMtu=1200..65527`. The host applies that exact complete UDP
payload ceiling before it starts its Quinn listener, echoes it as
`PlankQuicUdpPayloadMtu`, and the client applies the same value before
its endpoint starts. Automatic mode uses the selected route interface MTU with
a conservative cap; the qualified ZeroTier route uses 1344 bytes. Manual mode
is an explicit complete-QUIC-UDP-payload override. A missing, invalid, or
mismatched value fails launch so RaptorQ never packetizes a frame against a
path size that can shrink underneath it.

Bookmarks persist `configured`, `physical`, `single`, or `dual-horizontal` as
their host-layout requirement. `configured` is resolved to the authenticated
topology's exact current layout before launch; it is not sent as a wildcard.
Virtual layouts persist one enumerated mode per requested output. The current
60 Hz allowlist is `1024x2160`, `1280x2160`, `1920x1080`, `1920x1200`,
`2560x1440`, `2560x1600`, `2560x2160`, `3440x1440`, `3840x1600`,
`3840x2160`, `4096x2160`, and `5120x2160`. The host compares the requested
layout and both modes with the live topology before claiming the one-use PAM
launch state. A mismatch returns 425 and submits only the enumerated layout,
modes, and authenticated account UID to the root supervisor. Headless virtual
startup retains its bounded GDM transition. A physical-startup host instead
captures the exact NVIDIA MetaMode and applies a temporary logical layout over
the connected native scanouts without restarting the display manager. The
client retains credentials only in memory, waits for the new topology,
refreshes its generation, and continues launch. When login replaces GDM, the
supervisor takes a new snapshot from the authenticated user's X server and
carries the lease into it. The final stream release restores the exact saved
MetaMode; an abandoned launch restores after its bounded setup deadline.

The client persists the chosen output ID per host UUID. If it has no valid
mapping, it selects the primary output, then the first output as a final
fallback. It must re-fetch after hotplug or a rejected launch rather than
falling back to an enumeration index.

Generation fingerprints are independent of enumeration order and change when
output identity, geometry, rotation, refresh, or primary state changes. The
host rejects a stale launch with status 409 before consuming the PAM session;
the client re-fetches the topology and retries once with the same authenticated
token. During a bound stream the host polls for topology replacement at a
one-second maximum interval. A change ends the stream and runs normal input
cleanup so no pen contact, key, or virtual HID device survives against stale
geometry. Reconnection requires fresh OS authentication; seamless in-stream
topology acknowledgement is reserved for a later protocol feature.

An accepted launch owns the workstation from HTTPS acceptance through queued
native setup, in-flight QUIC negotiation, and the running stream. A second
authenticated client receives status 409 with `PLANK workstation session is
active`; it must not poll or silently displace that owner. With explicit local
confirmation, a version-13 client retries the same launch or resume with
`plankTakeover=1`. The Host accepts that flag only with feature `0x8000`, only
after PAM authentication, and only when the authenticated account still owns
the active desktop. It first revokes the old input path, sends reliable
termination reason `0x80030024`, joins the old stream, and only then starts
replacement display and media state. The displaced client disables automatic
reconnect and reports that its session was transferred. No Host OS logout
occurs, so the user's desktop and applications remain running.

## Launch and Input Rules

The host rejects an unsupported protocol version, unnegotiated feature bits,
an unknown output ID, or an output that disappears before launch. A successful
single-output launch resolves the opaque ID once and stores the capture name in
session state. A scaled-span launch captures the complete desktop rectangle
into the requested stream size without changing aspect ratio; unused pixels
are black. The video touch-port uses the same scale and offsets, so normalized
absolute devices share its geometry. Raw Wacom HID reports remain byte-for-byte
device data and are never scaled by this protocol; the host Wacom/Xorg stack
sees the same desktop topology and applies its normal physical-tablet mapping.

When several host outputs feed one client display, `scaled-span` is the default
PLANK mode. `single-output` remains available when native pixel detail
is more important than simultaneous visibility. `separate-displays` uses the
same one-decoder composite stream as `scaled-span`, but the client presents the
published source rectangles in synchronized local windows. Synchronized
per-output streams remain a future feature and must not be inferred from this
schema.

## Test Vector

`tests/protocol/output-topology-v13.json` represents a physical-startup host
temporarily presenting the Flame-style 3840x2160 primary plus 1280x2160
secondary virtual layout. Parsers must preserve order-independent
identity, geometry, virtual provenance, source rectangles, exact layout
binding, independent modes, allowed-layout capability, startup provenance, and
the primary fallback. The version-1, version-2, version-4, version-7, and
version-8 and version-9 vectors remain historical
evidence only; PLANK has no deployed legacy clients requiring a
silent version fallback.
