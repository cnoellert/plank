# Host Session Supervisor

StationConnect revision 0.17 evolves the graphical-login host user service into
`stationconnect-host.service`, a persistent machine-level Sender supervisor. The
supervisor starts at boot and asks `systemd-logind` for the active local X11
session on `seat0`. It accepts only `user` or `greeter` session classes in the
`active` state; remote, inactive, Wayland, TTY, lock-screen, and non-`seat0`
sessions are rejected.

No account, UID, display, or Xauthority path is fixed in code. For the selected
session, the supervisor resolves the UID through NSS and scans only processes
that logind assigns to that same session. It copies a small environment
whitelist (`DISPLAY`, `XAUTHORITY`, `XDG_RUNTIME_DIR`, and the session bus),
requires a local display, and verifies that the runtime directory and regular
Xauthority file belong to the selected UID.

The supervisor owns one machine-level Sender identity and launches its media
worker as root. The worker
keeps `HOME=/var/lib/stationconnect`, clears the inherited environment, and
receives only the selected session's validated X11 and runtime values. For
audio it receives the selected account's owned PulseAudio socket and cookie;
neither path is reused after a logind transition. This follows the persistent
workstation-Sender lifecycle used by current RGS instead of creating a
different host identity for every desktop owner.

Sunshine accepts an account only after receiving a versioned attachment update
over an inherited `SOCK_SEQPACKET` channel whose peer credentials prove that the
root supervisor created it. Each bounded update includes a monotonic generation,
the logind session identity, and a validated environment whitelist. Sunshine
rechecks the active seat and path ownership before acknowledging the update.
Malformed, stale, inactive, remote, or non-seat0 updates are rejected.

At GDM any valid non-root PAM account is eligible. In a user session, the PAM
account UID must equal the active seat owner. When logind selects a different
graphical session, the supervisor deliberately replaces the Sunshine media
worker. A fresh process is required because NVIDIA NvFBC/GLX cannot be safely
reinitialized after the X server that created it has exited. The machine
supervisor, TLS identity, state file, and workstation UUID remain stable.

The client masks this bounded replacement. It retains the successful PAM
credentials only in memory for the active stream, displays a reconnect overlay,
stops the old transport, retries authentication for up to 20 seconds, and starts
a fresh Desktop stream. Passwords and one-use tokens are cleared when consumed
or when the session ends; they are never written to settings, arguments,
environment variables, or logs. A local disconnect does not trigger reconnect.

The Sender uses the root-managed state file
`/var/lib/stationconnect/sunshine_state.json`. Sunshine's default per-user
state would assign separate workstation UUIDs to GDM and the desktop owner,
causing the client to reject the post-login worker as a different computer.
The packaged launcher enforces the machine state path. The TLS identity is
likewise machine-scoped.

Worker options are system-wide in `/etc/stationconnect/host.env`. The package
generates a stable TLS keypair under `/etc/stationconnect/tls/`; the private key
is mode `0640`, owned by `root:stationconnect-auth`.

Stage B—creating a correctly registered graphical session directly after PAM
authentication—remains separate work. The supervisor does not replay a
password, inject GDM keystrokes, enable autologin, restart Xorg, or attach to a
desktop owned by another user. The client may briefly show its reconnect overlay
while logind and Xorg publish the replacement desktop.

The Sunshine Sender still combines network, capture, media, and input functions
and therefore runs privileged. PAM remains a separate minimal broker,
root remote login is denied, and systemd limits the supervisor to
`CAP_DAC_READ_SEARCH` and `CAP_SYS_PTRACE`. Before `exec`, the child drops
`CAP_SYS_PTRACE`, leaving only `CAP_DAC_READ_SEARCH` for the selected user's
protected runtime and cookie paths. Read-only user homes, required address
families, and kernel/system protections apply to both. Collaboration can build
on this stable process identity, but still requires explicit viewer/controller
roles, input arbitration, and per-client lifecycle policy. Splitting
capture/input from the network-facing process remains a later hardening step.
