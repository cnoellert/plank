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
environment can override each binary path in its environment file.

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

Install `stationconnect-client.service` in the system user-unit directory so
the client inherits its Wayland display. Enable the services with:

```bash
sudo systemctl enable --now stationconnect-pam-broker.service \
  stationconnect-host.service
systemctl --user enable --now stationconnect-client.service
```

Configure shared host worker options in `/etc/stationconnect/host.env` and
client options in `~/.config/stationconnect/client.env`. The current host
profile must select its qualified physical
output; `output_name=1` is specific to hardware-test-host and is not a universal default.
The software profile expands x264 worker affinity to the qualified CPU set and
uses 16 slices on hardware-test-host; neither the CPU count nor slice count is a universal
default. Launcher options are whitespace-delimited; do not use paths with spaces
in `STATIONCONNECT_HOST_OPTIONS`.

Leave Sunshine's `bind_address` empty so discovery and media listen on all
available IPv4 and IPv6 interfaces. On the client, the approved-interface
setting applies to StationConnect TLS control and PAM credentials; discovery
and media transport may use every interface. Enforce
the intended deployment boundary in the host firewall even though the
process listens on wildcard addresses.

Install `packaging/firewalld/stationconnect.xml` in firewalld's service
directory, reload firewalld, and enable it only in the zone assigned to the
approved StationConnect/VPN interface. Do not add the service to the default
zone. The development hardware-test-host host currently has firewalld disabled, so its
wildcard listeners are suitable only for the isolated qualification network.
