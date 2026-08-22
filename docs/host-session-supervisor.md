# Host Session Supervisor

StationConnect revision 0.12 evolves the graphical-login host user service into
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

The supervisor launches one machine-level Sender identity as root. The Sender
keeps `HOME=/var/lib/stationconnect`, clears the inherited environment, and
receives only the selected session's validated X11 and runtime values. For
audio it receives the selected account's owned PulseAudio socket and cookie;
neither path is reused after a logind transition. This follows the persistent
workstation-Sender lifecycle used by current RGS instead of creating a
different host identity for every desktop owner.

Sunshine accepts an account only after receiving a one-use attestation over an
inherited local socket whose peer credentials prove that the root supervisor
created it. At GDM any valid non-root PAM account is eligible. In a user
session, the PAM account UID must equal the active seat owner. The supervisor
rechecks logind when authorization occurs and replaces the media child when
Xorg changes during login. The system service, TLS certificate, and workstation
UUID remain stable across that transition; the current monolithic Sunshine
child can still cause a brief stream reconnect while the display is replaced.

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
desktop owned by another user.

The current Sunshine Sender still combines network, capture, media, and input
functions and therefore runs privileged. PAM remains a separate minimal broker,
root remote login is denied, and systemd limits the supervisor to
`CAP_DAC_READ_SEARCH` and `CAP_SYS_PTRACE`. Before `exec`, the child drops
`CAP_SYS_PTRACE`, leaving only `CAP_DAC_READ_SEARCH` for the selected user's
protected runtime and cookie paths. Read-only user homes, required address
families, and kernel/system protections apply to both. Splitting capture/input
from the network-facing process remains a later hardening step.
