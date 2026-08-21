# Output Topology and Selection

## Scope

Protocol version 1 describes the host desktop after operating-system
authentication and lets the client select one capture output or a scaled span
of the complete desktop. Topology is not available through unauthenticated
discovery. The same topology snapshot must drive capture, presentation, cursor
placement, normalized mouse/touch input, and Wacom mapping for the lifetime of
a stream.

## Feature Negotiation

The host returns `schema_version: 1` and a numeric `feature_flags` field from
`GET /stationconnect/topology`. Version 1 defines these bits:

- `0x1` — output topology publication
- `0x2` — stable selected-output launch
- `0x4` — unified absolute-input geometry
- `0x8` — aspect-preserving scaled desktop span

The client sends `scProtocolVersion=1`, `scFeatureFlags`, and `scDisplayMode` on
`/launch`. `single-output` also requires `scOutputId`; `scaled-span` captures the
desktop bounds and omits it. An output ID is opaque to the client. Linux/X11
IDs use the current `x11:<connector>` form, for example `x11:DP-2`;
enumeration indices are never sent as stable IDs.

## Topology Document

The document contains a monotonically changing `generation`, the bounding
desktop rectangle, and an `outputs` array. Each connected output carries its
opaque `id`, user-facing `name`, desktop `x`/`y`, pixel `width`/`height`,
clockwise `rotation`, `refresh_millihz`, and `primary` state. Coordinates may be
negative. Unknown refresh is zero.

The client persists the chosen output ID per host UUID. If it has no valid
mapping, it selects the primary output, then the first output as a final
fallback. It must re-fetch after hotplug or a rejected launch rather than
falling back to an enumeration index.

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
is more important than simultaneous visibility. Synchronized per-output
streams require a future feature bit and must not be inferred from this schema.

## Test Vector

`tests/protocol/output-topology-v1.json` represents the qualification host:
3840x2160 Flame on primary `DP-2` and 1280x2160 scopes on `DP-1`. Parsers must
preserve order-independent identity, geometry, and the primary fallback.
