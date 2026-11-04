#!/bin/zsh
# AB-T-0429's clean install (G4 order 7): Gaea from its GitHub release on a Mac that has never seen it, a throwaway clone
# of AppProbe's golden Tart VM (Cirrus Labs' vanilla macOS 26), deleted afterwards.
#
#   tools/acceptance-clean-install.sh <tag>        e.g. v1.0.0-rc.1
#
#   1. the guest downloads Gaea-<version>.zip and its .sha256 from the GitHub release, as a browser would (quarantined),
#      checks the digest, unzips it and moves Gaea.app to /Applications;
#   2. Gatekeeper accepts the quarantined app as notarized Developer ID; its stapled ticket validates offline;
#   3. the app opens and serves (the person's first-open confirmation is theirs to click, so quarantine is cleared after
#      the Gatekeeper check, as AppProbe's VM runs do); `gaea status` answers from Helpers;
#   4. the demo plugin installs from GitHub and a job runs through MES, on the guest's paravirtualized GPU;
#   5. headless: the app quits, `Gaea --headless` starts on the same folder with the plugin, and runs a job;
#   6. the console renders on this Mac (`Gaea --snapshot`): its pages come back as PNGs.
set -uo pipefail
cd ${0:A:h:h}
TAG=${1:?a release tag, e.g. v1.0.0-rc.1}; VERSION=${TAG#v}
OUT=${OUT:-Docs/Evidence/AB-T-0429/clean-install}; mkdir -p "$OUT"
LOG=$OUT/acceptance.log; : > "$LOG"
APPPROBE=${APPPROBE_DIR:-${0:A:h:h:h}/AppProbe}
source $APPPROBE/VM/common.sh
VM=gaea-clean-$(date +%Y%m%d-%H%M%S)
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift
  if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi
}
g() { # a command in the guest; ssh's own failures (255, e.g. a timed-out banner) are retried, the command's are not
  local r
  for _ in 1 2 3; do vm_ssh $IP "$@"; r=$?; (( r == 255 )) || return $r; sleep 3; done
  return $r
}
cleanup() { tart stop $VM >/dev/null 2>&1; tart delete $VM >/dev/null 2>&1; true }
trap cleanup EXIT

say "# Clean install (AB-T-0429) $(date -u +%FT%TZ): Gaea $TAG from GitHub in $VM, a clone of $GOLDEN"
tart clone $GOLDEN $VM
tart run $VM --no-graphics >/dev/null 2>&1 &
IP=$(vm_wait_ip $VM) || { say "FAIL  the VM has no SSH"; exit 1 }
say "guest: $(g 'sw_vers -productVersion; sysctl -n hw.model hw.memsize' | tr '\n' ' ')at $IP"
check "the guest has never seen Gaea" g '! ls -d /Applications/Gaea.app ~/Library/Application\ Support/Gaea 2>/dev/null'

# 1. Download as a browser would, and install.
URL=https://github.com/xocialize-code/gaea/releases/download/$TAG
check "the release downloads: Gaea-$VERSION.zip and its sha256" g "set -e; mkdir -p ~/Downloads; cd ~/Downloads
  curl -sSfLO $URL/Gaea-$VERSION.zip; curl -sSfLO $URL/Gaea-$VERSION.zip.sha256
  xattr -w com.apple.quarantine \"0083;\$(printf %x \$(date +%s));Safari;\" Gaea-$VERSION.zip"
check "  its digest matches" g "cd ~/Downloads && shasum -a 256 -c Gaea-$VERSION.zip.sha256"
check "  it unzips with quarantine kept, and Gaea.app moves to /Applications" g "set -e; cd ~/Downloads
  ditto -x -k Gaea-$VERSION.zip . && xattr -p com.apple.quarantine Gaea.app && mv Gaea.app /Applications/"

# 2. Gatekeeper, before anything runs.
check "Gatekeeper accepts the quarantined app: notarized Developer ID" g 'spctl -a -vv -t exec /Applications/Gaea.app 2>&1 | tee /dev/stderr | grep -q "source=Notarized Developer ID"'
check "  its notarization ticket is stapled" g 'codesign -dvvv /Applications/Gaea.app 2>&1 | grep -q "Notarization Ticket=stapled"'
check "  --version answers $VERSION" g "/Applications/Gaea.app/Contents/MacOS/Gaea --version | grep -q '\"version\":\"$VERSION\"'"

# 3. The app opens and serves.
g 'xattr -dr com.apple.quarantine /Applications/Gaea.app'
g 'open /Applications/Gaea.app'
CLI=/Applications/Gaea.app/Contents/Helpers/gaea
check "the app opens, and gaea status answers" g "for i in {1..60}; do $CLI status >/dev/null 2>&1 && break; sleep 1; done; $CLI status | tee /dev/stderr | grep -q 'Gaea $VERSION'"
g "$CLI status" > "$OUT/status-app.txt" 2>&1

# 4. A plugin from GitHub, and a job through MES.
job() { # json body → the settled job (sed and grep: a vanilla guest has no python3 without the command-line tools)
  g "id=\$(curl -s -H 'MES-Version: 0.1' -X POST http://127.0.0.1:17630/mes/v0/jobs -H 'Content-Type: application/json' -d '$1' | sed -E 's/.*\"id\":\"(job_[a-z0-9]+)\".*/\\1/')
     for i in {1..30}; do j=\$(curl -s -H 'MES-Version: 0.1' \"http://127.0.0.1:17630/mes/v0/jobs/\$id?wait=10\")
       echo \"\$j\" | grep -qE '\"state\":\"(holding|purged)\"' && break; done; echo \"\$j\""
}
GRADIENT='{"operation":"image.generate","model":"demo-gradient","inputs":{"prompt":"a clean install"},"params":{"size":{"width":512,"height":512},"seed":1}}'
check "the demo plugin installs from GitHub" g "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-demo | tee /dev/stderr | grep -q '^Installed'"
job "$GRADIENT" > "$OUT/job-app.json"
check "  a job runs on it, on the guest's GPU" python3 -c "import json; j = json.load(open('$OUT/job-app.json')); assert j['outcome'] == 'succeeded', j; print(j['result']['effective']['model_params']['x-gaea.worker'])"

# 5. Headless, on the same folder.
g "osascript -e 'tell application \"Gaea\" to quit'; for i in {1..30}; do pgrep -x Gaea >/dev/null || break; sleep 1; done"
g "nohup /Applications/Gaea.app/Contents/MacOS/Gaea --headless > ~/gaea-headless.log 2>&1 &"
check "headless Gaea starts on the same folder, with the plugin" g "for i in {1..60}; do $CLI status >/dev/null 2>&1 && break; sleep 1; done; $CLI plugins | tee /dev/stderr | grep -q 'com.xocialize.gaea.demo'"
job "$GRADIENT" > "$OUT/job-headless.json"
check "  and runs a job" python3 -c "import json; j = json.load(open('$OUT/job-headless.json')); assert j['outcome'] == 'succeeded', j"
g "$CLI status; echo; $CLI crashes" > "$OUT/status-headless.txt" 2>&1
g "pkill -TERM -f 'Gaea --headless'"

# 6. The console renders.
check "the console renders its pages (--snapshot)" g 'set -e; rm -rf ~/snap; /Applications/Gaea.app/Contents/MacOS/Gaea --snapshot ~/snap; ls ~/snap/*.png | head -20'
g 'tar -C ~/snap -czf - .' | tar -xzf - -C "$OUT" 2>/dev/null
ls "$OUT"/*.png >> "$LOG" 2>&1

say ""
say "$pass passed, $fail failed"
(( fail == 0 ))
