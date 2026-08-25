#!/usr/bin/env bash

set -euo pipefail

if (($# > 2)); then
  echo "usage: $0 [BUILD_DIR] [OUTPUT_DIR]" >&2
  exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
build_dir=$(realpath -m -- "${1:-${repo_dir}/build/package-host}")
output_dir=$(realpath -m -- "${2:-${repo_dir}/artifacts/packages}")
package_version=$(<"${repo_dir}/packaging/VERSION")
[[ $package_version =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+$ ]] || {
  echo "invalid shared package version: ${package_version}" >&2
  exit 1
}
rpm_version=${package_version%%-*}
rpm_release=${package_version#*-}

if [[ -n $(git -C "$repo_dir" status --porcelain --untracked-files=normal) ]]; then
  echo "refusing to package a dirty StationConnect source tree" >&2
  exit 1
fi

for command_name in cmake install python3 rpmbuild tar; do
  command -v "$command_name" >/dev/null || {
    echo "required command is unavailable: ${command_name}" >&2
    exit 1
  }
done

"${repo_dir}/scripts/build-host-package-binaries.sh" "$build_dir"

work_dir=$(mktemp -d --tmpdir stationconnect-host-rpm.XXXXXX)
cleanup() {
  rm -rf -- "$work_dir"
}
trap cleanup EXIT
payload_dir="${work_dir}/payload"
rpm_topdir="${work_dir}/rpmbuild"
mkdir -p "$payload_dir" "$rpm_topdir/SOURCES" "$rpm_topdir/SPECS" \
  "$rpm_topdir/BUILD" "$rpm_topdir/BUILDROOT" "$rpm_topdir/RPMS" "$rpm_topdir/SRPMS"

install -D -m 0755 "$build_dir/sunshine" \
  "$payload_dir/usr/libexec/stationconnect/sunshine"
install -D -m 0755 "$build_dir/stationconnect-pam-broker" \
  "$payload_dir/usr/bin/stationconnect-pam-broker"
install -D -m 0755 "$build_dir/stationconnect-host-supervisor" \
  "$payload_dir/usr/bin/stationconnect-host-supervisor"
install -D -m 0755 "$repo_dir/packaging/bin/stationconnect-host" \
  "$payload_dir/usr/bin/stationconnect-host"
install -D -m 0755 "$repo_dir/packaging/bin/stationconnect-host-certificate" \
  "$payload_dir/usr/libexec/stationconnect/stationconnect-host-certificate"
install -D -m 0755 "$repo_dir/packaging/bin/stationconnect-host-state" \
  "$payload_dir/usr/libexec/stationconnect/stationconnect-host-state"
install -D -m 0755 "$repo_dir/packaging/bin/stationconnect-display-prepare" \
  "$payload_dir/usr/libexec/stationconnect/stationconnect-display-prepare"
install -D -m 0644 "$repo_dir/packaging/systemd/stationconnect-host.service" \
  "$payload_dir/usr/lib/systemd/system/stationconnect-host.service"
install -D -m 0644 "$repo_dir/packaging/systemd/stationconnect-pam-broker.service" \
  "$payload_dir/usr/lib/systemd/system/stationconnect-pam-broker.service"
install -D -m 0644 "$repo_dir/packaging/systemd/stationconnect-display-prepare.service" \
  "$payload_dir/usr/lib/systemd/system/stationconnect-display-prepare.service"
install -D -m 0644 "$repo_dir/packaging/systemd/90-stationconnect.preset" \
  "$payload_dir/usr/lib/systemd/system-preset/90-stationconnect.preset"
install -D -m 0644 "$repo_dir/packaging/pam/remote-desktop" \
  "$payload_dir/etc/pam.d/remote-desktop"
install -D -m 0644 "$repo_dir/packaging/config/stationconnect.conf" \
  "$payload_dir/etc/stationconnect/stationconnect.conf"
install -d -m 0750 "$payload_dir/etc/stationconnect/tls"
install -d -m 0750 "$payload_dir/var/lib/stationconnect"
install -D -m 0644 "$repo_dir/packaging/sysusers.d/stationconnect.conf" \
  "$payload_dir/usr/lib/sysusers.d/stationconnect.conf"
install -D -m 0644 "$repo_dir/packaging/udev/70-stationconnect-wacom.rules" \
  "$payload_dir/usr/lib/udev/rules.d/70-stationconnect-wacom.rules"
install -D -m 0644 "$repo_dir/packaging/modules-load.d/stationconnect.conf" \
  "$payload_dir/usr/lib/modules-load.d/stationconnect.conf"
install -D -m 0644 "$repo_dir/packaging/firewalld/stationconnect.xml" \
  "$payload_dir/usr/lib/firewalld/services/stationconnect.xml"
python3 "$repo_dir/packaging/display/generate-virtual-edids.py" \
  "$payload_dir/usr/share/stationconnect/display"
install -D -m 0644 "$repo_dir/host/sunshine-fork/LICENSE" \
  "$payload_dir/usr/share/licenses/stationconnect-host/LICENSE-Sunshine"
install -D -m 0644 "$repo_dir/packaging/README.md" \
  "$payload_dir/usr/share/doc/stationconnect-host/README.md"
mkdir -p "$payload_dir/usr/share/stationconnect"
cp -aL "$build_dir/assets/." "$payload_dir/usr/share/stationconnect/"

source_epoch=$(git -C "$repo_dir" log -1 --format=%ct)
tar --sort=name --mtime="@${source_epoch}" --owner=0 --group=0 \
  --numeric-owner -C "$work_dir" -czf \
  "$rpm_topdir/SOURCES/stationconnect-host-payload.tar.gz" payload
install -m 0644 "$repo_dir/packaging/rpm/stationconnect-host.spec" \
  "$rpm_topdir/SPECS/stationconnect-host.spec"
rpmbuild -bb --define "_topdir ${rpm_topdir}" \
  --define "stationconnect_version ${rpm_version}" \
  --define "stationconnect_release ${rpm_release}" \
  "$rpm_topdir/SPECS/stationconnect-host.spec"

mkdir -p "$output_dir"
find "$rpm_topdir/RPMS" -type f -name '*.rpm' -exec install -m 0644 -t "$output_dir" {} +
rpm_file=$(find "$output_dir" -maxdepth 1 -type f \
  -name "stationconnect-host-${rpm_version}-${rpm_release}*.rpm" | sort | tail -1)
[[ -n $rpm_file ]] || {
  echo "host RPM was not produced for shared version ${package_version}" >&2
  exit 1
}
rpm -qpl "$rpm_file" >/dev/null
rpm -qpR "$rpm_file" | rg -q 'libX11\.so\.6'
rpm -qpl "$rpm_file" | rg -q '/usr/lib/modules-load\.d/stationconnect\.conf$'
rpm -qpl "$rpm_file" | rg -q '/usr/bin/stationconnect-host-supervisor$'
rpm -qpl "$rpm_file" | rg -q '/usr/libexec/stationconnect/stationconnect-host-certificate$'
rpm -qpl "$rpm_file" | rg -q '/usr/libexec/stationconnect/stationconnect-host-state$'
rpm -qpl "$rpm_file" | rg -q '/usr/libexec/stationconnect/stationconnect-display-prepare$'
rpm -qpl "$rpm_file" | rg -q '/usr/lib/systemd/system/stationconnect-host\.service$'
rpm -qpl "$rpm_file" | rg -q '/usr/lib/systemd/system/stationconnect-display-prepare\.service$'
rpm -qpl "$rpm_file" | rg -q '/etc/stationconnect/stationconnect\.conf$'
rpm -qpl "$rpm_file" | rg -q '/usr/share/stationconnect/display/virtual-1\.edid$'
rpm -qpl "$rpm_file" | rg -q '/usr/share/stationconnect/display/virtual-2\.edid$'
if rpm -qpl "$rpm_file" | rg -q '/etc/stationconnect/host\.env$|/usr/share/stationconnect/web/'; then
  echo "host RPM still contains legacy environment configuration or Web UI assets" >&2
  exit 1
fi
if rpm -qpl "$rpm_file" | rg -q '/usr/lib/systemd/user/stationconnect-host\.service$'; then
  echo "host RPM still contains the obsolete graphical-login user service" >&2
  exit 1
fi
echo "host_rpm=${rpm_file}"
echo "stationconnect_package_version=${package_version}"
echo "host_rpm_manifest_gate=pass"
