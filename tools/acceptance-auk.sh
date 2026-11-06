#!/bin/zsh
# AB-T-0455's acceptance (G5 order 5): gaea-plugin-auk (AuK and AuK-Flash) through Gaea 1.1.1, installed from GitHub beside
# gaea-plugin-demo, on MES Audio 0.1 with RFC 0006 (media-engine-spec v0.10.0).
#
#   1. Restricted (G-27): both models are off until the operator enables them; then they offer speak, design_voice,
#      edit_speech and separate with the Qwen Research licence (commercial_use false, accepted_required,
#      user_accept_required, a notice), named-only;
#   2. users' acceptance: a named job without policy.accepted is 422 policy_unmet (terms_not_accepted); named-only: a
#      separate job naming no model runs on the demo's separator, never on AuK;
#   3. speak (clone with its transcript, a 4 s fit), design_voice, edit_speech (every one of AuK's 14 kinds) and separate
#      (the second speaker by order and by words, the singing, and on Base every voice): each succeeds; the stems are
#      the mixture's length; a replace returns the edited transcript; speed is snapped with param_adjusted;
#   4. byte for byte against auk-inproc: the clone, the fit, a design sample, the replace, the emotion, both picks, and
#      Base's voices;
#   5. refusals: a cue placed inline, removing every cue, trim_silence, the voices stem on Flash, the speaker stem
#      without a pick, a take and a mixture over 30 s (out_of_limits when the job runs), and a Mandarin edit on int4;
#   6. every recorded GPP session passes the validator.
#
#   tools/acceptance-auk.sh <short-work-dir> <evidence-dir>
#
# Needs: APP (default dist/Gaea.app, 1.1.1 or later); GAEA_GITHUB_TOKEN; the plugin repo at ../gaea-plugin-auk for its
# fixtures and auk-inproc (release, --build-system swiftbuild); AuK's weights in MODELS (default
# /Volumes/DEV_VOL1/Models/Models), which Gaea uses as its models root.
set -uo pipefail
cd "${0:A:h}/.."
WORK=${1:?work dir}; OUT=${2:?evidence dir}
APP=${APP:-dist/Gaea.app}
GAEA="$APP/Contents/MacOS/Gaea"; CLI="$APP/Contents/Helpers/gaea"
PLUGIN=${PLUGIN_REPO:-../gaea-plugin-auk}
MODELS=${MODELS:-/Volumes/DEV_VOL1/Models/Models}
INPROC=${AUK_INPROC:-$(cd $PLUGIN && xcrun swift build -c release --build-system swiftbuild --show-bin-path)/auk-inproc}
REF=$PLUGIN/scripts/fixtures/ref-en.wav
MIX=$PLUGIN/scripts/fixtures/mix-two.wav
REFTEXT='The morning train was late again, so I walked along the river and watched the boats come in.'
SPDX=LicenseRef-Qwen-Research
mkdir -p "$OUT"; rm -rf "$WORK"; mkdir -p "$WORK"
LOG="$OUT/acceptance.log"; : > "$LOG"
pass=0; fail=0
say() { print -r -- "$*" | tee -a "$LOG" }
check() { local name=$1; shift; if "$@" >> "$LOG" 2>&1; then pass=$((pass+1)); say "PASS  $name"; else fail=$((fail+1)); say "FAIL  $name"; fi }
mes() { curl -s -H 'MES-Version: 0.1' "$@" }
post() { mes -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" }
settle() {
  local j
  for _ in {1..90}; do
    j=$(mes "http://127.0.0.1:$P/mes/v0/jobs/$1?wait=10")
    print -r -- "$j" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin)["state"] in ("holding","purged") else 1)' && { print -r -- "$j"; return }
  done
  print -r -- "$j"
}
job() { local r id; r=$(post "$1"); id=$(print -r -- "$r" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))'); [[ -n $id ]] && settle $id || print -r -- "$r" }
fetch() { # job file, prefix → <prefix>-<output name>.wav for every audio output
  python3 -c "import json,sys; [print(o['name'], o['href']) for o in json.load(open(sys.argv[1]))['result']['outputs'] if o.get('href')]" "$1" |
    while read name href; do mes -o "$2-$name.wav" "http://127.0.0.1:$P$href"; done
}
start() { GAEA_HOME=$1 "$GAEA" --headless --port $2 --no-advertise --models-root "$MODELS" > "$1.out" 2>&1 &; for _ in {1..50}; do [[ -S $1/operator.sock ]] && return; sleep 0.2; done; say "Gaea didn't start"; }
stop() { pkill -TERM -f "$GAEA --headless --port $1" ; sleep 1 }
py() { python3 -c "$1" }
refused() { py "import json; e=json.load(open('$1')).get('error', {}); assert (e.get('code'), e.get('param')) == ('$3', '$4'), e" && grep -q "^$2\$" "$1.status" }
refuse() { mes -o "$2" -w '%{http_code}' -X POST "http://127.0.0.1:$P/mes/v0/jobs" -H 'Content-Type: application/json' -d "$1" > "$2.status" }
failed() { py "import json; j=json.load(open('$1')); e=j.get('error') or {}; assert j.get('outcome') == 'failed' and (e.get('code'), e.get('param')) == ('$2', '$3'), j" }
ok() { py "import json; j=json.load(open('$1')); assert j.get('outcome') == 'succeeded', j" }
upload() { mes -X POST "http://127.0.0.1:$P/mes/v0/uploads" -H "Content-Type: audio/wav" --data-binary @"$1" | py "import json,sys; print(json.load(sys.stdin)['upload_id'])" }
body() { # operation, inputs JSON (files as "@path"), params JSON, model, accepted (yes|no), [extensions JSON]
  python3 - "$@" <<'PY'
import json, sys, subprocess
op, inputs, params, model, accepted = sys.argv[1:6]
ext = sys.argv[6] if len(sys.argv) > 6 else ''
inputs = json.loads(inputs)
b = {'operation': op, 'inputs': inputs, 'params': json.loads(params)}
if model: b['model'] = model
if accepted == 'yes': b['policy'] = {'accepted': ['LicenseRef-Qwen-Research']}
if ext: b['extensions'] = json.loads(ext)
print(json.dumps(b))
PY
}
U() { print -r -- '{"upload":"'$(upload "$1")'"}' }

