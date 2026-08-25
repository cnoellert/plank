# Output Topology and Selection

## Scope

Protocol version 2 describes the host desktop after operating-system
authentication and lets the client select one capture output or a scaled span
of the complete desktop. Topology is not available through unauthenticated
discovery. The same topology snapshot must drive capture, presentation, cursor
placement, normalized mouse/touch input, and Wacom mapping for the lifetime of
a stream.

## Feature Negotiation

The host returns `schema_version: 2` and a numeric `feature_flags` field from
`GET /stationconnect/topology`. Version 2 defines these bits:

- `0x1` — output topology publication
- `0x2` — stable selected-output launch
- `0x4` — unified absolute-input geometry
- `0x8` — aspect-preserving scaled desktop span
- `0x10` — topology-generation binding at launch and during streaming
- `0x20` — host-layout and virtual-output metadata
- `0x40` — composite-stream source rectangles for local presentation
- `0x80` — exact host-layout binding at launch

The client sends `scProtocolVersion=2`, `scFeatureFlags`, `scDisplayMode`,
`scHostLayout`, and `scVirtualMode` on `/launch`. A client negotiating `0x10`
also sends the exact
`scTopologyGeneration` returned by the topology endpoint. `single-output` also
requires `scOutputId`; `scaled-span` captures the desktop bounds and omits it.
An output ID is opaque to the client. Linux/X11 IDs use the current
`x11:<connector>` form, for example `x11:DP-2`; enumeration indices are never
sent as stable IDs.

## Topology Document

The document contains a monotonically changing `generation`, the bounding
desktop rectangle, a `layout` object, and an `outputs` array. `layout.kind` is
`physical`, `single`, or `dual-horizontal`; `layout.virtual_mode` is empty for
a physical layout and is one of the administrator-qualified virtual modes for
a virtual layout. The layout also publishes whether it is virtual and its
output count. Each connected output carries its
opaque `id`, user-facing `name`, desktop `x`/`y`, pixel `width`/`height`,
clockwise `rotation`, `refresh_millihz`, and `primary` state. Coordinates may be
negative. Unknown refresh is zero. Each output also carries `virtual` and a
`source_rect` in composite-source coordinates. Version 2 currently makes the
source rectangle identical to the output rectangle relative to the desktop
origin; keeping it explicit avoids inferring monitor boundaries from a wide
encoded frame.

Bookmarks persist `configured`, `physical`, `single`, or `dual-horizontal` as
their host-layout requirement. `configured` is resolved to the authenticated
topology's exact current layout before launch; it is not sent as a wildcard.
Virtual layouts also persist an enumerated `1920x1080` or `3840x2160` mode.
The host compares the requested layout and mode with both its administrator
configuration and the live topology before claiming the one-use PAM launch
state. A mismatch returns 409 with a clear restart/configuration requirement.
The first implementation never restarts Xorg or changes an active Flame
desktop in response to a network request.

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
StationConnect mode. `single-output` remains available when native pixel detail
is more important than simultaneous visibility. `separate-displays` uses the
same one-decoder composite stream as `scaled-span`, but the client presents the
published source rectangles in synchronized local windows. Synchronized
per-output streams remain a future feature and must not be inferred from this
schema.

## Test Vector

`tests/protocol/output-topology-v2.json` represents the qualified headless-test-host
dual-horizontal virtual layout. Parsers must preserve order-independent
identity, geometry, virtual provenance, source rectangles, exact layout
binding, and the primary fallback. The version-1 vector remains historical
evidence only; StationConnect has no deployed legacy clients requiring a
silent version fallback.
