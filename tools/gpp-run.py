#!/usr/bin/env python3
"""Sends one run straight to a plugin's worker over GPP (no Gaea), for comparing what a host serves with what the
worker writes (AB-T-0364's acceptance).

    python3 tools/gpp-run.py <bundle.gaeaplugin> <work-dir> <model> <lane> <operation> <params-json> <model-params-json>
                             <seed> [<prompt>]

Prints {"outputs": [...], "sha256": [one per file output], "effective": {...}, "warnings": [...]} on stdout. The worker
is launched directly (a host would also check its signature and launch requirement; this tool trusts the bundle).
"""
import hashlib
import json
import os
import subprocess
import sys


def main():
    bundle, work, model, lane, operation, params, model_params, seed = sys.argv[1:9]
    prompt = sys.argv[9] if len(sys.argv) > 9 else None
    manifest = json.load(open(os.path.join(bundle, "Contents/Resources/manifest.json")))
    executable = os.path.join(bundle, "Contents/MacOS", manifest["executable"])
    for sub in ("models", "cache", "in", "out"):
        os.makedirs(os.path.join(work, sub), exist_ok=True)
    work = os.path.realpath(work)

    worker = subprocess.Popen([executable], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)

    def send(message):
        worker.stdin.write(json.dumps(message) + "\n")
        worker.stdin.flush()

    def until(request_id, finals):
        for line in worker.stdout:
            message = json.loads(line)
            if message.get("re") == request_id and message["type"] in finals + ["error"]:
                if message["type"] == "error":
                    sys.exit(f"worker error: {message}")
                return message
        sys.exit("the worker exited")

    hello = json.loads(worker.stdout.readline())
    assert hello["type"] == "hello", hello
    send({"type": "configure", "id": "h1", "budget": {"ceilingBytes": 8_000_000_000, "wiresWeights": False},
          "models_root": os.path.join(work, "models"), "cache_root": os.path.join(work, "cache"), "settings": {}})
    until("h1", ["configured"])
    send({"type": "prepare", "id": "h2", "model": model, "lane": lane})
    until("h2", ["prepared"])
    inputs = {}
    if prompt is not None:
        path = os.path.join(work, "in", "prompt-0.txt")
        open(path, "w").write(prompt)
        inputs["prompt"] = path
    run = {"type": "run", "id": "h3", "job": "job_direct", "operation": operation, "model": model, "lane": lane,
           "inputs": inputs, "params": json.loads(params), "seed": int(seed), "output_dir": os.path.join(work, "out")}
    if json.loads(model_params):
        run["model_params"] = json.loads(model_params)
    send(run)
    result = until("h3", ["result"])
    send({"type": "shutdown", "id": "h4"})
    worker.wait(timeout=10)
    digests = [hashlib.sha256(open(o["path"], "rb").read()).hexdigest() for o in result["outputs"] if "path" in o]
    print(json.dumps({"outputs": result["outputs"], "sha256": digests, "effective": result.get("effective", {}),
                      "warnings": result.get("warnings", [])}))


if __name__ == "__main__":
    main()
