#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
work_dir=$(mktemp -d --tmpdir stationconnect-display-test.XXXXXX)
cleanup() {
  rm -rf -- "$work_dir"
}
trap cleanup EXIT

config_file="${work_dir}/stationconnect.conf"
output_file="${work_dir}/xorg.conf.d/99-stationconnect-headless.conf"
edid_dir="${work_dir}/display"
fake_bin="${work_dir}/bin"
mkdir -p "$fake_bin"
python3 "$repo_dir/packaging/display/generate-virtual-edids.py" "$edid_dir" >/dev/null
[[ $(wc -c <"${edid_dir}/virtual-1-3840x2160.edid") -eq 384 ]]
[[ $(wc -c <"${edid_dir}/virtual-1-2560x2160.edid") -eq 384 ]]
[[ $(wc -c <"${edid_dir}/virtual-1-4096x2160.edid") -eq 384 ]]
displayid_headers=$(for block_offset in 128 256; do
  od -An -j "$block_offset" -N 8 -tx1 "${edid_dir}/virtual-1-2560x2160.edid" | tr -d '[:space:]'
done)
[[ $displayid_headers == '70136703010300647013670000030064' ]]
for block_offset in 0 128 256; do
  checksum=$(od -An -j "$block_offset" -N 128 -tu1 "${edid_dir}/virtual-1-4096x2160.edid" |
    awk '{ for (field = 1; field <= NF; ++field) sum += $field } END { print sum % 256 }')
  [[ $checksum -eq 0 ]]
done
[[ $(od -An -j 8 -N 2 -tx1 "${edid_dir}/virtual-1-2560x2160.edid" | tr -d '[:space:]') == '4c76' ]]
[[ $(od -An -j 113 -N 13 -tx1 "${edid_dir}/virtual-1-2560x2160.edid" | tr -d '[:space:]') == '446973706c617920310a202020' ]]

run_prepare() {
  PATH="${fake_bin}:${PATH}" \
    "$repo_dir/packaging/bin/stationconnect-display-prepare" \
      --config "$config_file" --output "$output_file" --edid-dir "$edid_dir"
}

run_requested_prepare() {
  PATH="${fake_bin}:${PATH}" \
    "$repo_dir/packaging/bin/stationconnect-display-prepare" \
      --config "$config_file" --output "$output_file" --edid-dir "$edid_dir" \
      "$@"
}

cat >"${fake_bin}/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod 0755 "${fake_bin}/systemctl"

printf '[display]\nvirtual_outputs = off\n' >"$config_file"
run_prepare >/dev/null
[[ ! -e $output_file ]]
if run_requested_prepare --layout single --mode-1 3840x2160 >/dev/null 2>&1; then
  echo "a virtual transition bypassed the physical-display policy" >&2
  exit 1
fi
[[ ! -e $output_file ]]

printf '[display]\nvirtual_outputs = single\n' >"$config_file"
run_prepare >/dev/null
grep -Fq 'DFP-0: 1920x1080 +0+0, DFP-2: NULL' "$output_file"
grep -Fq 'virtual-1-1920x1080.edid' "$output_file"
grep -Fq 'virtual-2-1920x1080.edid' "$output_file"
grep -Fq 'Virtual 5120 2160' "$output_file"

printf '[display]\nvirtual_outputs = single\nvirtual_mode_1 = 3840x2160\nvirtual_mode_2 = 1280x2160\n' >"$config_file"
run_prepare >/dev/null
grep -Fq 'Option "ConnectedMonitor" "DFP-0, DFP-2"' "$output_file"
if grep -Fq 'AllowNonEdidModes' "$output_file"; then
  echo "generated Xorg overlay permits a non-EDID mode" >&2
  exit 1
fi
grep -Fq 'DFP-0: 3840x2160 +0+0, DFP-2: NULL' "$output_file"
grep -Fq 'Virtual 5120 2160' "$output_file"
grep -Fq 'virtual-1-3840x2160.edid' "$output_file"
grep -Fq 'virtual-2-1280x2160.edid' "$output_file"

