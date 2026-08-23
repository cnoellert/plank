%{!?stationconnect_version:%global stationconnect_version 0.1.0}
%{!?stationconnect_release:%global stationconnect_release 0.5}

Name:           stationconnect-host
Version:        %{stationconnect_version}
Release:        %{stationconnect_release}%{?dist}
%global debug_package %{nil}
Summary:        Authenticated StationConnect workstation host
License:        GPL-3.0-only
URL:            https://github.com/instinctual/stationconnect
Source0:        stationconnect-host-payload.tar.gz

Requires:       pam
Requires:       systemd
Requires:       systemd-udev
Requires:       firewalld-filesystem
Requires:       openssl-libs
Requires:       xorg-x11-server-Xorg
Requires(pre):  systemd
Requires(post): systemd systemd-udev kmod
Requires(post): openssl
Requires(post): hostname
Requires(preun): systemd
Requires(postun): systemd
Obsoletes:      plome-pam-helper < 0.2.0

%description
StationConnect host services, authentication broker, media host, and
workstation integration for the qualified RHEL/Rocky deployment.

%prep
%setup -q -c -T
tar -xzf %{SOURCE0}

%build

%install
mkdir -p %{buildroot}
cp -a payload/. %{buildroot}/

%pre
%sysusers_create stationconnect.conf

%post
/usr/libexec/stationconnect/stationconnect-host-certificate \
  /etc/stationconnect/tls/cert.pem /etc/stationconnect/tls/key.pem || exit 1
/usr/bin/chown root:stationconnect-auth \
  /etc/stationconnect/tls/key.pem /etc/stationconnect/tls/cert.pem || exit 1
/usr/bin/chmod 0640 /etc/stationconnect/tls/key.pem || exit 1
/usr/bin/chmod 0644 /etc/stationconnect/tls/cert.pem || exit 1
/usr/libexec/stationconnect/stationconnect-host-state \
  /var/lib/stationconnect/sunshine_state.json || exit 1
/usr/bin/chown root:root \
  /var/lib/stationconnect/sunshine_state.json || exit 1
/usr/bin/chmod 0600 /var/lib/stationconnect/sunshine_state.json || exit 1
%systemd_post stationconnect-pam-broker.service stationconnect-host.service
/usr/bin/udevadm control --reload-rules >/dev/null 2>&1 || :
/usr/sbin/modprobe uhid >/dev/null 2>&1 || :
/usr/bin/udevadm trigger --action=change --subsystem-match=misc --sysname-match=uhid >/dev/null 2>&1 || :

%preun
%systemd_preun stationconnect-pam-broker.service stationconnect-host.service

%postun
%systemd_postun_with_restart stationconnect-pam-broker.service stationconnect-host.service

%files
%license /usr/share/licenses/stationconnect-host/LICENSE-Sunshine
%doc /usr/share/doc/stationconnect-host/README.md
%config(noreplace) /etc/pam.d/remote-desktop
%config(noreplace) /etc/stationconnect/host.env
%dir %attr(0755,root,root) /etc/stationconnect
%dir %attr(0750,root,stationconnect-auth) /etc/stationconnect/tls
%ghost %config(noreplace) %attr(0644,root,stationconnect-auth) /etc/stationconnect/tls/cert.pem
%ghost %config(noreplace) %attr(0640,root,stationconnect-auth) /etc/stationconnect/tls/key.pem
%dir %attr(0750,root,root) /var/lib/stationconnect
%ghost %attr(0600,root,root) /var/lib/stationconnect/sunshine_state.json
/usr/bin/stationconnect-host
/usr/bin/stationconnect-host-supervisor
/usr/bin/stationconnect-pam-broker
/usr/libexec/stationconnect/sunshine
/usr/libexec/stationconnect/stationconnect-host-certificate
/usr/libexec/stationconnect/stationconnect-host-state
/usr/lib/systemd/system/stationconnect-pam-broker.service
/usr/lib/systemd/system/stationconnect-host.service
/usr/lib/systemd/system-preset/90-stationconnect.preset
/usr/lib/sysusers.d/stationconnect.conf
/usr/lib/modules-load.d/stationconnect.conf
/usr/lib/udev/rules.d/70-stationconnect-wacom.rules
/usr/lib/firewalld/services/stationconnect.xml
/usr/share/stationconnect/

%changelog
* Sat Aug 22 2026 StationConnect Engineering <engineering@stationconnect.invalid> - 0.1.0-0.14
- Keep host and client release numbering synchronized for the ZeroTier packet fix.

* Sat Aug 22 2026 StationConnect Engineering <engineering@stationconnect.invalid> - 0.1.0-0.13
- Keep host and client release numbering synchronized for native-resolution streaming.

* Sat Aug 22 2026 StationConnect Engineering <engineering@stationconnect.invalid> - 0.1.0-0.12
- Keep one root-managed Sunshine UUID across GDM and desktop workers.
- Prevent per-session homes from appearing as duplicate client workstations.
- Run a capability-bounded machine Sender while keeping PAM isolated.

* Sat Aug 22 2026 StationConnect Engineering <engineering@stationconnect.invalid> - 0.1.0-0.11
- Generate and validate the DNS SAN required by the client TLS profile.
- Atomically repair invalid host certificates while preserving valid keys.

* Sat Aug 22 2026 StationConnect Engineering <engineering@stationconnect.invalid> - 0.1.0-0.10
- Start a root supervisor at boot and run the host as the active seat0 user.
- Support an authenticated GDM Stage A worker without hardcoded UIDs or displays.

* Sat Aug 22 2026 StationConnect Engineering <engineering@stationconnect.invalid> - 0.1.0-0.9
- Keep host and client release numbering synchronized for the VA-API dependency fix.

* Sat Aug 22 2026 StationConnect Engineering <engineering@stationconnect.invalid> - 0.1.0-0.8
- Keep host and client release numbering synchronized for the client packaging fix.

* Sat Aug 22 2026 StationConnect Engineering <engineering@stationconnect.invalid> - 0.1.0-0.7
- Keep host and client revisions synchronized for audio phase convergence.

* Fri Aug 21 2026 StationConnect Engineering <engineering@stationconnect.invalid> - 0.1.0-0.6
- Keep host and client package revisions synchronized for A/V backlog recovery.

* Fri Aug 21 2026 StationConnect Engineering <engineering@stationconnect.invalid> - 0.1.0-0.5
- Synchronize host release with adaptive client A/V correction

* Fri Aug 21 2026 StationConnect Engineering <engineering@stationconnect.invalid> - 0.1.0-0.4
- Load UHID and apply tablet device access during package installation

* Fri Aug 21 2026 StationConnect Engineering <engineering@stationconnect.invalid> - 0.1.0-0.3
- Bind authenticated streams to the matching desktop owner
- Replace the legacy plome PAM helper package

* Fri Aug 21 2026 StationConnect Engineering <engineering@stationconnect.invalid> - 0.1.0-0.1
- Initial development package
