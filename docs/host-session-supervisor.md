# Host Session Supervisor

StationConnect revision 0.10 replaces the graphical-login host user service
with `stationconnect-host.service`, a persistent system supervisor. The
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

The root process never performs capture or encoding. Before executing
`stationconnect-host`, its child installs the account's normal supplementary
groups plus `stationconnect-auth`, changes to the account GID and UID, clears
the inherited environment, and reconstructs only the values needed by the
worker. The extra group provides access to the PAM broker socket and packaged
TLS key without granting it permanently to interactive accounts.

At GDM, the worker runs as the dynamically discovered greeter account.
Sunshine permits a different PAM-authenticated account only when it receives a
one-use attestation over an inherited local socket whose peer credentials prove
that the root supervisor created it. The attested session must still be the
active local `seat0` greeter in logind when authorization is checked. Once GDM
creates the user's desktop, the supervisor terminates the greeter worker before
starting a worker as the desktop owner. A client must reconnect after this
Stage A transition.

Worker options are system-wide in `/etc/stationconnect/host.env`. The package
generates a stable TLS keypair under `/etc/stationconnect/tls/`; the private key
is mode `0640`, owned by `root:stationconnect-auth`.

Stage B—creating a correctly registered graphical session directly after PAM
authentication—remains separate work. The supervisor does not replay a
password, inject GDM keystrokes, enable autologin, restart Xorg, or attach to a
desktop owned by another user.

The current Sunshine worker still combines network, capture, media, and input
functions. The service bounds the supervisor's capabilities, and the child
loses them when it changes UID, but several systemd filesystem/device/network
restrictions cannot be applied to the supervisor cgroup without also breaking
the worker. Splitting those responsibilities into separate service cgroups
remains a later privilege-separation step.
