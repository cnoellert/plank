# StationConnect Service Deployment

## PAM Broker

Install `stationconnect-pam-broker` as `/usr/bin/stationconnect-pam-broker`,
install the service in the system unit directory, and install
`packaging/pam/stationconnect-host` as `/etc/pam.d/stationconnect-host`.
StationConnect denies root remote login by default and delegates account
authorization to the host's PAM/SSSD policy, including FreeIPA HBAC. The
administrator may set `security.allow_root_login = true` in
`stationconnect.conf`; this does not bypass PAM or active-desktop ownership.
StationConnect has no application-specific user allowlist.
Restart `stationconnect-pam-broker.service` after changing this setting; the
broker loads and validates it once at startup.

FreeIPA deployments use the exact PAM service identifier
`stationconnect-host` in their HBAC service and rules. Directory-policy changes
then require no StationConnect host or client update. Local service accounts
must retain locked passwords because IPA HBAC does not govern local identities.

The root media worker is the broker's only local client. The broker runtime
directory and socket are therefore `root:root` mode `0700` and `0600` instead
of being exposed through a supplementary group. After package installation,
run:

```bash
systemctl enable --now stationconnect-pam-broker.service
systemctl status stationconnect-pam-broker.service
```

Sunshine activates StationConnect authentication only when it can read and
write `/run/stationconnect/pam/auth.sock`. The broker forks one bounded worker for
each PAM conversation so the worker, rather than the persistent listener, owns
the logind session. The worker exits when its stream releases the authentication
socket; the service limits itself to 40 total tasks.

## Host Supervisor and Client Service

Install the launchers from `packaging/bin/` as `/usr/bin/stationconnect-host`
and `/usr/bin/stationconnect-client`. Production packages place their Sunshine
and Moonlight binaries under `/usr/libexec/stationconnect/`; a development
environment can override the binary path while invoking the launcher.

Build and bundle the pinned FFmpeg 9 client runtime next to Moonlight before
packaging it:

```bash
./scripts/build-client-ffmpeg.sh /usr/libexec/stationconnect
PKG_CONFIG_PATH=build/client-ffmpeg-9.0.1/install/lib/pkgconfig qmake6 ...
```

The script verifies the FFmpeg 9.0.1 source checksum and installs the required
shared libraries and LGPL license files under `lib/`. The client launcher
prepends that private directory to `LD_LIBRARY_PATH`, preventing an older
distribution FFmpeg from being selected at runtime.

Install `stationconnect-host.service` in the system unit directory. It starts
at boot, queries logind for the active local X11 session on `seat0`, validates
the discovered Xauthority file against the session UID, and drops root before
executing the media host. At GDM it launches as the discovered greeter UID; it
does not hardcode `gdm`, a numeric UID, `DISPLAY`, or an Xauthority path. On a
GDM-to-user transition it stops the old worker before starting the new one.

This is Stage A session handling: an authenticated client can see GDM, and the
client automatically reconnects while the supervisor replaces the greeter
worker with the authenticated desktop worker. The supervisor does not inject
input into GDM or create a new graphical session.

`stationconnect-display-prepare.service` runs before the display manager. It
keeps the workstation's Autodesk-derived `/etc/X11/xorg.conf` as the baseline
and atomically adds or removes only
`/etc/X11/xorg.conf.d/99-stationconnect-headless.conf`. Configure `[display]`
in `stationconnect.conf` with `startup_layout = physical`, `single`, or
`dual-horizontal`. `virtual_mode_1` and `virtual_mode_2` independently select
one of the package-documented 60 Hz monitor presets. A single-head Xorg overlay
keeps the second virtual connector present but inactive so the same
PAM-authenticated desktop owner can later switch resolutions or enable the
second head through the supervisor's allowlisted live-XRandR path. Other users
are refused. The default is `physical`. A changed static topology is applied on
reboot; the helper refuses to replace its overlay while the display manager is active.
Package removal deletes only an overlay carrying StationConnect's generated
file marker; it does not alter the currently running X server.

The administrator setting describes the boot layout. A host with
`startup_layout = physical` removes the headless overlay but may lease a
bookmark-selected logical layout over connected native scanouts for one remote
session. The supervisor restores the exact pre-session NVIDIA MetaMode at
disconnect. A host with `single` or `dual-horizontal` retains the packaged-EDID
headless workflow and does not advertise a physical bookmark layout. The RPM explicitly
applies the packaged preset on upgrade so the pre-GDM cleanup cannot remain
disabled while a stale owned overlay survives a reboot.

Install `stationconnect-client.service` in the system user-unit directory so
the client inherits its Wayland display. Enable the services with:

```bash
sudo systemctl enable --now stationconnect-pam-broker.service \
  stationconnect-display-prepare.service \
  stationconnect-host.service
systemctl --user enable --now stationconnect-client.service
```

Configure every host runtime option in the single root-managed
`/etc/stationconnect/stationconnect.conf`. Client options remain in
`~/.config/stationconnect/client.env`. Capture selection follows the
authenticated bookmark topology for each session; there is no fixed
administrator capture-output selector.
The software profile expands x264 worker affinity to the qualified CPU set and
uses 16 slices on hardware-test-host; neither the CPU count nor slice count is a universal
default. The host configuration uses INI-style section headers and one globally
scoped `key = value` setting per line. The package no longer loads a host
environment file, and shell environment syntax is not accepted in the host
configuration.

mDNS is disabled by default on both sides. Set
`stationconnect_mdns_discovery = true` in the host `stationconnect.conf` to publish
the host with Avahi, or set `STATIONCONNECT_MDNS_DISCOVERY=1` in the client env
file to browse for advertised workstations. The client launcher loads its env
file for app-icon launches as well as user-service launches. Saved and manually
entered workstations continue to connect when mDNS is disabled.

The Linux client mirrors its already-redacted stderr/journal output to private,
persistent per-user files under `$XDG_STATE_HOME/stationconnect/logs/`, or
`~/.local/state/stationconnect/logs/` when `XDG_STATE_HOME` is unset or not an
absolute path. The directory is mode `0700`; each timestamped
`stationconnect-client-*.log` is mode `0600`, capped at 10 MiB, and only the
newest 10 files are retained. Continue using
`journalctl --user -u stationconnect-client.service` for live service output.

The host writes its streaming runtime diagnostics to
`/var/log/stationconnect/stationconnect-host.log` while continuing to mirror
the same output to `journalctl -u stationconnect-host.service`. systemd creates
the root-only log directory with mode `0700`, and the service umask creates log
files with mode `0600`. The active file rotates at 10 MiB and retains
`stationconnect-host.log.1` through `.10`. Supervisor messages that occur
outside the media worker remain available in the service journal.

The StationConnect host is built without Sunshine's browser configuration
server and without its frontend assets. There is no listener on the former Web
UI port and no second writable configuration path. Do not remove or block the
separate NVHTTP, HTTPS, RTSP, audio, video, or control services required by the
client protocol.

Leave Sunshine's `bind_address` empty so media listens on all available IPv4
and IPv6 interfaces. When explicitly enabled, mDNS discovery also uses the
available interfaces. The client does not restrict which local network
interface carries control, credentials, or media. Enforce the intended
deployment boundary in the host firewall even though the process listens on
wildcard addresses.

Install `packaging/firewalld/stationconnect.xml` in firewalld's service
directory, reload firewalld, and enable it only in the zone assigned to the
approved StationConnect/VPN interface. Do not add the service to the default
zone. The development hardware-test-host host currently has firewalld disabled, so its
wildcard listeners are suitable only for the isolated qualification network.
