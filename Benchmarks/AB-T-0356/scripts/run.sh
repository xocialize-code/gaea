#!/bin/zsh
# Runs the AB-T-0356 measurements against a built harness (scripts/build.sh) and appends one JSON line
# per run to Docs/Evidence/AB-T-0356/raw/.
#
#   scripts/run.sh baseline [runs]        worker fixed cost (default 7 runs)
#   scripts/run.sh zimage [runs]          Z-Image Turbo int4: worker and in-process, alternated (default 5 each)
#   scripts/run.sh spool <internal|external> [runs]   spool throughput (default 5 runs per case)
#
# BENCH_SCRATCH must match the build. Nothing else should be using the GPU while this runs.
set -euo pipefail
ROOT=${0:A:h:h}
REPO=${ROOT:h:h}
SCRATCH=${BENCH_SCRATCH:-$TMPDIR/gaea-bench-ab-t-0356}
RAW=$REPO/Docs/Evidence/AB-T-0356/raw
mkdir -p $RAW
HOST=$SCRATCH/bench-host
INPROC=$SCRATCH/bench-inproc
BUNDLE=$SCRATCH/bench.gaeaplugin
PROMPT="A lighthouse on a rocky coast at dusk, photorealistic, 35mm film"

case ${1:-} in
baseline)
  for i in $(seq ${2:-7}); do $HOST baseline --bundle $BUNDLE | tee -a $RAW/baseline.jsonl; done
  ;;
zimage)
  # One unrecorded pass of each first, so both modes find the 19 GB bf16 snapshot in the file cache.
  $INPROC --prompt $PROMPT > /dev/null
  $HOST zimage --bundle $BUNDLE --prompt $PROMPT > /dev/null
  for i in $(seq ${2:-5}); do
    $HOST zimage --bundle $BUNDLE --prompt $PROMPT --out $SCRATCH/zimage-worker.png | tee -a $RAW/zimage-worker.jsonl
    $INPROC --prompt $PROMPT --out $SCRATCH/zimage-inproc.png | tee -a $RAW/zimage-inproc.jsonl
  done
  cmp $SCRATCH/zimage-worker.png $SCRATCH/zimage-inproc.png && print "worker and in-process PNGs are byte-identical"
  ;;
spool)
  where=${2:?internal or external}
  if [[ $where == internal ]]; then SPOOL=$SCRATCH/spool; else SPOOL=/Volumes/Satechi/gaea-bench-spool; fi
  SOURCE=$SCRATCH/zimage-worker.png
  [[ -f $SOURCE ]] || { print -u2 "run zimage first: the spool cases scale its output"; exit 1 }
  for c in 4k-png 4k-tiff16 1080p-raw-120 1080p-raw-600 1080p-png-120 1080p-png-120-par 1080p-png-600-par; do
    $HOST spool --bundle $BUNDLE --root $SPOOL --source $SOURCE --case $c --runs ${3:-5} \
      | sed "s/\"mode\":\"spool\"/\"mode\":\"spool\",\"volume\":\"$where\"/" | tee -a $RAW/spool-$where.jsonl
  done
  rm -rf $SPOOL
  ;;
*)
  print -u2 "usage: run.sh baseline|zimage|spool <internal|external> [runs]"; exit 2
  ;;
esac
