# StationConnect Service Deployment

## PAM Broker

Install `stationconnect-pam-broker` as `/usr/bin/stationconnect-pam-broker`,
install the service in the system unit directory, and create the
`stationconnect-auth` system group through the supplied sysusers file. Add only
the unprivileged worker to that group. The supervisor supplies this one
supplementary group while dropping to the selected session UID; interactive
desktop accounts do not need permanent membership.

Install `packaging/pam/remote-desktop` as `/etc/pam.d/remote-desktop` and create
the `remote-desktop-users` allow group before starting the broker. Do not add
root to either group. After package installation, run:

```bash
systemd-sysusers
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

This is Stage A session handling: an authenticated client can see GDM, but must
complete the graphical login and reconnect after the worker transition. The
supervisor does not inject input into GDM or create a new graphical session.

`stationconnect-display-prepare.service` runs before the display manager. It
keeps the workstation's Autodesk-derived `/etc/X11/xorg.conf` as the baseline
and atomically adds or removes only
`/etc/X11/xorg.conf.d/99-stationconnect-headless.conf`. Configure `[display]`
in `stationconnect.conf` with `virtual_outputs = off`, `single`, or
`dual-horizontal`. `virtual_mode_1` and `virtual_mode_2` independently select
one of the package-documented 60 Hz monitor presets; output 2 is ignored for a
single-head layout. The default is `off`. A changed topology is applied on reboot;
the helper refuses to replace its overlay while the display manager is active.
Package removal deletes only an overlay carrying StationConnect's generated
file marker; it does not alter the currently running X server.

Install `stationconnect-client.service` in the system user-unit directory so
the client inherits its Wayland display. Enable the services with:

```bash
sudo systemctl enable --now stationconnect-pam-broker.service \
  stationconnect-host.service
systemctl --user enable --now stationconnect-client.service
```

Configure every host runtime option in the single root-managed
`/etc/stationconnect/stationconnect.conf`. Client options remain in
`~/.config/stationconnect/client.env`. The current host profile must select its qualified physical
output; `output_name=1` is specific to hardware-test-host and is not a universal default.
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
