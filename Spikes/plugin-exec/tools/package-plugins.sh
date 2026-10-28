#!/bin/zsh
# Packages the demo worker as .gaeaplugin bundles, zips them, and writes dist/catalog.json
# (the stand-in for a GitHub Releases listing). Variants:
#   good      Developer ID, hardened runtime, timestamped
#   adhoc     ad-hoc signed (must be refused: wrong signer)
#   tampered  Developer ID, then manifest.json edited after signing (must be refused: broken seal)
set -euo pipefail
HERE=${0:A:h}/..
WORKER=$HERE/Worker/.build/release
DIST=$HERE/dist
DEVID="Developer ID Application: Dustin Nielson (CFZS6RXUCP)"
TEAM=CFZS6RXUCP
PORT=${PORT:-8765}
VERSION=0.1.0

rm -rf $DIST && mkdir -p $DIST/stage

make_bundle() { # <dir>
  local b=$1/demo.gaeaplugin
  mkdir -p $b/Contents/MacOS $b/Contents/Resources
  cp $WORKER/gaea-demo-worker $b/Contents/MacOS/
  ditto $WORKER/mlx-swift_Cmlx.bundle $b/Contents/Resources/mlx-swift_Cmlx.bundle
  cat > $b/Contents/Resources/manifest.json <<EOF
{"id":"com.xocialize.gaea.demo","version":"$VERSION","protocol":1,"operations":["demo.matmul"],
 "footprint":{"residentBytes":2147483648},"license":"Apache-2.0"}
EOF
  cat > $b/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.xocialize.gaea.demo</string>
  <key>CFBundleExecutable</key><string>gaea-demo-worker</string>
  <key>CFBundleName</key><string>Gaea Demo Worker</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
</dict></plist>
EOF
  print $b
}

entries=()
for variant in good adhoc tampered; do
  dir=$DIST/stage/$variant; mkdir -p $dir
  b=$(make_bundle $dir)
  if [[ $variant == adhoc ]]; then
    codesign -f -s - $b
  else
    codesign -f -s $DEVID -o runtime --timestamp $b
  fi
  [[ $variant == tampered ]] && print ' ' >> $b/Contents/Resources/manifest.json
  zip=$DIST/demo-$variant-$VERSION.zip
  ditto -c -k --keepParent $b $zip
  sum=$(shasum -a 256 $zip | cut -d' ' -f1)
  id=com.xocialize.gaea.demo; [[ $variant != good ]] && id=$id.$variant
  entries+=("{\"id\":\"$id\",\"version\":\"$VERSION\",\"url\":\"http://127.0.0.1:$PORT/${zip:t}\",\"sha256\":\"$sum\",\"teamID\":\"$TEAM\",\"bundleName\":\"demo.gaeaplugin\",\"executable\":\"gaea-demo-worker\"}")
done
print "{\"plugins\":[${(j:,:)entries}]}" > $DIST/catalog.json
codesign -dv --verbose=2 $DIST/stage/good/demo.gaeaplugin 2>&1 | grep -E "Identifier|Authority=Developer|TeamIdentifier|Sealed Resources|Runtime"
ls -la $DIST
