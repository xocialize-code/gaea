#!/usr/bin/env python3
"""Validates Gaea's v1 schemas, example manifests and GPP transcripts, with no third-party dependencies.

  tools/validate.py                         everything under schemas/ and examples/v1
  tools/validate.py --manifest <file>       one manifest (a plugin's build runs this before it signs)
  tools/validate.py --transcript <file>     one transcript, checked against the manifest its header names

The JSON Schema core (the draft 2020-12 subset these schemas use) is media-engine-spec's tools/validate.py
(MESKit v0.5.0), copied unchanged so both projects reject the same things. Keywords outside the subset are an
error, so a typo in a schema can't silently weaken it. On top of the schemas it checks what JSON Schema can't:
cross-references inside a manifest (offers to models and lanes, one default lane), and the conversation rules
of a transcript (hello first, direction, request ids, which replies a request allows, one ending per request).
"""
import hashlib
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "schemas"
EXAMPLES = ROOT / "examples" / "v1"
MANIFEST_SCHEMA = SCHEMAS / "v1" / "manifest.schema.json"
GPP_SCHEMA = SCHEMAS / "v1" / "gpp.schema.json"

ASSERTIONS = {"type", "enum", "const", "properties", "required", "additionalProperties", "propertyNames",
              "minProperties", "items", "minItems", "maxItems", "minimum", "maximum", "exclusiveMinimum",
              "minLength", "maxLength", "pattern", "oneOf", "anyOf", "allOf", "if", "then", "$ref"}
ANNOTATIONS = {"$schema", "title", "description", "default", "$defs", "$comment"}
_cache = {}


def load(path):
    path = path.resolve()
    if path not in _cache:
        _cache[path] = json.loads(path.read_text())
    return _cache[path]


def pointer(doc, ptr):
    node = doc
    for part in [p for p in ptr.lstrip("/").split("/") if p]:
        part = part.replace("~1", "/").replace("~0", "~")
        node = node[part]
    return node


def resolve(ref, base_file):
    file_part, _, frag = ref.partition("#")
    target = (base_file.parent / file_part) if file_part else base_file
    return pointer(load(target), frag), target.resolve()


def type_ok(value, t):
    if isinstance(t, list):
        return any(type_ok(value, x) for x in t)
    return {
        "object": isinstance(value, dict),
        "array": isinstance(value, list),
        "string": isinstance(value, str),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "number": isinstance(value, (int, float)) and not isinstance(value, bool),
        "boolean": isinstance(value, bool),
        "null": value is None,
    }[t]


def same(a, b):
    return type(a) is type(b) and a == b


