#!/usr/bin/env python3
"""AB-T-0377: what each quality tier routes to, and what it makes, for the operations G1's coverage adds, against one
running engine (Gaea or pixel-agency-image-engine).

For each tier: relight, colorize, every restore kind (scratches included), and upscale ×2 and ×4 of a photo and of a
drawing, with no model named, so the engine picks; describe and score, which take no quality, once. Then the models
only a request that names one reaches: DRUNet, Anime4K VL, VOSR2 and Nacre. Each job records the model the plan names,
what ran (`effective.model_params`), its outputs' sha256 and its values (a description, a score).

    tools/coverage-routing.py <port> <fixtures-dir> <out-dir>
    tools/coverage-routing.py --compare <gaea-out> <engine-out>

<fixtures-dir> is gaea-plugin-forge's scripts/fixtures (fox, its dark, grey and scratched copies, a face, a sign).
"""
import hashlib, json, sys, time, urllib.error, urllib.request
from pathlib import Path

H = {"MES-Version": "0.1"}
TIERS = ["draft", "standard", "best"]


def call(url, data=None, ctype="application/json"):
    req = urllib.request.Request(url, data=data, headers={**H, "Content-Type": ctype})
    with urllib.request.urlopen(req, timeout=1800) as r:
        return r.read()


def jobs():
    out = []
    for tier in TIERS:
        q = {"quality": tier}
        out += [
            (f"relight-{tier}", {"operation": "image.relight", "params": q, "inputs": {"image": "fox-dark-256.png"}}),
            (f"colorize-{tier}", {"operation": "image.colorize", "params": q, "inputs": {"image": "fox-grey-256.png"}}),
        ]
        for kind, image in [("general", "fox-256.png"), ("denoise", "fox-256.png"), ("deblur", "fox-256.png"),
                            ("faces", "face-512.png"), ("scratches", "fox-scratched-256.png")]:
            out.append((f"restore-{kind}-{tier}", {"operation": "image.restore", "params": {**q, "kind": kind}, "inputs": {"image": image}}))
        for scale in (2, 4):
            out.append((f"upscale-photo-x{scale}-{tier}", {"operation": "image.upscale", "params": {**q, "scale": scale},
                                                          "inputs": {"image": "fox-256.png"}}))
            out.append((f"upscale-drawn-x{scale}-{tier}", {"operation": "image.upscale", "params": {**q, "scale": scale, "content": "drawn"},
                                                          "inputs": {"image": "sign-256.png"}}))
    out += [
        ("describe", {"operation": "image.describe", "inputs": {"image": "fox-256.png"}}),
        ("describe-sign", {"operation": "image.describe", "inputs": {"image": "sign-256.png"}}),
        ("score", {"operation": "image.score", "inputs": {"image": "fox-256.png"}}),
        ("score-grey", {"operation": "image.score", "inputs": {"image": "fox-grey-256.png"}}),
        ("named-drunet", {"operation": "image.restore", "model": "drunet-denoise", "params": {"kind": "denoise"}, "inputs": {"image": "fox-256.png"}}),
        ("named-anime4k-x2", {"operation": "image.upscale", "model": "anime4k-upscale", "params": {"scale": 2}, "inputs": {"image": "sign-256.png"}}),
        ("named-anime4k-x4", {"operation": "image.upscale", "model": "anime4k-upscale", "params": {"scale": 4}, "inputs": {"image": "fox-256.png"}}),
        ("named-vosr2-x4", {"operation": "image.upscale", "model": "vosr2-upscale", "params": {"quality": "best", "scale": 4}, "inputs": {"image": "fox-256.png"}}),
        ("named-nacre-x4", {"operation": "image.upscale", "model": "nacre-upscale", "params": {"quality": "best", "scale": 4}, "inputs": {"image": "fox-256.png"}}),
        ("named-nacre-sign-x2", {"operation": "image.upscale", "model": "nacre-upscale", "params": {"quality": "best", "scale": 2}, "inputs": {"image": "sign-256.png"}}),
    ]
    return out


