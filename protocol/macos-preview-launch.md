# Authenticated macOS preview launch (schema 2)

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

After authentication, both display preparation and launch check the graphical
worker's current, non-prompting screen/input permissions before changing modes
or creating a transport lease. Missing permission returns HTTP 403 with exactly
`{"state":"denied","error":"host_permissions_required"}`. This is an error
extension, not a change to the schema-2 success manifest or transport ABI.
Unauthenticated callers still receive 401 without permission details. The Client
maps only this fixed code to local instructions; arbitrary Host text is not
displayed. Permission denial does not alter display topology. Any failed
authenticated display/launch attempt revokes that attempt's HTTP token (and
any claimed lease); retry requires fresh authentication. Unauthenticated or
wrong-peer requests cannot revoke another attempt. Successful display
preparation retains its token for launch. The Client stops automatic reconnect
on HTTP403, since operator consent cannot be recovered by repeated logins.
Capture/input still recheck access at startup to cover revocation races.

Authentication capacity/verification contention returns `{"state":"busy"}`,
distinct from `{"state":"denied"}` for rejected authentication. The Client
reports busy as HTTP503 locally, not an incorrect-password message. Pending
challenges are bounded at 16; unused authenticated setup tokens are bounded at
four. After successful account/ownership verification, a new token supersedes
unused tokens for the same verified account and peer. A full token table does
not prevent that verification/replacement. Account UUID and UID, not an
unverified username, define identity. Different accounts sharing a relay/NAT
remain independent. Active stream leases are separate and are never replaced
by a login attempt. Failed passwords cannot invalidate setup or stream access.
Failed/cancelled topology retrieval and failed topology reply delivery revoke
the authorized setup token, just as failed display/launch already does.
Unobserved client abandonment remains bounded by replacement and the five-minute
setup expiry. No account details or secrets enter errors. The wire format is
unchanged; existing Clients need no update.

The body has exactly the nine fields in
`tests/protocol/macos-preview-launch-v2.json`:

| Field | Required value |
| --- | --- |
| `schema_version` | Integer 2 |
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

A successful response has schema 2, `state: "connecting"`, an independent
one-use `transport_token`, `udp_port`, the exact `max_udp_payload_size`, the
selected `capture` descriptor and:

```json
"services": {"audio": true, "input": true, "pen": "normalized", "cursor": "embedded"}
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
Keyboard, absolute mouse, buttons, scrolling and normalized pen use native input.
No separate cursor, raw-HID or generic-touchscreen capability is claimed.
See `macos-pen-input.md` for pressure, validation and cleanup. Schema1 is rejected;
this requires matching Host/Client candidates, without a legacy fallback.
The native library itself retains its shared Linux endpoint implementation.

The Client now has a typed manifest parser and explicit native service flags.
Audio/input/normalized pen are required for this manifest. It sets
`LI_FF_DYNAMIC_VIDEO_BITRATE | LI_FF_ENCODER_TARGET_ACK | LI_FF_PEN_TOUCH_EVENTS`. The embedded cursor needs no local
cursor channel. Common-c skips absent service workers;
the Client does not start an audio receiver without negotiated audio. Linux
PLS1 setup explicitly retains all three services and its existing checks.
This internal Client/common-c struct change is not a transport wire ABI change;
the two must be rebuilt together, without an old-struct fallback.

The ordinary Session calls the pinned HTTPS launch, then consumes this manifest
instead of sending a Linux setup exchange. Capture pixels remain host-native;
Scaled-Span fits them at presentation. A changed topology requires fresh
authentication/geometry instead of silently reusing stale dimensions.

Mac display preparation accepts exact even dimensions from 2 through 8192 per
axis under the existing schema-2 numeric contract. Match Client supplies native
pixel dimensions, not a member of the Linux EDID preset list or the Retina
logical/backing size. One display or two horizontally arranged displays form
one canvas (sum of widths, maximum height). Manual presets remain available.
The Host registers at most one additional custom 60 Hz mode alongside its
presets, only applying changed settings while an existing output is online.
Preparation and launch must confirm the exact geometry and selected encoder
profile; these bounds are not a promise of encoder support for every size.
There is no nearest-preset substitution, Linux EDID change, new request field
or wire-version change. Matching Host/Client builds are required for this
expanded implementation of the existing dimensions contract.
