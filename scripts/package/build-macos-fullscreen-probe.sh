#!/usr/bin/env bash
# Diagnostic app only: no Client/Host dependencies or installation.
set -euo pipefail
umask 022
[[ $# == 3 && $2 == /* && $3 == /* ]] || exit 2
stage=$1
root=$2
output=$3
test "$(uname -m)" = arm64
test "$(sw_vers -productVersion | cut -d . -f 1)" -ge 27
test "$(xcrun --sdk macosx --show-sdk-version | cut -d . -f 1)" -ge 27
test -z "$(git -C "$root" status --porcelain)"
source "$root/scripts/package/package-version.sh"
plank_load_package_version "$root"
app="$output/image/PLANK Fullscreen Probe.app"
binary="$app/Contents/MacOS/plank-fullscreen-probe"
case $stage in
  --build)
    mkdir "$output"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    python3 - "$app" "$PLANK_BASE_VERSION" "$PLANK_PACKAGE_VERSION" "$root" <<'PY'
import json, pathlib, plistlib, subprocess, sys
app, base, version, root = sys.argv[1:]
info = dict(CFBundleIdentifier='la.instinctual.plank.fullscreen-probe',
    CFBundleName='PLANK Fullscreen Probe', CFBundleDisplayName='PLANK Fullscreen Probe',
    CFBundleExecutable='plank-fullscreen-probe', CFBundlePackageType='APPL',
    CFBundleVersion=base, CFBundleShortVersionString=base, PLANKVersion=version,
    LSMinimumSystemVersion='27.0', NSHighResolutionCapable=True,
    NSPrefersDisplaySafeAreaCompatibilityMode=False, NSPrincipalClass='NSApplication')
contents = pathlib.Path(app) / 'Contents'
with (contents / 'Info.plist').open('wb') as stream:
    plistlib.dump(info, stream)
source = subprocess.check_output(['git', '-C', root, 'rev-parse', 'HEAD'], text=True).strip()
(contents / 'Resources/source.json').write_text(json.dumps(dict(version=version,
    source_commit=source, purpose='Standalone fullscreen diagnostic; not a PLANK Client'), indent=2)+'\n')
PY
    xcrun clang -arch arm64 -mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror \
      -O2 -ffile-prefix-map="$root"=/plank-source \
      "$root/probes/macos/fullscreen-window.m" -framework AppKit -o "$binary"
    strip -S "$binary"
    test "$("$binary" --version)" = "$PLANK_PACKAGE_VERSION"
    python3 "$root/scripts/test/check-package-build-paths.py" "$app"
    cp "$root/probes/macos/fullscreen-window.md" "$output/image/READ ME.md"
    echo fullscreen_probe_compile=pass
    ;;
  --package)
    : "${PLANK_MACOS_SIGNING_IDENTITY:?}"
    : "${PLANK_NOTARY_PROFILE:?}"
    : "${PLANK_NOTARY_KEYCHAIN:?}"
    : "${PLANK_ARTIFACT_ROOT:?}"
    test -x "$binary"
    test "$("$binary" --version)" = "$PLANK_PACKAGE_VERSION"
    codesign --force --options runtime --timestamp --sign "$PLANK_MACOS_SIGNING_IDENTITY" "$app"
    codesign --verify --deep --strict "$app"
    dmg="$output/plank-fullscreen-probe_${PLANK_PACKAGE_VERSION}_arm64.dmg"
    hdiutil create -volname "PLANK Fullscreen Probe" -srcfolder "$output/image" -format UDZO "$dmg"
    codesign --timestamp --sign "$PLANK_MACOS_SIGNING_IDENTITY" "$dmg"
    xcrun notarytool submit "$dmg" --keychain-profile "$PLANK_NOTARY_PROFILE" \
      --keychain "$PLANK_NOTARY_KEYCHAIN" --wait --timeout 10m --output-format json > "$output/notary.json"
    test "$(plutil -extract status raw "$output/notary.json")" = Accepted
    xcrun stapler staple "$dmg"
    xcrun stapler validate "$dmg"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
    # Diagnostics are intentionally separate from the product package catalog.
    destination="$PLANK_ARTIFACT_ROOT/diagnostics/$PLANK_PACKAGE_VERSION/macos"
    mkdir -p "$destination"
    cp "$dmg" "$destination/"
    python3 - "$destination" "$dmg" "$app/Contents/Resources/source.json" <<'PY'
import hashlib, json, pathlib, sys
destination, package, provenance = map(pathlib.Path, sys.argv[1:])
digest = hashlib.sha256(package.read_bytes()).hexdigest()
assert hashlib.sha256((destination/package.name).read_bytes()).hexdigest() == digest
record = json.loads(provenance.read_text())
record.update(file=package.name, sha256=digest, size=package.stat().st_size,
    package_validation='passed', functional_validation='not-recorded')
(destination/'manifest.json').write_text(json.dumps(record, indent=2)+'\n')
(destination/'SHA256SUMS').write_text(digest+'  '+package.name+'\n')
print('fullscreen_probe_package=pass sha256='+digest)
PY
    ;;
  *) exit 2;;
esac