def validate(value, schema, file, path="$"):
    """Returns a list of error strings."""
    if schema is True or schema == {}:
        return []
    if schema is False:
        return [f"{path}: not allowed"]
    unknown = {k for k in schema if k not in ASSERTIONS | ANNOTATIONS and not k.startswith("x-")}
    if unknown:
        return [f"{path}: schema uses unsupported keywords {sorted(unknown)} ({file.name})"]
    errs = []
    if "$ref" in schema:
        target, tfile = resolve(schema["$ref"], file)
        errs += validate(value, target, tfile, path)
    if "type" in schema and not type_ok(value, schema["type"]):
        return errs + [f"{path}: expected {schema['type']}, got {type(value).__name__}"]
    if "enum" in schema and not any(same(value, e) for e in schema["enum"]):
        errs.append(f"{path}: {value!r} not in {schema['enum']}")
    if "const" in schema and not same(value, schema["const"]):
        errs.append(f"{path}: expected {schema['const']!r}")
    if isinstance(value, str):
        if "minLength" in schema and len(value) < schema["minLength"]:
            errs.append(f"{path}: shorter than {schema['minLength']}")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            errs.append(f"{path}: longer than {schema['maxLength']}")
        if "pattern" in schema and not re.search(schema["pattern"], value):
            errs.append(f"{path}: {value!r} doesn't match {schema['pattern']}")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errs.append(f"{path}: below {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errs.append(f"{path}: above {schema['maximum']}")
        if "exclusiveMinimum" in schema and value <= schema["exclusiveMinimum"]:
            errs.append(f"{path}: not above {schema['exclusiveMinimum']}")
    if isinstance(value, dict):
        props = schema.get("properties", {})
        for key in schema.get("required", []):
            if key not in value:
                errs.append(f"{path}: missing required '{key}'")
        if "minProperties" in schema and len(value) < schema["minProperties"]:
            errs.append(f"{path}: fewer than {schema['minProperties']} properties")
        for key, sub in value.items():
            if "propertyNames" in schema:
                errs += validate(key, schema["propertyNames"], file, f"{path}.<name {key}>")
            if key in props:
                errs += validate(sub, props[key], file, f"{path}.{key}")
            elif "additionalProperties" in schema:
                ap = schema["additionalProperties"]
                if ap is False:
                    errs.append(f"{path}: unexpected property '{key}'")
                elif isinstance(ap, dict):
                    errs += validate(sub, ap, file, f"{path}.{key}")
    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            errs.append(f"{path}: fewer than {schema['minItems']} items")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errs.append(f"{path}: more than {schema['maxItems']} items")
        if "items" in schema:
            for i, item in enumerate(value):
                errs += validate(item, schema["items"], file, f"{path}[{i}]")
    for sub in schema.get("allOf", []):
        errs += validate(value, sub, file, path)
    if "anyOf" in schema and not any(not validate(value, s, file, path) for s in schema["anyOf"]):
        errs.append(f"{path}: matches none of anyOf")
    if "oneOf" in schema:
        matches = [s for s in schema["oneOf"] if not validate(value, s, file, path)]
        if len(matches) != 1:
            errs.append(f"{path}: matches {len(matches)} of oneOf (needs exactly 1)")
    if "if" in schema and not validate(value, schema["if"], file, path) and "then" in schema:
        errs += validate(value, schema["then"], file, path)
    return errs




def walk_refs(node, file):
    """Every $ref in every schema must resolve."""
    errs = []
    if isinstance(node, dict):
        if "$ref" in node:
            try:
                resolve(node["$ref"], file)
            except (KeyError, FileNotFoundError) as e:
                errs.append(f"{file.name}: unresolved $ref {node['$ref']} ({e})")
        for v in node.values():
            errs += walk_refs(v, file)
    elif isinstance(node, list):
        for v in node:
            errs += walk_refs(v, file)
    return errs


# ---------------------------------------------------------------------------------------------------- manifests

# MES operation -> the MLXEngine capabilities that can serve it. An offer's lanes must back one of them.
OPERATION_CAPABILITIES = {
    "image.generate": {"textToImage"},
    "image.edit": {"imageEdit"},
    "image.fill": {"inpaint", "imageEdit"},
    "image.erase": {"inpaint", "objectRemoval"},
    "image.upscale": {"superResolution", "upscale"},
    "image.matte": {"matting", "backgroundRemoval"},
    "image.segment": {"segmentation"},
    "image.describe": {"imageAnalysis", "caption"},
}


def check_manifest(m, label):
    """Schema, then the rules that span fields. Returns error strings."""
    errs = [f"{label}: {e}" for e in validate(m, load(MANIFEST_SCHEMA), MANIFEST_SCHEMA)]
    if errs:
        return errs
    models = {}
    for model in m["models"]:
        if model["id"] in models:
            errs.append(f"{label}: model id '{model['id']}' appears twice")
        lanes = {lane["id"]: lane for lane in model["lanes"]}
        if len(lanes) != len(model["lanes"]):
            errs.append(f"{label}: model '{model['id']}' repeats a lane id")
        defaults = [lane["id"] for lane in model["lanes"] if lane["default"]]
        if len(defaults) != 1:
            errs.append(f"{label}: model '{model['id']}' needs exactly one default lane, has {len(defaults)}")
        for lane in model["lanes"]:
            quant = lane["resolved"].get("quant")
            if quant and quant != lane["id"] and not lane["id"].startswith(quant):
                errs.append(f"{label}: lane '{lane['id']}' of '{model['id']}' resolves quant {quant}; "
                            f"name the lane after it")
        models[model["id"]] = lanes
    if "engine" in m:
        for model in m["models"]:
            for lane in model["lanes"]:
                v = lane["resolved"]["contractVersion"]
                contract = f"{v['major']}.{v['minor']}.{v['patch']}"
                if contract != m["engine"]["contract"]:
                    errs.append(f"{label}: lane '{model['id']}/{lane['id']}' was resolved under contract {contract}, "
                                f"but engine.contract is {m['engine']['contract']}")
    seen = set()
    for i, offer in enumerate(m["offers"]):
        where = f"{label}: offers[{i}] ({offer['operation']})"
        mid = offer["model"]["id"]
        if not offer["operation"].startswith(offer["profile"] + "."):
            errs.append(f"{where}: operation is not in profile {offer['profile']}")
        if mid not in models:
            errs.append(f"{where}: model '{mid}' is not in models[]")
            continue
        if (offer["operation"], mid) in seen:
            errs.append(f"{where}: a second offer of '{mid}' for the same operation")
        seen.add((offer["operation"], mid))
        lane_ids = offer.get("lanes", list(models[mid]))
        for lane_id in lane_ids:
            if lane_id not in models[mid]:
                errs.append(f"{where}: lane '{lane_id}' is not a lane of '{mid}'")
        wanted = OPERATION_CAPABILITIES.get(offer["operation"])
        if wanted:
            backing = [l for l in lane_ids if l in models[mid] and wanted & set(models[mid][l]["resolved"]["capabilities"])]
            if not backing:
                errs.append(f"{where}: no lane of '{mid}' backs {sorted(wanted)} at its quant")
        adapter_ids = {a["id"] for a in offer["model"].get("adapters", [])}
        for aid in offer.get("adapters_meta", {}):
            if aid not in adapter_ids:
                errs.append(f"{where}: adapters_meta names '{aid}', which model.adapters doesn't offer")
        for name in offer.get("params", {}).get("required", []):
            if name not in offer["params"]["properties"]:
                errs.append(f"{where}: params requires undeclared '{name}'")
    for i, helper in enumerate(m.get("helpers", [])):
        if helper["model"] not in models:
            errs.append(f"{label}: helpers[{i}] model '{helper['model']}' is not in models[]")
    keys = [s["key"] for s in m.get("settings", [])]
    if len(keys) != len(set(keys)):
        errs.append(f"{label}: a settings key repeats")
    for s in m.get("settings", []):
        sch = s["schema"]
        if "default" not in sch:
            errs.append(f"{label}: setting '{s['key']}' has no default")
        elif "enum" in sch and sch["default"] not in sch["enum"]:
            errs.append(f"{label}: setting '{s['key']}' default is not in its enum")
    if not m["offers"] and not m.get("helpers"):
        errs.append(f"{label}: offers nothing and no helpers; Gaea could never call it")
    return errs


# --------------------------------------------------------------------------------------------------- transcripts

# request type -> (replies allowed before the end, replies that end it). An empty end set means no reply.
CONVERSATION = {
    "configure": (set(), {"configured", "error"}),
    "materialize": ({"materialize.progress"}, {"materialize.done", "error"}),
    "prepare": ({"materialize.progress"}, {"prepared", "error"}),
    "run": ({"progress", "chunk"}, {"result", "error"}),
    "unload": (set(), {"unloaded", "error"}),
    "memory.query": (set(), {"memory", "error"}),
    "cancel": (set(), set()),
    "shutdown": (set(), set()),
    "storage.get": (set(), {"storage.result", "error"}),
    "storage.put": (set(), {"storage.result", "error"}),
    "storage.delete": (set(), {"storage.result", "error"}),
    "storage.query": (set(), {"storage.result", "error"}),
}
SENDER = {"H": "H→W", "W": "W→H"}


def parse_transcript(path):
    """Yields (line number, sender, message) and the manifest the header names."""
    manifest, lines = None, []
    for n, raw in enumerate(path.read_text().splitlines(), 1):
        if not raw.strip():
            continue
        if raw.startswith("#"):
            mm = re.match(r"#\s*manifest:\s*(\S+)", raw)
            if mm:
                manifest = mm.group(1)
            continue
        sender, _, body = raw.partition(" ")
        lines.append((n, sender, body))
    return manifest, lines


def check_transcript(path, manifest_path=None):
    label = path.name
    schema = load(GPP_SCHEMA)
    direction = schema["x-gaea-direction"]
    errs = []
    mname, lines = parse_transcript(path)
    manifest_file = manifest_path or (EXAMPLES / "manifest" / mname if mname else None)
    manifest = load(manifest_file) if manifest_file else None
    sent = {"H": {}, "W": {}}          # id -> request message, per sender
    ended = set()                      # (sender of request, id)
    jobs = {}                          # job -> run id
    hello = False
    shutdown = False
    for n, sender, body in lines:
        where = f"{label}:{n}"
        if sender not in SENDER:
            errs.append(f"{where}: line must start with 'H ' or 'W ', got {sender!r}")
            continue
        if len(body.encode()) > 1 << 20:
            errs.append(f"{where}: line longer than 1 MiB")
        try:
            msg = json.loads(body)
        except json.JSONDecodeError as e:
            errs.append(f"{where}: not JSON ({e})")
            continue
        found = validate(msg, schema, GPP_SCHEMA)
        if found:
            errs += [f"{where}: {e}" for e in found]
            continue
        t = msg["type"]
        d = direction[t]
        if d != "either" and d != SENDER[sender]:
            errs.append(f"{where}: {t} goes {d}, but {sender} sent it")
        if shutdown and not ends_run_on_shutdown(msg, sender, sent, ended):
            errs.append(f"{where}: {t} after shutdown")
        if not hello:
            if t != "hello":
                errs.append(f"{where}: {t} before the worker's hello")
                continue
            hello = True
            if manifest is not None:
                if msg["plugin"] != {"id": manifest["id"], "version": manifest["version"]}:
                    errs.append(f"{where}: hello names {msg['plugin']}, the manifest {manifest['id']} {manifest['version']}")
                if msg["models"] != [model["id"] for model in manifest["models"]]:
                    errs.append(f"{where}: hello models {msg['models']} differ from the manifest's")
                digest = hashlib.sha256(manifest_file.read_bytes()).hexdigest()
                if msg["manifest_sha256"] != digest:
                    errs.append(f"{where}: manifest_sha256 is not the manifest's digest {digest}")
                if "engine" in manifest and msg.get("engine") != {k: manifest["engine"][k] for k in ("version", "contract")}:
                    errs.append(f"{where}: hello engine {msg.get('engine')} differs from the manifest's")
            continue
        elif t == "hello":
            errs.append(f"{where}: a second hello")
        if "id" in msg:
            if msg["id"] in sent[sender]:
                errs.append(f"{where}: {sender} reuses request id {msg['id']}")
            sent[sender][msg["id"]] = msg
            if t == "shutdown":
                shutdown = True
            if t == "run":
                if msg["job"] in jobs:
                    errs.append(f"{where}: job {msg['job']} was already run")
                jobs[msg["job"]] = msg["id"]
            if t == "cancel" and msg["job"] not in jobs:
                errs.append(f"{where}: cancel names job {msg['job']}, which never ran")
            if manifest is not None and "model" in msg and t in ("materialize", "prepare", "run", "unload"):
                errs += check_against_manifest(msg, manifest, where)
        if "re" in msg:
            other = "W" if sender == "H" else "H"
            req = sent[other].get(msg["re"])
            if req is None:
                errs.append(f"{where}: re {msg['re']} answers nothing {other} sent")
                continue
            if t == "memory" and req["type"] != "memory.query":
                errs.append(f"{where}: memory carries re only in answer to memory.query")
                continue
            during, ends = CONVERSATION[req["type"]]
            if (other, msg["re"]) in ended:
                errs.append(f"{where}: {t} after {req['type']} {msg['re']} already ended")
            elif t in ends:
                ended.add((other, msg["re"]))
            elif t not in during:
                errs.append(f"{where}: {t} can't answer {req['type']}")
            if "job" in msg and req["type"] == "run" and msg["job"] != req["job"]:
                errs.append(f"{where}: job {msg['job']} answers run of {req['job']}")
            for key in ("model", "lane"):
                if key in msg and key in req and msg[key] != req[key]:
                    errs.append(f"{where}: {key} {msg[key]} answers a request for {req[key]}")
        elif t in ("configured", "materialize.progress", "materialize.done", "prepared", "progress", "chunk",
                   "result", "unloaded", "storage.result"):
            errs.append(f"{where}: {t} without re")
    if not hello:
        errs.append(f"{label}: the worker never said hello")
    for sender, reqs in sent.items():
        for rid, req in reqs.items():
            ends = CONVERSATION[req["type"]][1]
            if ends and (sender, rid) not in ended:
                cancelled = req["type"] == "run" and shutdown
                if not cancelled:
                    errs.append(f"{label}: {req['type']} {rid} never ended")
    return errs


def ends_run_on_shutdown(msg, sender, sent, ended):
    """After shutdown the worker may still end a run that was in flight, with error code cancelled (§3.4)."""
    req = sent["H"].get(msg.get("re"))
    return (sender == "W" and msg["type"] == "error" and msg.get("code") == "cancelled"
            and req is not None and req["type"] == "run" and ("H", msg["re"]) not in ended)


def check_against_manifest(msg, manifest, where):
    models = {m["id"]: {lane["id"] for lane in m["lanes"]} for m in manifest["models"]}
    if msg["model"] not in models:
        return [f"{where}: model {msg['model']} is not in the manifest"]
    errs = []
    if "lane" in msg and msg["lane"] not in models[msg["model"]]:
        errs.append(f"{where}: lane {msg['lane']} is not a lane of {msg['model']}")
    if msg["type"] == "run":
        ops = {(o["operation"], o["model"]["id"]) for o in manifest["offers"]}
        ops |= {(h["operation"], h["model"]) for h in manifest.get("helpers", [])}
        if (msg["operation"], msg["model"]) not in ops:
            errs.append(f"{where}: the manifest neither offers nor helps with {msg['operation']} on {msg['model']}")
    return errs


# ------------------------------------------------------------------------------------------------------- main

def main(argv):
    errs = []
    if len(argv) == 3 and argv[1] == "--manifest":
        path = pathlib.Path(argv[2])
        errs = check_manifest(json.loads(path.read_text()), path.name)
    elif len(argv) == 3 and argv[1] == "--transcript":
        errs = check_transcript(pathlib.Path(argv[2]).resolve())
    elif len(argv) == 1:
        schema_files = sorted(SCHEMAS.rglob("*.schema.json"))
        for f in schema_files:
            try:
                errs += walk_refs(load(f), f.resolve())
            except json.JSONDecodeError as e:
                errs.append(f"{f.name}: invalid JSON ({e})")
        manifests = sorted((EXAMPLES / "manifest").glob("*.json"))
        transcripts = sorted((EXAMPLES / "gpp").glob("*.gpp"))
        for f in manifests:
            errs += check_manifest(load(f), f.name)
        for f in transcripts:
            errs += check_transcript(f)
        print(f"schemas: {len(schema_files)} · manifests: {len(manifests)} · transcripts: {len(transcripts)}")
    else:
        print(__doc__)
        sys.exit(2)
    if errs:
        print("\n".join("FAIL " + e for e in errs))
        sys.exit(1)
    print("OK")


if __name__ == "__main__":
    main(sys.argv)
