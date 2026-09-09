#!/bin/bash
# Native, receipt-backed macOS distribution. Run only on the dedicated Mac.
set -euo pipefail
if [[ $# != 3 || $1 != /* || $2 != /* || $3 != /* || $(uname -s) != Darwin ]]; then
  echo 'Usage: build-macos-host-pkg.sh CLEAN_SOURCE NEW_OUTPUT RETAINED_TRANSPORT_ARCHIVE' >&2; exit 2
fi
source_root=$1; output=$2; archive=$3
: "${PLANK_MACOS_SIGNING_IDENTITY:?Developer ID Application SHA1 required}"
: "${PLANK_MACOS_INSTALLER_IDENTITY:?Developer ID Installer SHA1 required}"
: "${PLANK_MACOS_TEAM_ID:?Developer Team ID required}"
: "${PLANK_NOTARY_PROFILE:?Keychain profile required}"
[[ $PLANK_MACOS_SIGNING_IDENTITY =~ ^[[:xdigit:]]{40}$ && $PLANK_MACOS_INSTALLER_IDENTITY =~ ^[[:xdigit:]]{40}$ ]]
[[ $PLANK_MACOS_TEAM_ID =~ ^[A-Z0-9]{10}$ ]]
test -z "$(git -C "$source_root" status --porcelain)"
source "$source_root/scripts/package-version.sh"
plank_load_package_version "$source_root"
export PLANK_MACOS_HOST_VERSION=$PLANK_PACKAGE_VERSION PLANK_MACOS_DISTRIBUTION=1
identities=$(security find-identity -v)
echo "$identities" | grep -F "$PLANK_MACOS_SIGNING_IDENTITY" | grep -F '"Developer ID Application:'
echo "$identities" | grep -F "$PLANK_MACOS_INSTALLER_IDENTITY" | grep -F '"Developer ID Installer:'
mkdir "$output"
printf '%s\n' "source=$(git -C "$source_root" rev-parse HEAD)" "version=$PLANK_PACKAGE_VERSION"
shasum -a 256 "$archive"
bash "$source_root/scripts/build-macos-host.sh" "$source_root" "$output/host" "$archive"
flags=(-mmacosx-version-min=27.0 -fobjc-arc -Wall -Wextra -Werror
  "-DPLANK_INSTALLER_TEAM=\"$PLANK_MACOS_TEAM_ID\"" "-DPLANK_INSTALLER_VERSION=\"$PLANK_PACKAGE_VERSION\""
  -framework Foundation -framework Security)
xcrun clang "${flags[@]}" -Wno-unused-function "$source_root/tests/packaging/macos-native-installer.m" -o "$output/installer-policy-test"
"$output/installer-policy-test"
xcrun clang "${flags[@]}" "$source_root/packaging/macos/native-installer.m" -o "$output/plank-host-installer"
codesign --force --sign "$PLANK_MACOS_SIGNING_IDENTITY" --options runtime --timestamp \
  --identifier la.instinctual.PLANK.Host.Installer "$output/plank-host-installer"
codesign --verify --strict "$output/plank-host-installer"

mkdir -p "$output/payload/Applications" "$output/install-scripts" "$output/uninstall-scripts" "$output/resources"
app="$output/payload/Applications/PLANK Host.app"
ditto "$output/host/PLANK Host.app" "$app"
codesign --verify --strict -R "identifier \"la.instinctual.PLANK.Host\" and anchor apple generic and certificate leaf[subject.OU] = \"$PLANK_MACOS_TEAM_ID\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists" "$app"
test "$(/usr/libexec/PlistBuddy -c 'Print :PLANKVersion' "$app/Contents/Info.plist")" = "$PLANK_PACKAGE_VERSION"
test -z "$(find "$output/payload" -name '*.py' -print)"
codesign -d --verbose=4 "$app" 2>&1 | grep 'flags=.*runtime'
codesign -d --verbose=4 "$app" 2>&1 | grep '^Timestamp='
otool -L "$app/Contents/MacOS/plank-host"
install -m 0755 "$output/plank-host-installer" "$output/install-scripts/plank-host-installer"
install -m 0755 "$output/plank-host-installer" "$output/uninstall-scripts/plank-host-installer"
install -m 0755 "$source_root/packaging/macos/pkg-preinstall" "$output/install-scripts/preinstall"
install -m 0755 "$source_root/packaging/macos/pkg-postinstall" "$output/install-scripts/postinstall"
install -m 0755 "$source_root/packaging/macos/pkg-uninstall" "$output/uninstall-scripts/postinstall"
install -m 0644 "$source_root/packaging/macos/welcome.html" "$source_root/packaging/macos/conclusion.html" "$source_root/packaging/macos/uninstall.html" "$output/resources/"
pkgbuild --root "$output/payload" --component-plist "$source_root/packaging/macos/component.plist" \
  --identifier la.instinctual.PLANK.Host --version "$PLANK_BASE_VERSION" --install-location / \
  --ownership recommended --scripts "$output/install-scripts" "$output/host-component.pkg"
pkgbuild --nopayload --identifier la.instinctual.PLANK.Host.Uninstall --version "$PLANK_BASE_VERSION" \
  --scripts "$output/uninstall-scripts" "$output/uninstall-component.pkg"
for kind in host uninstall; do
  if [[ $kind = host ]]; then
    title="PLANK Host $PLANK_PACKAGE_VERSION"; welcome=welcome.html; conclusion=conclusion.html
    identifier=la.instinctual.PLANK.Host; component=host-component.pkg
    name="plank-host_${PLANK_PACKAGE_VERSION}_arm64.pkg"
  else
    title="Uninstall PLANK Host $PLANK_PACKAGE_VERSION"; welcome=uninstall.html; conclusion=uninstall.html
    identifier=la.instinctual.PLANK.Host.Uninstall; component=uninstall-component.pkg
    name="plank-host-uninstall_${PLANK_PACKAGE_VERSION}_arm64.pkg"
  fi
  sed -e "s/@TITLE@/$title/g" -e "s/@WELCOME@/$welcome/g" -e "s/@CONCLUSION@/$conclusion/g" \
    -e "s/@IDENTIFIER@/$identifier/g" -e "s/@VERSION@/$PLANK_BASE_VERSION/g" -e "s/@COMPONENT@/$component/g" \
    "$source_root/packaging/macos/distribution.xml.in" > "$output/$kind-distribution.xml"
  productbuild --distribution "$output/$kind-distribution.xml" --resources "$output/resources" \
    --package-path "$output" --sign "$PLANK_MACOS_INSTALLER_IDENTITY" --timestamp "$output/$name"
  pkgutil --check-signature "$output/$name"
  xcrun notarytool submit "$output/$name" --keychain-profile "$PLANK_NOTARY_PROFILE" --wait --timeout 10m --output-format json > "$output/$kind-notary.json"
  /usr/bin/plutil -extract status raw "$output/$kind-notary.json" | grep -x Accepted
  xcrun stapler staple "$output/$name"
  xcrun stapler validate "$output/$name"
  spctl --assess --type install --verbose=2 "$output/$name"
  shasum -a 256 "$output/$name"
done
echo 'macos_native_pkg_gate=pass install=not-performed'
