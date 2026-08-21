# StationConnect Service Deployment

## PAM Broker

Install `stationconnect-pam-broker` as `/usr/bin/stationconnect-pam-broker`,
install the service in the system unit directory, and create the
`stationconnect-auth` system group through the supplied sysusers file. Add only
the unprivileged Sunshine service account to that group; an interactive shell
must be restarted before it gains the supplementary group.

Install `packaging/pam/remote-desktop` as `/etc/pam.d/remote-desktop` and create
the `remote-desktop-users` allow group before starting the broker. Do not add
root to either group. After package installation, run:

```bash
systemd-sysusers
systemctl enable --now stationconnect-pam-broker.service
systemctl status stationconnect-pam-broker.service
```

Sunshine activates StationConnect authentication only when it can read and
write `/run/stationconnect/auth.sock`. The broker forks one bounded worker for
each PAM conversation so the worker, rather than the persistent listener, owns
the logind session. The worker exits when its stream releases the authentication
socket; the service limits itself to 40 total tasks.

## Desktop Services

Install the launchers from `packaging/bin/` as `/usr/bin/stationconnect-host`
and `/usr/bin/stationconnect-client`. Production packages place their Sunshine
and Moonlight binaries under `/usr/libexec/stationconnect/`; a development
environment can override each binary path in its environment file.

Install `stationconnect-host.service` and `stationconnect-client.service` in
the system user-unit directory. They start inside the graphical session so the
host inherits the active Xorg authorization and the client inherits its
Wayland display. A launcher refuses to run without that graphical environment;
the host also refuses to run without access to the PAM broker socket. Enable
the applicable unit for the desktop account:

```bash
systemctl --user enable --now stationconnect-host.service
systemctl --user enable --now stationconnect-client.service
```

Install the matching example environment file as
`~/.config/stationconnect/host.env` or `client.env` and adjust it during
provisioning. The current host profile must select its qualified physical
output; `output_name=1` is specific to hardware-test-host and is not a universal default.
The 33-thread software profile is likewise qualified only for hardware-test-host's 128
logical CPUs. Launcher options are whitespace-delimited; do not use paths with
spaces in `STATIONCONNECT_HOST_OPTIONS`.

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
