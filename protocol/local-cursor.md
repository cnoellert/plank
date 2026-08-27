# Local Cursor Protocol

StationConnect presents the host pointer as a compositor-owned cursor on the
client. The host cursor is never composited into negotiated StationConnect
video frames. This gives the streamed desktop and the native toolbar one local
pointer and removes any remote/local cursor handoff at the toolbar boundary.

The host advertises `LI_FF_LOCAL_CURSOR` (`0x40`) and
`LI_FF_CURSOR_POSITION` (`0x80`). The client advertises `ML_FF_LOCAL_CURSOR`
(`0x10`) and `ML_FF_CURSOR_POSITION` (`0x20`). All four bits are mandatory
StationConnect protocol requirements. A missing bit is a connection error;
there is no embedded-video cursor fallback, compatibility mode, configuration
switch, or migration path.

Cursor images travel on the encrypted, reliable control stream as message
`0x5507`. Each payload begins with `SC_CURSOR_WIRE_HEADER` from
`StationConnect.h`. All integer fields are little-endian. Pixels use
premultiplied 32-bit ARGB8888 values in row-major order. The header carries the
exact XFixes cursor serial as `generation`, image dimensions, hotspot,
visibility, total image size, and the offset and size of the current chunk.

The first and final packets of an image set `SC_CURSOR_FLAG_FIRST_CHUNK` and
`SC_CURSOR_FLAG_LAST_CHUNK`. Chunks for one generation are reliable and
ordered, but the client still validates offsets and discards an incomplete or
superseded generation. Dimensions are limited to 512 by 512 and each control
chunk to 48 KiB. These limits permit large custom Flame cursors without
overflowing the 16-bit encrypted-control payload length.

The host sends its authoritative cursor hotspot position as message `0x5508`.
Each payload is one `SC_CURSOR_POSITION_WIRE_MESSAGE`. Position packets use
the encrypted control channel without retransmission and carry a monotonically
increasing sequence number, so delayed or reordered samples are discarded.
Coordinates are encoded-frame pixels after the host capture canvas has been
aspect-fit into the negotiated video frame. This accounts for host capture
letterboxing before the client maps the position through its presentation
letterboxing.

The host obtains the exact cursor bitmap, hotspot, and root position from XFixes, including
custom and animated application cursors. It sends an initial image after the
control peer is ready and sends a replacement whenever the X cursor serial
changes. A fully transparent cursor is sent with visibility cleared. Cursor
hotspots on transparent Xorg placeholder images are normalized into the image
bounds because they have no visible semantic meaning. For ordinary mouse input,
the Wayland compositor cursor remains authoritative. For raw-HID Wacom input,
the client displays the latest host-authoritative position in an
input-transparent Wayland subsurface. This preserves the host Wacom driver's
pressure and Tablet Margins mapping. The next physical mouse motion immediately
restores the compositor cursor.

The client assembles and validates a complete generation before replacing both
the compositor cursor image and the input-transparent Wacom cursor surface.
Cursor construction and replacement occur on the SDL event thread. While the
pointer belongs to the native toolbar, the toolbar uses its local arrow cursor.
No path warps or synthesizes local pointer motion. Buttons, wheel events, and
motion over the toolbar remain exclusively local and never reach the host.
