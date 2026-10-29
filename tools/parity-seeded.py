#!/usr/bin/env python3
"""AB-T-0373: seeded jobs for what TierBench sends unseeded (its tiers and edits suites), against one running engine.

Each job runs three times on a freshly started engine: the first is the model's first use, the other two warm. The
outputs are downloaded and the job's own timings kept, with the wall time from submit to settled.

    tools/parity-seeded.py <port> <inputs-dir> <out-dir>

<inputs-dir> is a TierBench run's `inputs` folder (edit-0831.png, edit-mask.png). Compare two out-dirs with
`tools/parity-seeded.py --compare <gaea-out> <engine-out>`.
"""
import hashlib, json, sys, time, urllib.request
from pathlib import Path

H = {"MES-Version": "0.1"}


def call(url, data=None, ctype="application/json", method=None):
    req = urllib.request.Request(url, data=data, headers={**H, "Content-Type": ctype}, method=method)
    with urllib.request.urlopen(req, timeout=900) as r:
        return r.read()


def jobs(photo, mask):
    edit = {"images": [photo], "instruction": "make it a snowy winter scene"}
    return [
        ("klein-generate-draft", {"operation": "image.generate", "params": {"quality": "draft", "seed": 7, "size": {"width": 512, "height": 512}},
                                  "inputs": {"prompt": "a small wooden boat on a lake"}}),
        ("zimage-generate-standard", {"operation": "image.generate", "params": {"quality": "standard", "seed": 7, "size": {"width": 512, "height": 512}},
                                      "inputs": {"prompt": "a small wooden boat on a lake"}}),
        ("klein-edit", {"operation": "image.edit", "model": "klein-4b", "params": {"seed": 7}, "inputs": edit}),
        ("klein-fill", {"operation": "image.fill", "model": "klein-4b", "params": {"seed": 7},
                        "inputs": {"image": photo, "mask": mask, "prompt": "a small wooden bench"}}),
    ]


def run(port, inputs, out):
    base = f"http://127.0.0.1:{port}/mes/v0"
    out.mkdir(parents=True, exist_ok=True)
    results = []
    for name, body in jobs("PHOTO", "MASK"):
        for i in range(3):
            # Uploads are single-use: a fresh one per job.
            def upload(path):
                return {"upload": json.loads(call(f"{base}/uploads", path.read_bytes(), "image/png"))["upload_id"]}
            text = json.dumps(body)
            b = json.loads(text)
            for key, value in list(b["inputs"].items()):
                if value == "PHOTO": b["inputs"][key] = upload(inputs / "edit-0831.png")
                if value == "MASK": b["inputs"][key] = upload(inputs / "edit-mask.png")
                if value == ["PHOTO"]: b["inputs"][key] = [upload(inputs / "edit-0831.png")]
            start = time.monotonic()
            job = json.loads(call(f"{base}/jobs", json.dumps(b).encode()))
            while job["state"] not in ("holding", "purged"):
                job = json.loads(call(f"{base}/jobs/{job['id']}?wait=10"))
            wall = time.monotonic() - start
            files = []
            for k, o in enumerate((job.get("result") or {}).get("outputs") or []):
                if "href" in o:
                    f = out / f"{name}-{i}-{k}.png"; f.write_bytes(call(f"http://127.0.0.1:{port}{o['href']}")); files.append(f.name)
            t = ((job.get("result") or {}).get("provenance") or {}).get("timings") or {}
            mp = ((job.get("result") or {}).get("effective") or {}).get("model_params") or {}
            r = {"name": name, "i": i, "outcome": job.get("outcome"), "error": job.get("error"), "model": (job.get("plan") or {}).get("model", {}).get("id"),
                 "queue_ms": t.get("queue_ms"), "run_ms": t.get("run_ms"), "wall_ms": round(wall * 1000), "files": files,
                 "prompt_enhancement": mp.get("prompt_enhancement")}
            print(json.dumps(r)[:300], flush=True)
            results.append(r)
    (out / "seeded.json").write_text(json.dumps(results, indent=1))


def compare(a, b):
    ra = json.loads((a / "seeded.json").read_text()); rb = json.loads((b / "seeded.json").read_text())
    print("| Job | Run | Gaea run / wall (ms) | Engine run / wall (ms) | Same bytes |\n|---|---|---|---|---|")
    for x, y in zip(ra, rb):
        same = all(hashlib.sha256((a / f).read_bytes()).digest() == hashlib.sha256((b / g).read_bytes()).digest()
                   for f, g in zip(x["files"], y["files"])) and len(x["files"]) == len(y["files"]) > 0
        print(f"| {x['name']} | {'first use' if x['i'] == 0 else 'warm'} | {x['run_ms']} / {x['wall_ms']} | {y['run_ms']} / {y['wall_ms']} | {'yes' if same else '**no**'} |")


if sys.argv[1] == "--compare":
    compare(Path(sys.argv[2]), Path(sys.argv[3]))
else:
    run(int(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
