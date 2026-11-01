#!/bin/zsh
# Builds, checks, notarizes and publishes a GitHub Release of Gaea (G4 order 1; DST-1, DST-2): Gaea-<version>.zip (the
# stapled Gaea.app, with the gaea CLI in Contents/Helpers), its .sha256, and release.json, which Gaea's updater reads
# (G-24), tagged v<version>. CI runs it on a tag (.github/workflows/release.yml); it runs on this Mac the same way.
#
#   scripts/release.sh
#
# Environment (beyond scripts/build-app.sh's):
#   NOTARIZE        yes | no | auto (default). auto notarizes when the notary profile exists, and otherwise publishes
#                   a pre-release marked "signed, not notarized".
#   NOTARY_PROFILE  the notarytool keychain profile (default mlx-notary, the fleet's).
#   NOTARY_KEYCHAIN the keychain holding that profile (CI's temporary keychain); default: login.
#   PUBLISH         yes (default) | no: build, check and notarize only.
#   GH_TOKEN        for gh in CI.
set -euo pipefail
ROOT=${0:A:h:h}
cd $ROOT
NOTARIZE=${NOTARIZE:-auto}
PROFILE=${NOTARY_PROFILE:-mlx-notary}
step() { print -P "%B==> $*%b" }

VERSION=$(sed -n 's/.*static let version = "\(.*\)"/\1/p' Sources/GaeaCore/Support/Gaea.swift)
TAG=v$VERSION
if [[ -n ${GITHUB_REF_NAME:-} && ${GITHUB_REF_TYPE:-} == tag && $GITHUB_REF_NAME != $TAG ]]; then
  print -u2 "tag $GITHUB_REF_NAME doesn't match Gaea.version $VERSION"; exit 1
fi

step "build Gaea.app $VERSION"
$ROOT/scripts/build-app.sh
DIST=$ROOT/dist
APP=$DIST/Gaea.app
ZIP=$DIST/Gaea-$VERSION.zip
[[ $(defaults read $APP/Contents/Info CFBundleShortVersionString) == $VERSION ]] || { print -u2 "Info.plist isn't $VERSION"; exit 1 }

# The built app runs: headless, in a fresh folder, it answers the MES handshake and the operator socket. GAEA_HOME is
# short, since the socket's path is at most 103 bytes.
step "smoke: Gaea --headless, the MES handshake and gaea status"
SMOKE=$(mktemp -d /tmp/gaea-rel.XXXX)
PORT=17799
GAEA_HOME=$SMOKE $APP/Contents/MacOS/Gaea --headless --port $PORT --no-advertise > $DIST/smoke.log 2>&1 &
pid=$!
for _ in {1..100}; do [[ -S $SMOKE/operator.sock ]] && break; sleep 0.2; done
smoke_ok=yes
curl -sf -H 'MES-Version: 0.1' http://127.0.0.1:$PORT/mes/v0/engine | tee $DIST/smoke-engine.json | grep -q '"version"' || smoke_ok=no
GAEA_HOME=$SMOKE $APP/Contents/Helpers/gaea status | tee -a $DIST/smoke.log | grep -q "Gaea $VERSION" || smoke_ok=no
kill $pid; wait $pid 2>/dev/null || true
rm -rf $SMOKE
[[ $smoke_ok == yes ]] || { print -u2 "smoke failed (dist/smoke.log)"; exit 1 }

ditto -c -k --keepParent $APP $ZIP

notary=(--keychain-profile $PROFILE); [[ -n ${NOTARY_KEYCHAIN:-} ]] && notary+=(--keychain $NOTARY_KEYCHAIN)
if [[ $NOTARIZE == auto ]]; then
  if xcrun notarytool history $notary >/dev/null 2>&1; then NOTARIZE=yes; else NOTARIZE=no
    print "no notary profile \"$PROFILE\": publishing signed, not notarized"
  fi
fi

notarized=no
if [[ $NOTARIZE == yes ]]; then
  step "notarize ${ZIP:t}"
  xcrun notarytool submit $ZIP $notary --wait --output-format json | tee $DIST/notary.json
  notary_status=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' $DIST/notary.json)
  id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' $DIST/notary.json)
  [[ -n $id ]] && xcrun notarytool log $id $notary $DIST/notary-log.json || true
  [[ $notary_status == Accepted ]] || { print -u2 "notarization: $notary_status (see dist/notary-log.json)"; exit 1 }
  # A zip can't carry a ticket; the app inside can, so it opens offline too.
  step "staple Gaea.app"
  xcrun stapler staple $APP
  xcrun stapler validate $APP
  rm -f $ZIP && ditto -c -k --keepParent $APP $ZIP
  step "Gatekeeper: spctl --assess --type execute"
  spctl --assess --type execute -vv $APP
  notarized=yes
fi
(cd $DIST && shasum -a 256 ${ZIP:t} > ${ZIP:t}.sha256)
SHA=$(cut -d' ' -f1 $ZIP.sha256)

# What the updater needs before it downloads (G-24): the version, the zip and its digest, the macOS it needs, and the
# plugin protocol it runs, so an update that would drop a protocol an installed plugin uses is refused.
GPP_VERSION=$(sed -n 's/.*public static let version = \([0-9]*\).*/\1/p' .build/checkouts/gaea-plugin-kit/Sources/GaeaProtocol/GPP.swift)
python3 - $DIST/release.json <<EOF
import json, sys
json.dump({"name": "Gaea", "version": "$VERSION", "tag": "$TAG", "zip": "${ZIP:t}", "sha256": "$SHA",
           "minimum_macos": "$(defaults read $APP/Contents/Info LSMinimumSystemVersion)", "gpp": [int("$GPP_VERSION")],
           "team": "CFZS6RXUCP", "notarized": "$notarized" == "yes"}, open(sys.argv[1], "w"), indent=2)
EOF
cat $DIST/release.json

[[ ${PUBLISH:-yes} == yes ]] || { print "PUBLISH=no: done"; exit 0 }

step "GitHub Release $TAG"
assets=($ZIP $ZIP.sha256 $DIST/release.json)
if [[ $notarized == yes ]]; then
  state="Signed with Developer ID (hardened runtime, secure timestamp), notarized and stapled."
  pre=()
else
  state="Signed with Developer ID (hardened runtime, secure timestamp). **Not notarized**: Gatekeeper stops it when downloaded through a browser."
  pre=(--prerelease)
fi
previous=$(git tag --list 'v*' --sort=-v:refname | grep -vx $TAG | head -1 || true)
notes="$state

- \`${ZIP:t}\` sha256 \`$SHA\`: Gaea.app, with the \`gaea\` command line in \`Contents/Helpers\`
- \`release.json\`: the version, digest, minimum macOS ($(defaults read $APP/Contents/Info LSMinimumSystemVersion)) and plugin protocol (GPP $GPP_VERSION), for Gaea's updater

Checked before publishing: \`codesign --verify --strict --deep\`, the app headless answering the MES handshake and \`gaea status\`$([[ $notarized == yes ]] && print ', `stapler validate` and `spctl --assess`')."
[[ -n $previous ]] && notes+="

Changes since ${previous}: https://github.com/xocialize-code/gaea/compare/${previous}...${TAG}"
if gh release view $TAG >/dev/null 2>&1; then
  gh release upload $TAG $assets --clobber
  gh release edit $TAG --notes $notes ${pre:---prerelease=false}
else
  gh release create $TAG $assets --title "Gaea $VERSION" --notes $notes $pre
fi
gh release view $TAG --json url,isPrerelease,assets -q '.url, (.assets[] | .name)'