def run(port, fixtures, out):
    base = f"http://127.0.0.1:{port}/mes/v0"
    out.mkdir(parents=True, exist_ok=True)
    results = []
    for name, body in jobs():
        b = json.loads(json.dumps(body))
        for key, value in list(b["inputs"].items()):
            b["inputs"][key] = {"upload": json.loads(call(f"{base}/uploads", (fixtures / value).read_bytes(), "image/png"))["upload_id"]}
        start = time.monotonic()
        try:
            job = json.loads(call(f"{base}/jobs", json.dumps(b).encode()))
            while job["state"] not in ("holding", "purged"):
                job = json.loads(call(f"{base}/jobs/{job['id']}?wait=10"))
        except urllib.error.HTTPError as e:
            job = {"outcome": "refused", "error": json.loads(e.read() or b"{}")}
        wall = time.monotonic() - start
        result = job.get("result") or {}
        files, values = [], {}
        for k, o in enumerate(result.get("outputs") or []):
            if "href" in o:
                data = call(f"http://127.0.0.1:{port}{o['href']}")
                f = out / f"{name}-{k}.{'json' if o.get('kind') == 'data' else 'png'}"
                f.write_bytes(data)
                files.append(f.name)
                if o.get("kind") == "data":
                    values[o.get("name", str(k))] = json.loads(data)
            elif "value" in o:
                values[o.get("name", str(k))] = o["value"]
        mp = (result.get("effective") or {}).get("model_params") or {}
        r = {"name": name, "outcome": job.get("outcome"), "error": job.get("error"),
             "model": (job.get("plan") or {}).get("model", {}).get("id"), "ran": mp.get("model"),
             "model_params": mp, "files": files, "sha256": [hashlib.sha256((out / f).read_bytes()).hexdigest() for f in files],
             "values": values, "run_ms": ((result.get("provenance") or {}).get("timings") or {}).get("run_ms"), "wall_ms": round(wall * 1000)}
        print(json.dumps(r)[:400], flush=True)
        results.append(r)
    (out / "coverage.json").write_text(json.dumps(results, indent=1))


def compare(a, b):
    ra = {r["name"]: r for r in json.loads((a / "coverage.json").read_text())}
    rb = {r["name"]: r for r in json.loads((b / "coverage.json").read_text())}
    print("| Job | Gaea's model | v0.9.1's model | Same model | Same output | Gaea / v0.9.1 run (ms) |\n|---|---|---|---|---|---|")
    counts = {"jobs": 0, "same_model": 0, "same_output": 0}
    for name, x in ra.items():
        y = rb.get(name)
        if y is None: continue
        counts["jobs"] += 1
        mx = x["model_params"].get("model") or x["model"]; my = y["model_params"].get("model") or y["model"]
        same_model = mx == my and x["model_params"].get("detector") == y["model_params"].get("detector")
        if x["files"] and y["files"]:
            # A data output is compared by value (the JSON's own bytes may order keys differently), an image byte for byte.
            same_out = x["sha256"] == y["sha256"] or (x["values"] and x["values"] == y["values"])
        else:
            same_out = x["outcome"] == y["outcome"] and x["error"] and y["error"]
        counts["same_model"] += bool(same_model); counts["same_output"] += bool(same_out)
        show = lambda r, m: m + (f" (+{r['model_params']['detector']})" if r["model_params"].get("detector") else "") if m else f"{r['outcome']}: {(r['error'] or {}).get('code', '')}"
        print(f"| {name} | {show(x, mx)} | {show(y, my)} | {'yes' if same_model else '**no**'} | {'yes' if same_out else '**no**'} | {x['run_ms']} / {y['run_ms']} |")
    print(f"\n{counts['jobs']} jobs: the same model in {counts['same_model']}, the same output in {counts['same_output']}.")


if __name__ == "__main__":
    if sys.argv[1] == "--compare":
        compare(Path(sys.argv[2]), Path(sys.argv[3]))
    else:
        run(int(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
