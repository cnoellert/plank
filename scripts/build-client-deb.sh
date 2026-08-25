#!/usr/bin/env bash

set -euo pipefail

if (($# < 2 || $# > 4)); then
  echo "usage: $0 MOONLIGHT_BINARY FFMPEG_WORK_DIR [OUTPUT_DIR] [MOONLIGHT_SOURCE_DIR]" >&2
  exit 2
fi

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
moonlight_binary=$(realpath -- "$1")
ffmpeg_work_dir=$(realpath -- "$2")
output_dir=$(realpath -m -- "${3:-${repo_dir}/artifacts/packages}")
moonlight_source_dir=$(realpath -- "${4:-${repo_dir}/client/moonlight-qt-fork}")
common_source_dir="${moonlight_source_dir}/moonlight-common-c/moonlight-common-c"
nanors_source_dir="${common_source_dir}/nanors"
ffmpeg_version=9.0.1
ffmpeg_sha256=cf38e0e28c7e5605942c4a77755349b0145804a397af37eb1fb4c77cb237f635
ffmpeg_lib_dir="${ffmpeg_work_dir}/install/lib"
if [[ -f ${ffmpeg_work_dir}/COPYING.LGPLv2.1 ]]; then
  ffmpeg_source_dir="$ffmpeg_work_dir"
else
  ffmpeg_source_dir="${ffmpeg_work_dir}/ffmpeg-${ffmpeg_version}"
fi
ffmpeg_archive=""
for archive_candidate in \
  "${ffmpeg_work_dir}/ffmpeg-${ffmpeg_version}.tar.xz" \
  "$(dirname -- "$ffmpeg_work_dir")/ffmpeg-${ffmpeg_version}.tar.xz"; do
  if [[ -f $archive_candidate ]]; then
    ffmpeg_archive=$archive_candidate
    break
  fi
done
package_version=$(<"${repo_dir}/packaging/VERSION")
[[ $package_version =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+$ ]] || {
  echo "invalid shared package version: ${package_version}" >&2
  exit 1
}

for command_name in cmp dpkg-deb dpkg-shlibdeps du git install md5sum realpath rg sha256sum; do
  command -v "$command_name" >/dev/null || {
    echo "required command is unavailable: ${command_name}" >&2
    exit 1
  }
done

[[ -x ${moonlight_binary} ]] || {
  echo "Moonlight binary is not executable: ${moonlight_binary}" >&2
  exit 1
}
[[ -f ${moonlight_source_dir}/LICENSE ]] || {
  echo "Moonlight source tree is unavailable: ${moonlight_source_dir}" >&2
  exit 1
}
[[ -f ${nanors_source_dir}/LICENSE ]] || {
  echo "nanors source tree is unavailable: ${nanors_source_dir}" >&2
  exit 1
}
if [[ -n $(git -C "$moonlight_source_dir" status --porcelain) ]]; then
  echo "Moonlight source tree is dirty; refusing to create a release package" >&2
  exit 1
fi

for library in \
  libavcodec.so.63 libavutil.so.61 libswscale.so.10; do
  [[ -e ${ffmpeg_lib_dir}/${library} ]] || {
    echo "required FFmpeg ${ffmpeg_version} library is unavailable: ${library}" >&2
    exit 1
  }
done
for license_file in COPYING.LGPLv2.1 COPYING.LGPLv3; do
  [[ -f ${ffmpeg_source_dir}/${license_file} ]] || {
    echo "FFmpeg license file is unavailable: ${ffmpeg_source_dir}/${license_file}" >&2
    exit 1
  }
done
if [[ -n $ffmpeg_archive ]]; then
  printf '%s  %s\n' "$ffmpeg_sha256" "$ffmpeg_archive" | \
    sha256sum --check --status
  echo "ffmpeg_source_archive_gate=pass"
else
  # The prepared Development NUC tree is a retained, Git-ignored build input.
  # Cleanup intentionally does not retain a duplicate release archive. Verify
  # the extracted release identity instead of downloading the same archive for
  # every package build.
  [[ -f ${ffmpeg_source_dir}/VERSION ]] &&
    [[ $(<"${ffmpeg_source_dir}/VERSION") == "$ffmpeg_version" ]] &&
    [[ -f ${ffmpeg_source_dir}/RELEASE ]] &&
    [[ $(<"${ffmpeg_source_dir}/RELEASE") == "$ffmpeg_version" ]] || {
      echo "prepared FFmpeg source identity is not ${ffmpeg_version}" >&2
      exit 1
    }
  echo "ffmpeg_prepared_source_identity_gate=pass"
fi

moonlight_commit=$(git -C "$moonlight_source_dir" rev-parse HEAD)
common_commit=$(git -C "$common_source_dir" rev-parse HEAD)
nanors_commit=$(git -C "$nanors_source_dir" rev-parse HEAD)
source_epoch=$(git -C "$moonlight_source_dir" log -1 --format=%ct)
work_dir=$(mktemp -d --tmpdir stationconnect-client-deb.XXXXXX)
cleanup() {
  rm -rf -- "$work_dir"
}
trap cleanup EXIT
stage_dir="${work_dir}/debian/stationconnect-client"
private_lib_dir="${stage_dir}/usr/libexec/stationconnect/lib"
mkdir -p "$stage_dir/DEBIAN" "$private_lib_dir" "$work_dir/debian"

install -D -m 0755 "$moonlight_binary" \
  "$stage_dir/usr/libexec/stationconnect/moonlight"
install -D -m 0755 "$repo_dir/packaging/bin/stationconnect-client" \
  "$stage_dir/usr/bin/stationconnect-client"
install -D -m 0644 "$repo_dir/packaging/systemd/stationconnect-client.service" \
  "$stage_dir/usr/lib/systemd/user/stationconnect-client.service"
install -D -m 0644 "$repo_dir/packaging/systemd/client.env.example" \
  "$stage_dir/usr/share/doc/stationconnect-client/client.env.example"
install -D -m 0644 \
  "$repo_dir/packaging/desktop/la.instinctual.StationConnect.desktop" \
  "$stage_dir/usr/share/applications/la.instinctual.StationConnect.desktop"
install -D -m 0644 \
  "$repo_dir/packaging/udev/70-stationconnect-client-wacom.rules" \
  "$stage_dir/usr/lib/udev/rules.d/70-stationconnect-client-wacom.rules"
install -m 0755 "$repo_dir/packaging/deb/postinst" \
  "$stage_dir/DEBIAN/postinst"
install -m 0755 "$repo_dir/packaging/deb/postrm" \
  "$stage_dir/DEBIAN/postrm"
install -D -m 0644 "$moonlight_source_dir/app/res/stationconnect-logo.png" \
  "$stage_dir/usr/share/icons/hicolor/512x512/apps/stationconnect-client.png"
install -D -m 0644 "$moonlight_source_dir/LICENSE" \
  "$stage_dir/usr/share/doc/stationconnect-client/copyright"
install -D -m 0644 "$nanors_source_dir/LICENSE" \
  "$stage_dir/usr/share/doc/stationconnect-client/COPYING.nanors"
install -D -m 0644 "$ffmpeg_source_dir/COPYING.LGPLv2.1" \
  "$stage_dir/usr/share/doc/stationconnect-client/COPYING.FFmpeg.LGPLv2.1"
install -D -m 0644 "$ffmpeg_source_dir/COPYING.LGPLv3" \
  "$stage_dir/usr/share/doc/stationconnect-client/COPYING.FFmpeg.LGPLv3"

for library in libavcodec libavutil libswscale; do
  cp -a "${ffmpeg_lib_dir}/${library}.so."* "$private_lib_dir/"
done
cmp --silent "$moonlight_source_dir/app/res/stationconnect-logo.png" \
  "$stage_dir/usr/share/icons/hicolor/512x512/apps/stationconnect-client.png" || {
  echo "packaged client logo differs from the approved runtime source" >&2
  exit 1
}
version_output=$(
  QT_QPA_PLATFORM=offscreen \
    LD_LIBRARY_PATH="$private_lib_dir" \
    "$stage_dir/usr/libexec/stationconnect/moonlight" --version 2>&1
)
grep -Fxq "StationConnect ${package_version}" <<<"$version_output" || {
  echo "packaged client did not report the expected StationConnect version" >&2
  printf '%s\n' "$version_output" >&2
  exit 1
}
echo "client_headless_version_gate=pass"
echo "client_logo_identity_gate=pass"
cat >"$work_dir/debian/control" <<'EOF'
Source: stationconnect-client
Section: net
Priority: optional
Maintainer: StationConnect Engineering <engineering@stationconnect.invalid>
Standards-Version: 4.7.0

Package: stationconnect-client
Architecture: amd64
Description: StationConnect remote workstation client
EOF
cat >"$work_dir/shlibs.local" <<'EOF'
libavcodec 63 stationconnect-client
libavutil 61 stationconnect-client
libswscale 10 stationconnect-client
EOF

(
  cd "$work_dir"
  mapfile -d '' packaged_elfs < <(
    find debian/stationconnect-client/usr/libexec/stationconnect \
      -type f -print0 | sort -z
  )
  dpkg-shlibdeps -O -Lshlibs.local -xstationconnect-client \
    -l"$private_lib_dir" \
    "${packaged_elfs[@]}"
) >"$work_dir/shlibdeps"
depends=$(sed -n 's/^shlibs:Depends=//p' "$work_dir/shlibdeps")
[[ -n ${depends} ]] || {
  echo "dpkg-shlibdeps did not produce client dependencies" >&2
  exit 1
}

cat >"$stage_dir/usr/share/doc/stationconnect-client/BUILD-INFO" <<EOF
Moonlight-Qt commit: ${moonlight_commit}
moonlight-common-c commit: ${common_commit}
nanors commit: ${nanors_commit}
FFmpeg version: ${ffmpeg_version}
FFmpeg source SHA-256: ${ffmpeg_sha256}
Moonlight binary SHA-256: $(sha256sum "$moonlight_binary" | awk '{print $1}')
EOF
installed_size=$(du -sk "$stage_dir/usr" | awk '{print $1}')
sed -e "s/@VERSION@/${package_version}/" \
  -e "s/@INSTALLED_SIZE@/${installed_size}/" \
  -e "s/@DEPENDS@/${depends}/" \
  "$repo_dir/packaging/deb/control.in" >"$stage_dir/DEBIAN/control"

find "$stage_dir" -type d -exec chmod 0755 {} +
chmod 0644 "$stage_dir/DEBIAN/control" \
  "$stage_dir/usr/share/doc/stationconnect-client/BUILD-INFO"

(
  cd "$stage_dir"
  find usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums
)
chmod 0644 "$stage_dir/DEBIAN/md5sums"
find "$stage_dir" -exec touch -h -d "@${source_epoch}" {} +
export SOURCE_DATE_EPOCH="$source_epoch"
mkdir -p "$output_dir"
deb_file="${output_dir}/stationconnect-client_${package_version}_amd64.deb"
dpkg-deb --root-owner-group --uniform-compression -Zxz --build "$stage_dir" "$deb_file"

dpkg-deb --info "$deb_file" >/dev/null
dpkg-deb --contents "$deb_file" >/dev/null
for required_package in \
  intel-media-va-driver \
  qml6-module-qtquick \
  qml6-module-qtquick-controls \
  qml6-module-qtquick-layouts \
  qml6-module-qtquick-window \
  udev; do
  dpkg-deb --field "$deb_file" Depends | grep -Fq "$required_package" || {
    echo "client DEB is missing required dependency: ${required_package}" >&2
    exit 1
  }
done
package_manifest=$(dpkg-deb --contents "$deb_file")
grep -Fq './usr/share/applications/la.instinctual.StationConnect.desktop' \
  <<<"$package_manifest" || {
  echo "client DEB is missing the canonical StationConnect desktop entry" >&2
  exit 1
}
grep -Fq './usr/share/icons/hicolor/512x512/apps/stationconnect-client.png' \
    <<<"$package_manifest" || {
  echo "client DEB is missing the StationConnect application icon" >&2
  exit 1
}
if grep -Fq './usr/share/applications/stationconnect-client.desktop' \
    <<<"$package_manifest"; then
  echo "client DEB still contains the superseded desktop entry" >&2
  exit 1
fi
grep -Fq './usr/lib/udev/rules.d/70-stationconnect-client-wacom.rules' \
  <<<"$package_manifest" || {
  echo "client DEB is missing the Wacom udev access rule" >&2
  exit 1
}
grep -Fq './usr/share/doc/stationconnect-client/COPYING.nanors' \
  <<<"$package_manifest" || {
  echo "client DEB is missing the nanors license" >&2
  exit 1
}
control_audit_dir=$(mktemp -d --tmpdir stationconnect-client-control.XXXXXX)
dpkg-deb --control "$deb_file" "$control_audit_dir"
for maintainer_script in postinst postrm; do
  [[ -x ${control_audit_dir}/${maintainer_script} ]] || {
    echo "client DEB is missing executable ${maintainer_script}" >&2
    exit 1
  }
  sh -n "${control_audit_dir}/${maintainer_script}"
done
rm -rf -- "$control_audit_dir"
"${repo_dir}/scripts/audit-package-runtime.sh" \
  "$stage_dir/usr/libexec/stationconnect/moonlight" "$private_lib_dir"
dpkg-deb --field "$deb_file" Depends | rg -q 'libqt6core6'
dpkg-deb --field "$deb_file" Depends | rg -q 'libdecor-0-plugin-1-cairo'
if dpkg-deb --field "$deb_file" Depends | rg -q 'libdecor-0-plugin-1-gtk'; then
  echo "client DEB still requires the main-thread-only GTK libdecor plugin" >&2
  exit 1
fi
echo "client_deb=${deb_file}"
echo "client_deb_manifest_gate=pass"
