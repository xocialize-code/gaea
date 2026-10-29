#!/usr/bin/env python3
"""AB-T-0378: adapter parity against one running engine (Gaea, or pixel-agency-image-engine v0.9.1 with --allow-research).

Every adapter the engine offers on Qwen-Image Flash (image.generate) and FLUX.2 Klein 4B (image.edit) runs once, seeded,
on its own: Flash at 1024² with a fixed prompt, Klein editing one photo (an ic adapter's slots filled with the same
photo, then the photo itself). The outputs are downloaded, with each job's provenance.adapters and timings.

    tools/parity-adapters.py <port> <photo.png> <out-dir>
    tools/parity-adapters.py --compare <gaea-out> <engine-out>
"""
import hashlib, json, sys, time, urllib.error, urllib.request
from pathlib import Path

H = {"MES-Version": "0.1"}
PROMPT = "a lighthouse on a cliff at dusk"
INSTRUCTION = "make it a snowy winter scene"


def call(url, data=None, ctype="application/json"):
    req = urllib.request.Request(url, data=data, headers={**H, "Content-Type": ctype})
    try:
        with urllib.request.urlopen(req, timeout=1800) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def run(port, photo, out):
    base = f"http://127.0.0.1:{port}/mes/v0"
    out.mkdir(parents=True, exist_ok=True)

    def offered(operation, model):
        _, data = call(f"{base}/operations/{operation}")
        m = next((m for m in json.loads(data)["models"] if m["id"] == model), None)
        return (m or {}).get("adapters", [])

    def upload():
        return {"upload": json.loads(call(f"{base}/uploads", photo.read_bytes(), "image/png")[1])["upload_id"]}

    # KLEIN_ONLY=1 leaves out Flash; NO_ADAPTERS=1 leaves out every adapter; CONTROL=1 adds an edit without one, on
    # CONTROL_MODEL (default klein-4b).
    import os
    cases = [] if os.environ.get("KLEIN_ONLY") or os.environ.get("NO_ADAPTERS") else \
        [("image.generate", "qwen-image-flash", a) for a in offered("image.generate", "qwen-image-flash")]
    if not os.environ.get("NO_ADAPTERS"):
        cases += [("image.edit", "klein-4b", a) for a in offered("image.edit", "klein-4b")]
    if os.environ.get("CONTROL"):
        cases.append(("image.edit", os.environ.get("CONTROL_MODEL", "klein-4b"), {"id": "none", "strength": {"default": 0}}))
    print(f"{len(cases)} adapters offered", flush=True)
    results = []
    for operation, model, adapter in cases:
        name = adapter["id"].replace(":", "_") if adapter["id"] != "none" else f"none-{model}"
        if operation == "image.generate":
            body = {"operation": operation, "model": model, "params": {"seed": 7, "size": {"width": 1024, "height": 1024}},
                    "inputs": {"prompt": PROMPT}}
        else:
            slots = len(adapter.get("slots") or [])
            body = {"operation": operation, "model": model, "params": {"seed": 7},
                    "inputs": {"images": [upload() for _ in range(slots + 1)], "instruction": INSTRUCTION}}
        if adapter["id"] != "none":
            body["adapters"] = [{"id": adapter["id"], "strength": adapter["strength"]["default"]}]
        start = time.monotonic()
        status, data = call(f"{base}/jobs", json.dumps(body).encode())
        job = json.loads(data)
        while status < 300 and job.get("state") not in ("holding", "purged"):
            status, data = call(f"{base}/jobs/{job['id']}?wait=10")
            job = json.loads(data)
        result = job.get("result") or {}
        prov = result.get("provenance") or {}
        files = []
        for k, o in enumerate(result.get("outputs") or []):
            if "href" in o:
                f = out / f"{name}-{k}.png"
                f.write_bytes(call(f"http://127.0.0.1:{port}{o['href']}")[1])
                files.append(f.name)
        r = {"adapter": adapter["id"], "operation": operation, "model": model, "status": status,
             "outcome": job.get("outcome"), "error": job.get("error") or (job if status >= 300 else None),
             "provenance_adapters": prov.get("adapters"), "run_ms": (prov.get("timings") or {}).get("run_ms"),
             "prompt": (result.get("effective") or {}).get("prompt"),
             "enhancement": ((result.get("effective") or {}).get("model_params") or {}).get("prompt_enhancement"),
             "warnings": [w.get("code") for w in job.get("warnings") or []],
             "wall_ms": round((time.monotonic() - start) * 1000), "files": files,
             "sha256": [hashlib.sha256((out / f).read_bytes()).hexdigest() for f in files]}
        print(json.dumps({k: r[k] for k in ("adapter", "outcome", "run_ms", "sha256")})[:240], flush=True)
        results.append(r)
        (out / "adapters.json").write_text(json.dumps(results, indent=1))


def compare(a, b):
    def key(r): return r["adapter"] if r["adapter"] != "none" else f"none ({r['model']})"
    ra = {key(r): r for r in json.loads((a / "adapters.json").read_text())}
    rb = {key(r): r for r in json.loads((b / "adapters.json").read_text())}
    same = 0
    print("| Adapter | Model | Gaea run (ms) | v0.9.1 run (ms) | Revision and licence | Same prompt | Same bytes |\n|---|---|---|---|---|---|---|")
    for aid in sorted(set(ra) | set(rb)):
        x, y = ra.get(aid), rb.get(aid)
        if not x or not y:
            print(f"| {aid} | | {x and x['run_ms']} | {y and y['run_ms']} | only on {'Gaea' if x else 'v0.9.1'} | | **no** |")
            continue
        ok = bool(x["sha256"]) and x["sha256"] == y["sha256"]
        same += ok
        pa, pb = (x["provenance_adapters"] or [{}])[0], (y["provenance_adapters"] or [{}])[0]
        prov = "same" if (pa.get("revision"), (pa.get("license") or {}).get("spdx")) == (pb.get("revision"), (pb.get("license") or {}).get("spdx")) \
            else f"Gaea {pa.get('revision', '')[:8]} {(pa.get('license') or {}).get('spdx')}, v0.9.1 {pb.get('revision', '')[:8]} {(pb.get('license') or {}).get('spdx')}"
        prompt = "yes" if x.get("prompt") == y.get("prompt") else "**no**"
        print(f"| {aid} | {x['model']} | {x['run_ms']} | {y['run_ms']} | {prov} | {prompt} | {'yes' if ok else '**no**'} |")
    print(f"\n{same} of {len(set(ra) | set(rb))} byte-identical.")


if sys.argv[1] == "--compare":
    compare(Path(sys.argv[2]), Path(sys.argv[3]))
else:
    run(int(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]))
