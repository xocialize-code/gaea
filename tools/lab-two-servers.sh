#!/bin/zsh
# AB-T-0372 (G-19): Gaea Lab's lab-run over two Gaea servers with different plugins. Each job names what only one server
# has (a model, an adapter, an operation), and lab-run's EnginePool must send it there. Prints each job and where it ran;
# writes each result and a JSON report per job.
#
#   tools/lab-two-servers.sh <lab-run> <server-A-url> <server-B-url> <photo.png> <out-dir>
set -euo pipefail
LR=$1 A=$2 B=$3 PHOTO=$4 OUT=$5
mkdir -p $OUT
n=0
job() {  # name, expected server (A or B), lab-run arguments…
  local name=$1 expect=$2; shift 2
  n=$((n + 1))
  print "\n== $n. $name (expect server $expect)"
  print "lab-run --engine $A --engine $B $*"
  "$LR" --engine $A --engine $B "$@" --out $OUT/$name --report $OUT/$name.json
}
job zimage-generate A --operation image.generate --model z-image-turbo --text "prompt=a lighthouse on a cliff at dusk" --param seed=7
job flash-lora B --operation image.generate --model qwen-image-flash --adapter qwen-image:martha=0.8 --text "prompt=a lighthouse on a cliff at dusk" --param seed=7
job lora-implies-model B --operation image.generate --adapter qwen-image:martha=0.8 --text "prompt=a lighthouse on a cliff at dusk" --param seed=7
job upscale A --operation image.upscale --file image=$PHOTO --param scale=2
job klein-edit B --operation image.edit --model klein-4b --file images=$PHOTO --text "instruction=make it a snowy winter scene" --param seed=7
job score A --operation image.score --file image=$PHOTO
print "\n== where each job ran"
for f in $OUT/*.json; do
  python3 -c "import json,sys; r=json.load(open(sys.argv[1])); p=r.get('provenance') or {}; print(f\"{sys.argv[1].split('/')[-1][:-5]:20} {r['engine']:40} model {(p.get('model') or {}).get('id')}\")" $f
done
