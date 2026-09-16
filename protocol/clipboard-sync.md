# Clipboard sync v1

Status: implemented for the Teraguchi Mac client and Linux X11 Host. The
feature remains candidate-scoped until a clean paired package passes live
qualification.

## Scope

Bidirectional UTF-8 plain text clipboard during an authenticated stream:

| Copy on | Paste on | Shortcut |
|---|---|---|
| Mac | Linux / Flame | `Ctrl+V` in the remote session |
| Linux / Flame | Mac | `Cmd+V` on macOS |

Images, files, HTML, RTF, Flame-internal formats, and clipboard transfer across
disconnect are outside v1.

## Negotiation

`ClipboardSyncFeature` is launch feature bit `0x400000`.

- The client includes the bit in `plankFeatureFlags`.
- The Host accepts clipboard traffic only when the authenticated session
  negotiated the bit.
- If absent, no automatic synchronization occurs. The inherited text-injection
  key combination remains available.

## Transport

`PLANK_CLIPBOARD_WIRE_HEADER` is defined in `moonlight-common-c/src/plank.h`.
All header fields use little-endian byte order.

| Lane | Type | Direction |
|---|---|---|
| PLE1 event `PLANK_TRANSPORT_EVENT_CLIPBOARD_OFFER` (5) | Host → client |
| Input `PLANK_TRANSPORT_INPUT_CLIPBOARD_OFFER` (9) | Client → Host |

Each chunk carries `generation`, `totalSize`, `chunkOffset`, `chunkSize`, and
`FIRST` / `LAST` flags. MIME is implicit UTF-8 plain text.

Receivers must:

- require the payload length to equal `sizeof(header) + chunkSize`;
- reject zero-length chunks, unknown flags, nonzero reserved fields, and
  generation zero;
- accept only ordered, contiguous chunks from one generation;
- reject text over 1 MiB;
- reject malformed UTF-8, overlong encodings, surrogate code points, values
  above U+10FFFF, and embedded NUL;
- keep inbound and outbound generation counters independent;
- reset generation and partial assembly state for each authenticated session;
- ignore completed generations older than the last applied generation from the
  same sender.

See `tests/protocol/clipboard-sync-v1.json`.

## Client behavior

The macOS client reads and writes `NSPasteboard` only on the SDL main thread.
It polls every 250 ms while the stream has input focus. A copy made in another
Mac application is sent after focus returns to the stream. Host offers are
queued without event-owned heap payloads and carry a session epoch so events
from an earlier connection cannot apply after reconnect.

The client deduplicates repeated Host text by content. It never compares Host
generations against its independent outbound generation. Failed transport
sends remain pending for the next poll; failure to queue a Host offer on the
SDL event loop terminates the affected session.

## Host behavior

The Linux X11 Host watches `CLIPBOARD`, publishes client text as owner of
`CLIPBOARD` and `PRIMARY`, and answers `SelectionRequest` for UTF-8/plain-text
targets. It records each locally forwarded value to prevent repeated offers.
Validated Client offers cross a bounded latest-value inbox; the dedicated
clipboard thread performs all Xlib selection reads and writes. If several
offers arrive before the next 250 ms poll, the newest clipboard value wins.

Session teardown releases any synthetic selection ownership, destroys the X11
window, and closes the display after clipboard workers stop.

## Security and diagnostics

- Traffic is accepted only from the authenticated stream owner.
- Mac → Host automatic sync requires stream input focus.
- Payload contents never enter logs; size and generation may.
- Malformed frames terminate the affected authenticated session.