say "# AuK acceptance (AB-T-0455) $(date -u +%FT%TZ): Gaea $(defaults read "${APP:A}/Contents/Info" CFBundleShortVersionString), auk from GitHub"
say "host: $(sysctl -n hw.model) $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB, macOS $(sw_vers -productVersion)"
unset GH_TOKEN GITHUB_TOKEN GAEA_GITHUB_API
H=$WORK/main; P=17693
start $H $P
export GAEA_HOME=$H
check "add by repo URL installs the demo" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-demo | grep -q Installed"
check "add by repo URL installs AuK" zsh -c "$CLI plugins add https://github.com/xocialize-code/gaea-plugin-auk | tee -a $LOG | grep -q 'Installed AuK'"

# 1. Restricted and opt-in.
$CLI models list > "$OUT/models-before.txt"
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations-before.json"
check "both models start off, and AuK offers nothing until the operator enables them" py "
import json; lines = [l for l in open('$OUT/models-before.txt') if ' auk' in l]; assert len(lines) == 2 and all(l.startswith('off') for l in lines), lines
ops = json.load(open('$OUT/operations-before.json'))['operations']
assert not any(m['id'].startswith('auk') for o in ops for m in o['models']), [m['id'] for o in ops for m in o['models']]"
for m in auk-flash auk; do $CLI models enable $m >> "$LOG" 2>&1; done
mes "http://127.0.0.1:$P/mes/v0/operations" > "$OUT/operations.json"
check "enabled, each model offers speak, design_voice, edit_speech and separate: named-only, Qwen Research, non-commercial, users' acceptance" py "
import json; ops = {o['operation']: o for o in json.load(open('$OUT/operations.json'))['operations']}
for op in ['audio.speak', 'audio.design_voice', 'audio.edit_speech', 'audio.separate']:
    m = {x['id']: x for x in ops[op]['models']}; assert {'auk-flash', 'auk'} <= set(m), (op, list(m))
    for i in ['auk-flash', 'auk']:
        x = m[i]; l = x['license']; assert x.get('named_only') is True, x
        assert l['spdx'] == '$SPDX' and l['commercial_use'] is False and l['accepted_required'] is True and l['user_accept_required'] is True and l['notice'], l
s = {x['id']: x['supports'] for x in ops['audio.separate']['models']}
assert s['auk-flash']['stems'] == ['speaker', 'singing'] and s['auk']['stems'] == ['speaker', 'singing', 'voices'], s
assert s['auk']['stem_method'] == 'regenerated' and s['auk']['speaker_selection'] == ['ordinal', 'saying'], s
e = {x['id']: x['supports'] for x in ops['audio.edit_speech']['models']}['auk-flash']
assert len(e['edits']) == 14 and e['cue_placement'] == ['edge'] and e['remove_all_cues'] is False and e['target_duration'] is True, e
assert [o['name'] for o in ops['audio.separate']['outputs']] == ['speaker', 'singing', 'voices', 'vocals', 'instrumental'], ops['audio.separate']['outputs']"

