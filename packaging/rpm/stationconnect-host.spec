%{!?stationconnect_version:%global stationconnect_version 0.1.0}
%{!?stationconnect_release:%global stationconnect_release 0.3}

Name:           stationconnect-host
Version:        %{stationconnect_version}
Release:        %{stationconnect_release}%{?dist}
%global debug_package %{nil}
Summary:        Authenticated StationConnect workstation host
License:        GPL-3.0-only
URL:            https://github.com/instinctual/stationconnectOS
Source0:        stationconnect-host-payload.tar.gz

Requires:       pam
Requires:       systemd
Requires:       systemd-udev
Requires:       firewalld-filesystem
Requires:       openssl-libs
Requires:       xorg-x11-server-Xorg
Requires(pre):  systemd
Requires(post): systemd
Requires(preun): systemd
Requires(postun): systemd

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

%post
%systemd_post stationconnect-pam-broker.service

%preun
%systemd_preun stationconnect-pam-broker.service

%postun
%systemd_postun_with_restart stationconnect-pam-broker.service

%files
%license /usr/share/licenses/stationconnect-host/LICENSE-Sunshine
%doc /usr/share/doc/stationconnect-host/README.md
%config(noreplace) /etc/pam.d/remote-desktop
/usr/bin/stationconnect-host
/usr/bin/stationconnect-pam-broker
/usr/libexec/stationconnect/sunshine
/usr/lib/systemd/system/stationconnect-pam-broker.service
/usr/lib/systemd/user/stationconnect-host.service
/usr/lib/sysusers.d/stationconnect.conf
/usr/lib/udev/rules.d/70-stationconnect-wacom.rules
/usr/lib/firewalld/services/stationconnect.xml
/usr/share/stationconnect/

%changelog
* Fri Aug 21 2026 StationConnect Engineering <engineering@stationconnect.invalid> - 0.1.0-0.3
- Bind authenticated streams to the matching desktop owner

* Fri Aug 21 2026 StationConnect Engineering <engineering@stationconnect.invalid> - 0.1.0-0.1
- Initial development package
