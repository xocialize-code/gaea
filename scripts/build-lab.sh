#!/bin/zsh
# Builds dist/Gaea Lab.app (Release, AB-T-0372): the app, its SwiftPM resource bundles, and `lab-run` in Contents/Helpers,
# signed with Developer ID and the hardened runtime, then notarized and stapled with the notary profile.
#
#   scripts/build-lab.sh                     sign, notarize (NOTARY_PROFILE, default mlx-notary) and staple
#   NOTARIZE=no scripts/build-lab.sh         sign only
set -euo pipefail
cd "${0:A:h}/.."
VERSION=$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Apps/GaeaLab/Sources/GaeaLabCore/Lab.swift)
IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*(CFZS6RXUCP)\)".*/\1/p' | head -1)}
[[ -n "$IDENTITY" ]] || { print -u2 "no Developer ID Application identity for CFZS6RXUCP"; exit 1 }

(cd Apps/GaeaLab && xcrun swift build -c release --product GaeaLabApp && xcrun swift build -c release --product lab-run)
BIN=$(cd Apps/GaeaLab && xcrun swift build -c release --show-bin-path)

APP="dist/Gaea Lab.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
sed "s/__VERSION__/$VERSION/g" Apps/GaeaLab/Info.plist > "$APP/Contents/Info.plist"
cp "$BIN/GaeaLabApp" "$APP/Contents/MacOS/GaeaLab"
cp "$BIN/lab-run" "$APP/Contents/Helpers/lab-run"
for bundle in "$BIN"/*.bundle(N); do ditto "$bundle" "$APP/Contents/Resources/${bundle:t}"; done

codesign --force --options runtime --timestamp --identifier com.xocialize.gaea.lab.run --sign "$IDENTITY" "$APP/Contents/Helpers/lab-run"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep "$APP"
print "built $APP $VERSION, signed by $IDENTITY"

if [[ ${NOTARIZE:-yes} == yes ]]; then
  ZIP="dist/Gaea-Lab-$VERSION.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "${NOTARY_PROFILE:-mlx-notary}" --wait
  xcrun stapler staple "$APP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl --assess --type execute -vv "$APP"
  print "notarized and stapled: $ZIP"
fi