# 2. Users' acceptance, and named-only.
refuse "$(body audio.speak '{"text":"Hello.","voice_ref":'"$(U $REF)"'}' '{"seed":1}' auk-flash no)" "$WORK/r-terms.json"
check "a named job without policy.accepted is 422 policy_unmet, terms_not_accepted" py "
import json; e = json.load(open('$WORK/r-terms.json'))['error']; assert (e['code'], e.get('reason')) == ('policy_unmet', 'terms_not_accepted'), e
assert open('$WORK/r-terms.json.status').read().strip() == '422'"
job "$(body audio.separate '{"audio":'"$(U $MIX)"'}' '{}' '' yes)" > "$OUT/route-separate.json"
check "a separate job naming no model runs on the demo's separator, never on AuK (named-only)" py "
import json; j = json.load(open('$OUT/route-separate.json')); assert j['outcome'] == 'succeeded' and j['result']['provenance']['model']['id'] == 'demo-separator', j"

# 3. Every operation.
EN='Gaea speaks. This sentence came from a signed plugin, over its own protocol.'
jtext() { python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$1" }
t0=$(py 'import time; print(time.time())')
job "$(body audio.speak '{"text":'"$(jtext "$EN")"',"voice_ref":'"$(U $REF)"',"voice_ref_text":'"$(jtext "$REFTEXT")"'}' '{"seed":42}' auk-flash yes)" > "$OUT/job-clone.json"
say "      clone, cold: $(py "import time; print(round(time.time()-$t0, 2))") s from submit to settled (launch, prepare int8, speak)"
job "$(body audio.speak '{"text":"This line has to fit the cue. [pause 0.5s] Exactly.","voice_ref":'"$(U $REF)"'}' '{"seed":7,"target_duration_s":4.0}' auk-flash yes)" > "$OUT/job-fitted.json"
DESC='A warm, low voice of a woman in her forties, unhurried, with a slight rasp.'
job "$(body audio.design_voice '{"description":'"$(jtext "$DESC")"'}' '{"count":2,"seed":7,"language":"en"}' auk-flash yes)" > "$OUT/job-design.json"
for n in clone fitted design; do check "$n succeeds" ok "$OUT/job-$n.json"; fetch "$OUT/job-$n.json" "$OUT/gaea-$n"; done
check "the fit is 4.0 s within a tenth" py "
import json; o = json.load(open('$OUT/job-fitted.json'))['result']['outputs'][0]; assert abs(o['duration_s'] - 4.0) <= 0.1 and o['sample_rate'] == 24000, o"

edit() { # name, seed, edit JSON, [transcript]
  local inputs='{"audio":'"$(U $REF)"'}'
  [[ -n ${4:-} ]] && inputs='{"audio":'"$(U $REF)"',"transcript":'"$(jtext "$4")"'}'
  job "$(body audio.edit_speech "$inputs" "{\"seed\":$2,\"edit\":$3}" auk-flash yes)" > "$OUT/edit-$1.json"
  check "edit $1 succeeds" ok "$OUT/edit-$1.json"
  fetch "$OUT/edit-$1.json" "$OUT/gaea-edit-$1"
}
edit replace 3 '{"kind":"replace_text","text":"river","with":"harbour"}' "$REFTEXT"
edit insert 3 '{"kind":"insert_text","text":"slowly","anchor":"walked","position":"before"}' "$REFTEXT"
edit remove 3 '{"kind":"remove_text","text":"again"}' "$REFTEXT"
edit happy 3 '{"kind":"emotion","emotion":"happy"}'
edit whisper 3 '{"kind":"style","style":"whisper"}'
edit hum 4 '{"kind":"add_cue","cue":"hum","at":"start"}' "$REFTEXT"
edit unlaugh 4 '{"kind":"remove_cue","cue":"laugh"}'
edit speed 5 '{"kind":"speed","factor":1.4}'
edit pitch 5 '{"kind":"pitch","semitones":2}'
edit volume 5 '{"kind":"volume","gain_db":-5}'
edit timbre 6 '{"kind":"timbre","description":"a deep, older male voice"}'
edit accent 6 '{"kind":"de_accent"}'
edit denoise 6 '{"kind":"denoise"}'
edit dereverb 6 '{"kind":"dereverb"}'
check "replace returns the edited transcript" py "
import json; o = [o for o in json.load(open('$OUT/edit-replace.json'))['result']['outputs'] if o['name'] == 'transcript'][0]
assert 'along the harbour' in json.dumps(o), o"
check "hum at the start returns the transcript with the cue first" py "
import json; o = [o for o in json.load(open('$OUT/edit-hum.json'))['result']['outputs'] if o['name'] == 'transcript'][0]
assert '[hum] The morning' in json.dumps(o, ensure_ascii=False), o"
check "speed 1.4 is snapped to AuK's 1.5 with param_adjusted" py "
import json; j = json.load(open('$OUT/edit-speed.json')); assert 'param_adjusted' in [w['code'] for w in j.get('warnings', [])], j.get('warnings')"

separate() { # name, model, seed, params JSON
  job "$(body audio.separate '{"audio":'"$(U $MIX)"'}' "$4" $2 yes)" > "$OUT/sep-$1.json"
  check "separate $1 succeeds" ok "$OUT/sep-$1.json"
  fetch "$OUT/sep-$1.json" "$OUT/gaea-sep-$1"
}
separate ordinal auk-flash 5 '{"seed":5,"speaker":{"ordinal":2}}'
separate saying auk-flash 5 '{"seed":5,"speaker":{"saying":"coat pocket"}}'
separate singing auk-flash 5 '{"seed":5,"stems":["singing"]}'
separate voices auk 9 '{"seed":9,"stems":["voices"]}'
check "each stem is named by it, at the mixture's length, with effective.stems" py "
import json, wave
w = wave.open('$MIX'); mix = w.getnframes() / w.getframerate()
for n, stem in [('ordinal', 'speaker'), ('saying', 'speaker'), ('singing', 'singing'), ('voices', 'voices')]:
    r = json.load(open('$OUT/sep-%s.json' % n))['result']; o = r['outputs']
    s = wave.open('$OUT/gaea-sep-%s-%s.wav' % (n, stem)); frames = s.getnframes()
    assert [x['name'] for x in o] == [stem] and frames == round(mix * s.getframerate()), (n, o, frames, mix)
    assert r['effective']['stems'] == [stem], r['effective']"

# 5. Refusals.
refuse "$(body audio.edit_speech '{"audio":'"$(U $REF)"'}' '{"edit":{"kind":"add_cue","cue":"laugh","text":"Hi [laugh] there"}}' auk-flash yes)" "$WORK/r-inline.json"
refuse "$(body audio.edit_speech '{"audio":'"$(U $REF)"'}' '{"edit":{"kind":"remove_cue"}}' auk-flash yes)" "$WORK/r-allcues.json"
refuse "$(body audio.edit_speech '{"audio":'"$(U $REF)"'}' '{"edit":{"kind":"trim_silence"}}' auk-flash yes)" "$WORK/r-trim.json"
refuse "$(body audio.separate '{"audio":'"$(U $MIX)"'}' '{"stems":["voices"]}' auk-flash yes)" "$WORK/r-voices.json"
refuse "$(body audio.separate '{"audio":'"$(U $MIX)"'}' '{"stems":["speaker"]}' auk-flash yes)" "$WORK/r-nopick.json"
py "
import wave; w = wave.open('$MIX'); p = w.getparams(); f = w.readframes(p.nframes)
o = wave.open('$WORK/long.wav', 'wb'); o.setparams(p); o.writeframes(f * 7); o.close()"
job "$(body audio.edit_speech '{"audio":'"$(U $WORK/long.wav)"'}' '{"edit":{"kind":"denoise"}}' auk-flash yes)" > "$WORK/f-longtake.json"
job "$(body audio.separate '{"audio":'"$(U $WORK/long.wav)"'}' '{"speaker":{"ordinal":1}}' auk-flash yes)" > "$WORK/f-longmix.json"
job "$(body audio.edit_speech '{"audio":'"$(U $REF)"'}' '{"edit":{"kind":"replace_text","text":"今天","with":"明天"}}' auk-flash yes '{"x-gaea.lane":"int4"}')" > "$WORK/f-int4.json"
for f in $WORK/r-*.json; do say "      $(basename $f .json): $(cat $f.status) $(py "import json; e=json.load(open('$f')).get('error', {}); print(e.get('code'), e.get('param'), '-', (e.get('message') or '')[:110])")"; done
for f in $WORK/f-long*.json; do say "      $(basename $f .json): $(py "import json; j=json.load(open('$f')); e=j.get('error') or {}; print(j.get('outcome'), e.get('code'), e.get('param'), '-', (e.get('message') or '')[:110])")"; done
say "      f-int4: $(py "import json; j=json.load(open('$WORK/f-int4.json')); e=j.get('error') or {}; print(j.get('outcome'), e.get('code'), e.get('param'), '-', (e.get('message') or '')[:110])")"
check "a cue placed inline is 422 (cue_placement edge)" refused "$WORK/r-inline.json" 422 unsupported_parameter edit
check "removing every cue is 422 (remove_all_cues false)" refused "$WORK/r-allcues.json" 422 unsupported_parameter edit
check "trim_silence is 422" refused "$WORK/r-trim.json" 422 unsupported_parameter edit
check "the voices stem on AuK-Flash is 422" refused "$WORK/r-voices.json" 422 unsupported_parameter stems
check "the speaker stem without a pick is 400" refused "$WORK/r-nopick.json" 400 invalid_request speaker
check "a 38 s take fails out_of_limits on audio, measured when it runs" failed "$WORK/f-longtake.json" out_of_limits audio
check "a 38 s mixture fails out_of_limits on audio, measured when it runs" failed "$WORK/f-longmix.json" out_of_limits audio
check "a Mandarin edit on the int4 lane is refused, naming the lane" failed "$WORK/f-int4.json" unsupported_parameter x-gaea.lane

$CLI ledger > "$OUT/ledger.txt"
stop $P

# 4. The in-process side.
inproc() { "$INPROC" "$@" --models-root "$MODELS" 2>> "$LOG" | tail -1 }
inproc speak --ref "$REF" --ref-text "$REFTEXT" --text "$EN" --seed 42 --out "$OUT/inproc-clone.wav" > "$OUT/inproc-clone.json"
inproc speak --ref "$REF" --text 'This line has to fit the cue. [pause 0.5s] Exactly.' --target-duration 4.0 --seed 7 --out "$OUT/inproc-fitted.wav" > /dev/null
inproc design --description "$DESC" --count 2 --language en --seed 7 --out-dir "$OUT/inproc-design" > /dev/null
inproc edit --take "$REF" --transcript "$REFTEXT" --edit '{"kind":"replace_text","text":"river","with":"harbour"}' --seed 3 --out "$OUT/inproc-replace.wav" > /dev/null
inproc edit --take "$REF" --edit '{"kind":"emotion","emotion":"happy"}' --seed 3 --out "$OUT/inproc-happy.wav" > /dev/null
inproc separate --mixture "$MIX" --ordinal 2 --seed 5 --out-dir "$OUT/inproc-ordinal" > /dev/null
inproc separate --mixture "$MIX" --saying 'coat pocket' --seed 5 --out-dir "$OUT/inproc-saying" > /dev/null
inproc separate --model auk --mixture "$MIX" --stems voices --seed 9 --out-dir "$OUT/inproc-voices" > /dev/null
check "the clone through Gaea is auk-inproc's, byte for byte" cmp "$OUT/gaea-clone-audio.wav" "$OUT/inproc-clone.wav"
check "the fit through Gaea is auk-inproc's, byte for byte" cmp "$OUT/gaea-fitted-audio.wav" "$OUT/inproc-fitted.wav"
check "design sample 1 through Gaea is auk-inproc's, byte for byte" cmp "$OUT/gaea-design-samples.wav" "$OUT/inproc-design/samples-1.wav"
check "the replace through Gaea is auk-inproc's, byte for byte" cmp "$OUT/gaea-edit-replace-audio.wav" "$OUT/inproc-replace.wav"
check "the emotion edit through Gaea is auk-inproc's, byte for byte" cmp "$OUT/gaea-edit-happy-audio.wav" "$OUT/inproc-happy.wav"
check "the second speaker through Gaea is auk-inproc's, byte for byte" cmp "$OUT/gaea-sep-ordinal-speaker.wav" "$OUT/inproc-ordinal/speaker.wav"
check "the speaker who says the words through Gaea is auk-inproc's, byte for byte" cmp "$OUT/gaea-sep-saying-speaker.wav" "$OUT/inproc-saying/speaker.wav"
check "Base's voices through Gaea are auk-inproc's, byte for byte" cmp "$OUT/gaea-sep-voices-voices.wav" "$OUT/inproc-voices/voices.wav"
say "      in-process clone: $(cat "$OUT/inproc-clone.json")"

for s in $H/Logs/sessions/*.gpp; do check "transcript $(basename $s) passes validate.py" python3 tools/validate.py --transcript "$s"; done
mkdir -p "$OUT/sessions"; cp $H/Logs/sessions/*.gpp "$OUT/sessions/"
say "== $pass passed, $fail failed"
exit $(( fail > 0 ))
