#!/usr/bin/env bash
# Interactive app distribution: copy to Applications, uninstall by trashing app.
set -euo pipefail
[[ $# == 2 && $1 == /* && $2 == /* ]] || { echo 'usage: build-macos-client-dmg.sh CLEAN_SOURCE NEW_OUTPUT' >&2; exit 2; }
source_root=$1
output=$2
: "${PLANK_MACOS_SIGNING_IDENTITY:?Developer ID Application SHA1 required}"
: "${PLANK_NOTARY_PROFILE:?Keychain profile required}"
: "${PLANK_QT_ROOT:?}"
test -z "$(git -C "$source_root" status --porcelain)"
test -z "$(git -C "$source_root/client/moonlight-qt-fork" status --porcelain)"
source "$source_root/scripts/package-version.sh"
plank_load_package_version "$source_root"
mkdir "$output"
bash "$source_root/scripts/build-macos-client.sh" "$source_root" "$output/build"
mkdir "$output/image"
app="$output/image/PLANK Client.app"
ditto "$output/build/app/plank-client.app" "$app"
"$PLANK_QT_ROOT/bin/macdeployqt" "$app" \
    "-qmldir=$source_root/client/moonlight-qt-fork/app/gui" -always-overwrite -no-strip
mkdir "$output/plank.iconset"
clang -fobjc-arc -mmacosx-version-min=27.0 "$source_root/scripts/macos-app-icon.m" \
    -framework Foundation -framework CoreGraphics -framework ImageIO -o "$output/macos-app-icon"
"$output/macos-app-icon" "$source_root/branding/assets/plank-logo.png" "$output/plank.iconset"
iconutil -c icns "$output/plank.iconset" -o "$app/Contents/Resources/plank.icns"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile plank' "$app/Contents/Info.plist"
# Remove only the inherited icon in this newly created packaging tree.
if [[ -f "$app/Contents/Resources/moonlight.icns" ]]; then
    rm "$app/Contents/Resources/moonlight.icns"
fi
mkdir -p "$app/Contents/Resources/licenses"
cp "$source_root/client/moonlight-qt-fork/LICENSE" "$app/Contents/Resources/licenses/client.txt"
for name in SDL3-3.4.2 SDL3_ttf-3.2.2 opus-1.5.2 openssl-3.5.5 freetype-2.14.1 ffmpeg-9.0.1; do
    mkdir "$app/Contents/Resources/licenses/$name"
    find "$PLANK_MAC_CLIENT_DEPS/src/$name" -maxdepth 1 -type f \
        \( -name 'COPYING*' -o -name 'LICENSE*' -o -name 'LICENSE.txt' \) \
        -exec cp {} "$app/Contents/Resources/licenses/$name/" \;
done
while IFS= read -r -d '' binary; do
    file -b "$binary" | grep -q 'Mach-O' || continue
    # macdeployqt relocates linked libraries; remove developer-only search paths.
    while IFS= read -r rpath; do
        case "$rpath" in
            /Users/*) install_name_tool -delete_rpath "$rpath" "$binary" ;;
        esac
    done < <(otool -l "$binary" | awk '/cmd LC_RPATH/{getline; getline; print $2}')
    if otool -L "$binary" | tail -n +2 | grep -E '^[[:space:]]+/(Users|opt|usr/local)/'; then
        echo "Unbundled dependency in $binary" >&2; exit 1
    fi
    codesign --force --options runtime --timestamp --sign "$PLANK_MACOS_SIGNING_IDENTITY" "$binary"
done < <(find "$app" -type f -print0)
while IFS= read -r -d '' framework; do
    codesign --force --options runtime --timestamp --sign "$PLANK_MACOS_SIGNING_IDENTITY" "$framework"
done < <(find "$app" -depth -type d -name '*.framework' -print0)
codesign --force --options runtime --timestamp --sign "$PLANK_MACOS_SIGNING_IDENTITY" "$app"
codesign --verify --deep --strict "$app"
test "$(QT_QPA_PLATFORM=offscreen "$app/Contents/MacOS/plank-client" --version)" = "PLANK $PLANK_PACKAGE_VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :PLANKVersion' "$app/Contents/Info.plist")" = "$PLANK_PACKAGE_VERSION"
ln -s /Applications "$output/image/Applications"
dmg="$output/plank-client_${PLANK_PACKAGE_VERSION}_arm64.dmg"
hdiutil create -volname "PLANK Client $PLANK_PACKAGE_VERSION" -srcfolder "$output/image" -format UDZO "$dmg"
codesign --timestamp --sign "$PLANK_MACOS_SIGNING_IDENTITY" "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile "$PLANK_NOTARY_PROFILE" --wait --timeout 10m --output-format json > "$output/notary.json"
test "$(plutil -extract status raw "$output/notary.json")" = Accepted
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
shasum -a 256 "$dmg"
echo 'macos_client_dmg_gate=pass install=not-performed'
