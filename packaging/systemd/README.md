# PAM Broker Deployment

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
write `/run/stationconnect/auth.sock`. Configure its `bind_address` to the VPN
address and enforce the same interface boundary in the host firewall.
