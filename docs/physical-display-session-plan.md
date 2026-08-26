# Physical-Display Session Lease

## Goal

A workstation with connected physical monitors may temporarily present a
bookmark-selected StationConnect layout without leaving the local console in a
broken state after disconnect. The host restores the exact pre-session NVIDIA
MetaMode when the last StationConnect stream ends. A failed exact restore
enables one known connected physical output at a safe native mode. Recovery
never reboots the workstation and never restarts the display manager merely to
repair a live user desktop.

The administrator configuration describes only the boot layout:

```ini
[display]
startup_layout = physical
virtual_mode_1 = 1920x1080
virtual_mode_2 = 1920x1080
```

`startup_layout` accepts `physical`, `single`, or `dual-horizontal`.
`physical` removes the StationConnect Xorg overlay at boot but permits a
temporary `single` or `dual-horizontal` bookmark layout. The two virtual
startup values retain the packaged EDID workflow for truly headless machines.

## Protocol

Output-topology protocol version 5 separates the current live layout from the
layouts the host can accept. The topology document publishes
`layout.startup_kind` and `layout.allowed_kinds` in addition to the existing
current `layout.kind`. A physical-startup host advertises physical, single, and
dual-horizontal. A virtual-startup host advertises single and dual-horizontal.
The host still validates the actual connected-output count when applying a
request; for example, two temporary logical displays require two usable
physical scanout outputs.

Worker-to-supervisor control messages distinguish acquire, activate, and
release operations. The root supervisor owns the lease. The media worker may
request it only for the PAM-authenticated account that owns the active desktop.
An acquired lease has a short setup deadline. It becomes active only when the
RTSP stream is allocated, preventing an abandoned HTTPS launch from leaving a
temporary topology behind. The last stream releases the lease.

## Physical layout application

Before changing a physical-startup X server, the supervisor captures
`CurrentMetaMode` with `nvidia-settings`. That string is the authoritative
rollback record; reconstructing a layout from output dimensions would lose
viewport, panning, primary-output, and positioning details.

Temporary layouts reuse the currently active physical scanout surfaces. Their
native `ViewPortOut` values remain unchanged while the requested StationConnect
resolution becomes `ViewPortIn` and the logical panning domain. This gives the
capture desktop the exact bookmark dimensions without injecting an unqualified
physical timing. A single layout uses one scanout and a dual-horizontal layout
uses two, ordered left to right.

GDM and an authenticated desktop are different X servers. When login replaces
GDM while a lease belongs to that account, the supervisor captures the new
user X server's physical MetaMode and reapplies the requested temporary layout
before launching its media worker. A logout back to GDM invalidates the user
lease because the leased X server no longer exists.

## Restoration and failure policy

On normal disconnect the supervisor assigns the exact saved MetaMode to the
same live X server, clears the runtime topology marker, and logs success. If
the session or X server has already disappeared, the lease is cleared without
applying a stale snapshot to a replacement server.

If exact assignment fails on the same X server, the supervisor builds a
minimal MetaMode from the first validated physical scanout in the snapshot,
uses its native output size at `+0+0`, disables the other temporary outputs,
and logs a prominent recovery error. It does not reboot, restart GDM, or modify
the administrator's Xorg configuration.

## Acceptance gates

1. A physical two-monitor host accepts single and dual bookmark layouts.
2. GDM login carries the lease into the authenticated user's replacement X
   server without requiring a second manual connection attempt.
3. Disconnect restores the exact pre-stream MetaMode byte for byte.
4. A forced exact-restore failure leaves one connected physical monitor usable
   through the safe fallback.
5. An abandoned launch restores automatically after its setup deadline.
6. A stale release cannot restore over a newer session owner's lease.
7. Headless single/dual startup and live single/dual transitions retain their
   existing packaged-EDID behavior.
8. No recovery path invokes reboot or restarts an authenticated user's display
   manager.
