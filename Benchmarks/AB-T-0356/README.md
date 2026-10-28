# AB-T-0356 harness

What running a model out of process costs: a worker's fixed footprint, Z-Image Turbo's cold start through a worker
against in-process, and spool throughput. The results and the verdict are in
[Docs/Evidence/AB-T-0356](../../Docs/Evidence/AB-T-0356/README.md). Not a plugin; never published.

```bash
BENCH_SCRATCH=/some/internal/disk/folder scripts/build.sh   # Release; signs bench.gaeaplugin with Developer ID
BENCH_SCRATCH=… scripts/run.sh baseline                     # worker fixed cost
BENCH_SCRATCH=… scripts/run.sh zimage                       # Z-Image Turbo int4, worker and in-process
BENCH_SCRATCH=… scripts/run.sh spool internal               # then: spool external
python3 scripts/summarize.py ../../Docs/Evidence/AB-T-0356/raw > ../../Docs/Evidence/AB-T-0356/summary.md
```

Z-Image Turbo's bf16 snapshot (19 GB) must already be in `~/Library/Application Support/MLXEngine/Models`.
