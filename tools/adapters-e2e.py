#!/usr/bin/env python3
"""AB-T-0378: adapters through MES on one running Gaea: the offer lists them, a request naming one runs and records it in
provenance, and what the offer doesn't allow is refused at submit.

    tools/adapters-e2e.py <port> <out-dir> <adapter-id> [<model>]

Writes <out-dir>/e2e.json (each case's request, outcome and the result's provenance.adapters) and the run's image.
"""
import json, sys, time, urllib.error, urllib.request
from pathlib import Path

H = {"MES-Version": "0.1", "Content-Type": "application/json"}


def call(url, body=None):
    req = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(), headers=H)
    try:
        with urllib.request.urlopen(req, timeout=900) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def main():
    port, out, adapter = int(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
    model = sys.argv[4] if len(sys.argv) > 4 else "qwen-image-flash"
    base = f"http://127.0.0.1:{port}/mes/v0"
    out.mkdir(parents=True, exist_ok=True)
    report = {}

    # The offer: the adapter, its strength range and licence, and max_adapters.
    _, data = call(f"{base}/operations/image.generate")
    gen = json.loads(data)
    offer = next(m for m in gen["models"] if m["id"] == model)
    listed = next((a for a in offer.get("adapters", []) if a["id"] == adapter), None)
    report["offer"] = {"model": model, "max_adapters": offer.get("max_adapters"), "adapters": len(offer.get("adapters", [])),
                       "adapter": listed}
    print("offer:", json.dumps(report["offer"])[:400])

    def job(adapters, seed=42):
        return {"operation": "image.generate", "model": model, "adapters": adapters,
                "params": {"seed": seed, "size": {"width": 1024, "height": 1024}},
                "inputs": {"prompt": "a lighthouse on a cliff at dusk, concept art"}}

    # Refused at submit.
    for name, adapters in [("unknown adapter", [{"id": "qwen-image:no-such-lora", "strength": 1}]),
                           ("strength out of range", [{"id": adapter, "strength": 3.5}]),
                           ("opt-in adapter not enabled", [{"id": "qwen-image:martha", "strength": 1}])]:
        status, data = call(f"{base}/jobs", job(adapters))
        body = json.loads(data or b"{}")
        report[name] = {"status": status, "error": body.get("error", body)}
        print(f"{name}: {status} {json.dumps(body.get('error', body))[:200]}")

    # Runs, and provenance records it.
    start = time.monotonic()
    status, data = call(f"{base}/jobs", job([{"id": adapter, "strength": 0.8}]))
    j = json.loads(data)
    while j.get("state") not in ("holding", "purged") and status < 300:
        status, data = call(f"{base}/jobs/{j['id']}?wait=10")
        j = json.loads(data)
    result = j.get("result") or {}
    prov = result.get("provenance") or {}
    files = []
    for k, o in enumerate(result.get("outputs") or []):
        if "href" in o:
            _, img = call(f"http://127.0.0.1:{port}{o['href']}")
            f = out / f"run-{k}.png"
            f.write_bytes(img)
            files.append(f.name)
    report["run"] = {"outcome": j.get("outcome"), "error": j.get("error"), "wall_s": round(time.monotonic() - start, 1),
                     "adapters": prov.get("adapters"), "licenses": prov.get("licenses"), "timings": prov.get("timings"),
                     "files": files}
    print("run:", json.dumps(report["run"])[:900])
    (out / "e2e.json").write_text(json.dumps(report, indent=1))


main()