printf '[display]\nvirtual_outputs = dual-horizontal\nvirtual_mode_1 = 3840x2160\nvirtual_mode_2 = 1280x2160\n' >"$config_file"
run_prepare >/dev/null
grep -Fq 'Option "ConnectedMonitor" "DFP-0, DFP-2"' "$output_file"
grep -Fq 'DFP-0: 3840x2160 +0+0, DFP-2: 1280x2160 +3840+0' "$output_file"
grep -Fq 'virtual-2-1280x2160.edid' "$output_file"
grep -Fq 'Virtual 5120 2160' "$output_file"

run_requested_prepare --layout single --mode-1 2560x1600 >/dev/null
grep -Fq 'Option "ConnectedMonitor" "DFP-0, DFP-2"' "$output_file"
grep -Fq 'DFP-0: 2560x1600 +0+0, DFP-2: NULL' "$output_file"
grep -Fq 'virtual-1-2560x1600.edid' "$output_file"
grep -Fq 'Virtual 5120 2160' "$output_file"
grep -Fq 'virtual_outputs = dual-horizontal' "$config_file"

run_requested_prepare --layout single --mode-1 2560x2160 >/dev/null
grep -Fq 'DFP-0: 2560x2160 +0+0, DFP-2: NULL' "$output_file"
grep -Fq 'virtual-1-2560x2160.edid' "$output_file"
grep -Fq 'Virtual 5120 2160' "$output_file"

if run_requested_prepare --layout dual-horizontal --mode-1 4096x2160 >/dev/null 2>&1; then
  echo "a dual transition without mode 2 was accepted" >&2
  exit 1
fi

printf '[display]\nvirtual_outputs = dual-horizontal\nvirtual_mode_1 = 4096x2160\nvirtual_mode_2 = 1024x2160\n' >"$config_file"
run_prepare >/dev/null
grep -Fq 'DFP-0: 4096x2160 +0+0, DFP-2: 1024x2160 +4096+0' "$output_file"
grep -Fq 'virtual-1-4096x2160.edid' "$output_file"
grep -Fq 'virtual-2-1024x2160.edid' "$output_file"
grep -Fq 'Virtual 5120 2160' "$output_file"

previous_hash=$(sha256sum "$output_file")
printf '[display]\nvirtual_outputs = three\n' >"$config_file"
if run_prepare >/dev/null 2>&1; then
  echo "invalid virtual output count was accepted" >&2
  exit 1
fi
[[ $(sha256sum "$output_file") == "$previous_hash" ]]

cat >"${fake_bin}/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod 0755 "${fake_bin}/systemctl"
printf '[display]\nvirtual_outputs = single\nvirtual_mode_1 = 1920x1080\n' >"$config_file"
if run_prepare >/dev/null 2>&1; then
  echo "an active display manager did not block a topology change" >&2
  exit 1
fi
[[ $(sha256sum "$output_file") == "$previous_hash" ]]

printf '[display]\nvirtual_outputs = dual-horizontal\nvirtual_mode_1 = 4096x2160\nvirtual_mode_2 = 1024x2160\n' >"$config_file"
run_prepare >/dev/null

printf '[display]\nvirtual_outputs = dual-horizontal\nvirtual_mode_1 = 5120x2160\nvirtual_mode_2 = 1280x2160\n' >"$config_file"
if run_prepare >/dev/null 2>&1; then
  echo "an unqualified independent virtual mode was accepted" >&2
  exit 1
fi

cat >"${fake_bin}/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod 0755 "${fake_bin}/systemctl"
printf '[display]\nvirtual_outputs = off\n' >"$config_file"
run_prepare >/dev/null
[[ ! -e $output_file ]]

mkdir -p "${output_file%/*}"
printf '# owned by somebody else\n' >"$output_file"
if run_prepare >/dev/null 2>&1; then
  echo "a foreign Xorg configuration was removed" >&2
  exit 1
fi
grep -Fxq '# owned by somebody else' "$output_file"

if "$repo_dir/packaging/bin/stationconnect-display-prepare" --cleanup \
    --output "$output_file" >/dev/null 2>&1; then
  echo "uninstall cleanup removed a foreign Xorg configuration" >&2
  exit 1
fi
printf '%s\n' '# Generated by StationConnect; do not edit.' >"$output_file"
"$repo_dir/packaging/bin/stationconnect-display-prepare" --cleanup \
  --output "$output_file" >/dev/null
[[ ! -e $output_file ]]

echo "display_prepare_tests=pass"
