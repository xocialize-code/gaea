#!/bin/zsh
# Builds the AB-T-0356 harness in Release and assembles a signed bench.gaeaplugin, the way
# gaea-plugin-demo's build-plugin.sh does (Developer ID, hardened runtime, the metallib in the
# bundle's Resources so MLX finds it through the worker's main bundle).
#
#   scripts/build.sh            → $BENCH_SCRATCH/bench.gaeaplugin, bench-host, bench-inproc
#
# BENCH_SCRATCH: the build folder. Default: an internal-disk folder under $TMPDIR, because the build
# is several GB and the external volume may be short of space. Never committed.
set -euo pipefail
ROOT=${0:A:h:h}
cd $ROOT
SCRATCH=${BENCH_SCRATCH:-$TMPDIR/gaea-bench-ab-t-0356}
IDENTITY=${SIGN_IDENTITY:-"Developer ID Application: Dustin Nielson (CFZS6RXUCP)"}
ID=com.xocialize.gaea.bench-ab-t-0356

xcrun swift build -c release --arch arm64 --scratch-path $SCRATCH/build
BIN=$(xcrun swift build -c release --arch arm64 --scratch-path $SCRATCH/build --show-bin-path)

B=$SCRATCH/bench.gaeaplugin
rm -rf $B && mkdir -p $B/Contents/MacOS $B/Contents/Resources
cp $BIN/bench-worker $B/Contents/MacOS/bench-worker
ditto $BIN/mlx-swift_Cmlx.bundle $B/Contents/Resources/mlx-swift_Cmlx.bundle
$BIN/bench-worker --manifest $B/Contents/Resources/manifest.json
cat > $B/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleExecutable</key><string>bench-worker</string>
  <key>CFBundleName</key><string>bench</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
</dict></plist>
EOF
codesign --force --sign $IDENTITY --options runtime --timestamp --identifier $ID $B
codesign --verify --strict --deep $B

# The in-process baseline gets the same metallib arrangement: a bundle-less binary finds it next to
# itself (mlx-swift_Cmlx.bundle in the bin folder), which is where SwiftPM put it.
cp $BIN/bench-host $BIN/bench-inproc $SCRATCH/
ditto $BIN/mlx-swift_Cmlx.bundle $SCRATCH/mlx-swift_Cmlx.bundle
print "built: $B, $SCRATCH/bench-host, $SCRATCH/bench-inproc"
