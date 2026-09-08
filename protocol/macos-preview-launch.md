# Authenticated macOS preview launch (schema 1)

Experimental, on `macos-host` only. The actual Host advertises HEVC Main10 and
fixed capture; component-only fixtures still advertise zero capabilities.
The ordinary Client uses this authenticated media contract. This does not
replace Linux PLS1 negotiation or claim completed LoginWindow deployment.

After TLS 1.3 certificate approval, `/plank/auth/start` and `/plank/auth/respond`
authenticate the active desktop's owner. `GET /plank/topology` returns the exact
schema-13 fixed-capture descriptor. The preview then accepts an authenticated
`POST /plank/launch` with `Authorization: Bearer <HTTP token>` and a JSON body.
No credentials or tokens are accepted in URLs. A missing launch handler leaves
the route absent (404); authentication itself does not enable capture.

The body has exactly the nine fields in
`tests/protocol/macos-preview-launch-v1.json`:

| Field | Required value |
| --- | --- |
| `schema_version` | Integer 1 |
| `capture_generation` | Current authenticated topology generation |
| `capture_id` | Current fixed-capture identifier |
| `width`, `height` | Exact advertised even pixel dimensions, 2–8192 |
| `encoding_mode` | `hevc-10-420-videotoolbox` |
| `frame_rate` | Integer 60 |
| `bitrate_kbps` | Integer 10000–150000, supplied by the bookmark |
| `max_udp_payload_size` | Integer 1200–65527, the existing native QUIC range |

The MTU value is the complete QUIC UDP payload ceiling, not Ethernet MTU or
encoded NAL size. The Client must calculate or manually select it using its
existing route policy; accepting a numeric value does not prove that path MTU.
Unknown fields, booleans as integers, wrong profiles and stale geometry fail.
There is no resize, profile substitution, implicit takeover or fallback port.

A successful response has schema 1, `state: "connecting"`, an independent
one-use `transport_token`, `udp_port`, the exact `max_udp_payload_size`, the
selected `capture` descriptor and:

```json
"services": {"audio": true, "input": true, "cursor": "embedded"}
```

The UDP port is the same number as the approved HTTPS control port. QUIC uses
the same leaf certificate; the Client pins the certificate it approved for
HTTPS, not a new trust decision or a request-selected certificate. Launch does
not instruct the Client to connect to another host/address. Bind address and
key/certificate files are trusted Host configuration, never JSON fields.

The original HTTP token is consumed. Replay fails even before QUIC connects.
The native transport secret proves possession for that connection; its endpoint
must reach READY within the claim's 15-second activation window. Capture starts
only after lease activation. Failed/expired HTTPS reply delivery revokes the
original token's claimed lease. An exception during launch also revokes it.

Native data controls retain existing PLD1 encoding: disconnect, keyframe request,
reference-range invalidation (implemented by forcing a keyframe), and bitrate
updates. Bitrate acknowledgement contains requested/applied/peak values in that
order. Malformed/unsupported controls fail the session. System audio is Opus,
stereo 48 kHz, 5 ms packets (one stream, one coupled stream, mapping 0/1).
Keyboard, absolute mouse, buttons, and scrolling use native input. No separate
cursor, raw-HID, tablet or generic-touchscreen capability is claimed.
The native library itself retains its shared Linux endpoint implementation.

The Client now has a typed manifest parser and explicit native service flags.
Audio/input are required for this manifest, while schema-1's bitrate
controls set `LI_FF_DYNAMIC_VIDEO_BITRATE | LI_FF_ENCODER_TARGET_ACK`. The embedded cursor needs no local
cursor channel. Common-c skips absent service workers;
the Client does not start an audio receiver without negotiated audio. Linux
PLS1 setup explicitly retains all three services and its existing checks.
This internal Client/common-c struct change is not a transport wire ABI change;
the two must be rebuilt together, without an old-struct fallback.

The ordinary Session calls the pinned HTTPS launch, then consumes this manifest
instead of sending a Linux setup exchange. Capture pixels remain host-native;
Scaled-Span fits them at presentation. A changed topology requires fresh
authentication/geometry instead of silently reusing stale dimensions.
