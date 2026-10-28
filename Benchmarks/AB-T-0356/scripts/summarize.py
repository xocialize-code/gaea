#!/usr/bin/env python3
"""Summarize AB-T-0356's raw JSON lines: n, median, min, max and standard deviation per metric.

    python3 scripts/summarize.py <raw-dir>  > summary.md

Spool runs are grouped by volume and case; each case's warm-up run (run 0) is left out.
"""
import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def flatten(obj, prefix=""):
    out = {}
    for key, value in obj.items():
        name = f"{prefix}{key}"
        if isinstance(value, dict):
            out.update(flatten(value, name + "."))
        elif isinstance(value, bool):
            out[name] = int(value)
        elif isinstance(value, (int, float)):
            out[name] = value
    return out


def fmt(value, key):
    if key.endswith("_s") or key.endswith("_s_per_frame") or ".encode" in key or ".denoise" in key \
            or ".decode" in key or ".postprocess" in key or "phase_first" in key:
        return f"{value * 1000:.2f} ms" if abs(value) < 0.1 else f"{value:.3f} s"
    if "phys" in key or "bytes" in key or "sys_anon" in key or key.endswith("gpu_active"):
        return f"{value / 1e6:,.1f} MB"
    return f"{value:,.3f}".rstrip("0").rstrip(".")


def table(rows, title, keys=None):
    flat = [flatten(r) for r in rows]
    keys = keys or sorted({k for f in flat for k in f})
    print(f"\n### {title} (n={len(rows)})\n")
    print("| metric | median | min | max | stdev |")
    print("|---|---:|---:|---:|---:|")
    for key in keys:
        values = [f[key] for f in flat if key in f]
        if not values or key in ("pid", "run", "main_at", "warmup", "count", "width", "height", "parallel"):
            continue
        sd = statistics.stdev(values) if len(values) > 1 else 0.0
        print(f"| {key} | {fmt(statistics.median(values), key)} | {fmt(min(values), key)} | "
              f"{fmt(max(values), key)} | {fmt(sd, key)} |")


def main():
    raw = Path(sys.argv[1])
    for name in ("baseline", "baseline-first-launch", "zimage-worker", "zimage-inproc"):
        path = raw / f"{name}.jsonl"
        if path.exists():
            rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
            table(rows, name)
    for path in sorted(raw.glob("spool-*.jsonl")):
        groups = defaultdict(list)
        for line in path.read_text().splitlines():
            if line.strip():
                r = json.loads(line)
                if not r.get("warmup"):
                    groups[r["case"]].append(r)
        for case, rows in groups.items():
            table(rows, f"{path.stem} · {case}")


if __name__ == "__main__":
    main()
