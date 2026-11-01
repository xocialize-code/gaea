#!/bin/zsh
# Builds dist/Gaea.app (Release): the app, its SwiftPM resource bundles, and the `gaea` CLI in Contents/Helpers,
# signed with Developer ID and the hardened runtime (G-6, DST-1). Notarization happens in CI, not here.
#
#   scripts/build-app.sh                 sign with "Developer ID Application: … (CFZS6RXUCP)"
#   SIGN_IDENTITY=- scripts/build-app.sh ad-hoc, for a quick local build (the operator API then accepts any same-user caller)
set -euo pipefail
cd "${0:A:h}/.."
VERSION=$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/GaeaCore/Support/Gaea.swift)
IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*(CFZS6RXUCP)\)".*/\1/p' | head -1)}
[[ -n "$IDENTITY" ]] || { print -u2 "no Developer ID Application identity for CFZS6RXUCP"; exit 1 }

# Swift Build, named: its Bundle.module looks in the app's Contents/Resources. The native build system (Swift 6.3's
# default, on GitHub's runners) looks only beside Contents and in the absolute build folder, so a release built with it
# traps on its first resource on any other Mac (AB-T-0410).
BUILD=(-c release --build-system swiftbuild)
xcrun swift build $BUILD --product GaeaApp
xcrun swift build $BUILD --product gaea
BIN=$(xcrun swift build $BUILD --show-bin-path)

APP=dist/Gaea.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
sed "s/__VERSION__/$VERSION/g" Apps/Gaea/Info.plist > "$APP/Contents/Info.plist"
cp "$BIN/GaeaApp" "$APP/Contents/MacOS/Gaea"
if strings "$APP/Contents/MacOS/Gaea" | grep -q '/\.build/.*\.bundle$'; then
  print -u2 "Gaea's Bundle.module looks in the build folder: it would trap on another Mac"; exit 1
fi
cp "$BIN/gaea" "$APP/Contents/Helpers/gaea"
for bundle in "$BIN"/*.bundle(N); do ditto "$bundle" "$APP/Contents/Resources/${bundle:t}"; done

TIMESTAMP=(--timestamp)
[[ "$IDENTITY" == "-" ]] && TIMESTAMP=()
codesign --force --options runtime $TIMESTAMP --identifier com.xocialize.gaea.cli --sign "$IDENTITY" "$APP/Contents/Helpers/gaea"
codesign --force --options runtime $TIMESTAMP --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep "$APP"
print "built $APP $VERSION, signed by $IDENTITY"
