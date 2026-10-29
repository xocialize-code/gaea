#!/usr/bin/env python3
"""AB-T-0377: warm timing over GPP, with no Gaea in between. One worker, one model, N runs of one call; prints each run's
wall seconds (run sent → result) and how many progress lines it sent. The worker is configured as Gaea's scheduler
configures it (a 64 GB WorkerBudget, wiresWeights off); WIRED=1 turns wiring on, as an in-process engine does.

    tools/gpp-warm-time.py <bundle> <models-root> <model> <lane> <operation> <params-json> <image> <runs>
"""
import json, os, subprocess, sys, tempfile, time
WIRED = os.environ.get("WIRED") == "1"
bundle, root, model, lane, op, params, image, n = sys.argv[1:9]
m = json.load(open(os.path.join(bundle, "Contents/Resources/manifest.json")))
w = subprocess.Popen([os.path.join(bundle, "Contents/MacOS", m["executable"])], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
def send(x): w.stdin.write(json.dumps(x) + "\n"); w.stdin.flush()
def until(rid, finals, lines=None):
    for line in w.stdout:
        x = json.loads(line)
        if lines is not None and x.get("type") == "progress": lines.append(time.monotonic())
        if x.get("re") == rid and x["type"] in finals + ["error"]:
            if x["type"] == "error": sys.exit(f"error {x}")
            return x
work = tempfile.mkdtemp(prefix="gppt"); os.makedirs(work + "/cache"); 
assert json.loads(w.stdout.readline())["type"] == "hello"
send({"type": "configure", "id": "c", "budget": {"ceilingBytes": 64_000_000_000, "wiresWeights": WIRED}, "models_root": root, "cache_root": work + "/cache", "settings": {}})
until("c", ["configured"]); send({"type": "prepare", "id": "p", "model": model, "lane": lane}); until("p", ["prepared"])
times = []
for i in range(int(n)):
    out = f"{work}/out{i}"; os.makedirs(out)
    lines = []; t = time.monotonic()
    send({"type": "run", "id": f"r{i}", "job": f"j{i}", "operation": op, "model": model, "lane": lane, "inputs": {"image": image},
          "params": json.loads(params), "seed": 0, "output_dir": out})
    r = until(f"r{i}", ["result"], lines); dt = time.monotonic() - t; times.append(round(dt, 3))
    print(json.dumps({"run": i, "wall_s": round(dt, 3), "worker_s": r.get("seconds"), "progress_lines": len(lines)}), flush=True)
send({"type": "shutdown", "id": "s"}); w.wait(timeout=20)
print(json.dumps({"model": model, "op": op, "params": params, "warm_s": times[1:]}))
