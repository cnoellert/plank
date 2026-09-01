# Current RGS Session-Transition Reference

PLANK engineering observed HP Anyware RGS Sender 26.2.1.9883 on
`reference-host` during an interactive login and logout. This was a read-only behavioral
reference; no RGS files or configuration were changed.

The system service uses `Type=simple`, `Restart=always`, and `RestartSec=2`.
Before logout, the root Sender was PID 7890. Logout terminated that process with
a connection-lost path and NvFBC destruction errors. Systemd then started a new
service wrapper and a new root Sender (PID 1331974) about three seconds later.
The current product therefore uses a stable service identity plus a fresh media
process across X-server replacement; it does not reuse one NvFBC process.

PLANK now follows the same lifecycle boundary while preserving its
machine-scoped UUID, TLS identity, and state file in the supervisor. A controlled
`hardware-test-host` to development-NUC test replaced the Sunshine worker while retaining the
supervisor. The client detected graceful transport termination, reauthenticated
after three bounded readiness failures, launched a fresh Desktop stream when
the replacement worker reported nothing to resume, and received the first new
video packet on reconnect attempt 4. No NvFBC crash or client process exit was
observed.

A later overlapping-session package test exposed an NvFBC crash when Sunshine's
per-resume encoder probe raced a starting capture thread. Revision 0.18 makes
the fresh worker's startup probe authoritative for PLANK and prefers a
new Desktop launch before falling back to resume. The repeated test retained
the supervisor, replaced the worker, restored video on attempt 4, held the same
worker for more than one minute with two session records present, and produced
no coredump.

The first end-user-NUC handoff also exposed stale raw-tablet state: the new host
worker correctly had no UHID devices, while the surviving client tablet object
continued sending reports under its old attachment generation. Revision 0.19
resets the raw-HID client state only after the replacement encrypted control
stream starts, then rediscovers the same physical USB Wacom and resends its
identity and descriptors. This remains model-independent within the supported
hardwired USB Wacom scope.

That run's roughly 50 FPS result was not an encoder regression. A development
client service had left overlapping stream processes, and the host reported two
active software-encoded sessions. Once the development stream was removed, the
single native 5120x2160 stream returned close to 60 FPS.
