#!/usr/bin/env python3
"""Negative tests: every invalid fixture and every mutation of a valid manifest must be rejected, with the error
the case names, or the schemas and rules are weaker than spec/GPP-1.md says.

  tools/test_validator.py
"""
import copy
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import validate as v  # noqa: E402

INVALID = v.EXAMPLES / "invalid"


def setp(path, value):
    def f(doc):
        node = doc
        for k in path[:-1]:
            node = node[k]
        node[path[-1]] = value
    return f


def delp(path):
    def f(doc):
        node = doc
        for k in path[:-1]:
            node = node[k]
        del node[path[-1]]
    return f


def both(*fs):
    def f(doc):
        for g in fs:
            g(doc)
    return f


Z = "z-image.json"
D = "demo.json"
LANE0 = ["models", 0, "lanes", 0]
RES0 = LANE0 + ["resolved"]
OFFER0 = ["offers", 0]
SRC = {"repo": "xocialize/qwen-image-flash-loras", "revision": "a60485ca35e32b69c2d71930c2ef3d3745271411",
       "file": "loras/martha.safetensors", "sha256": "0" * 64}
ADAPTER = {"id": "martha", "title": "Martha", "kind": "plain", "strength": {"min": 0, "max": 2, "default": 1},
           "license": {"spdx": "Apache-2.0", "commercial_use": True}}
SUPPORT = {"base_model": "qwen-image", "formats": ["diffusers-peft"], "kinds": ["plain"], "max_count": 4,
           "strength": {"min": 0, "max": 2}}

# (manifest, mutation, the error text it must produce, why)
MANIFEST_CASES = [
    (Z, setp(["manifest_version"], 2), "expected 1", "unknown manifest version"),
    (Z, setp(["id"], "Z-Image"), "doesn't match", "plugin id not reverse-DNS"),
    (Z, setp(["version"], "1.0"), "doesn't match", "version not semver"),
    (Z, setp(["team"], "cfzs6rxucp"), "doesn't match", "team id not 10 upper-case characters"),
    (Z, setp(["repo"], "https://gitlab.com/x/y"), "doesn't match", "repo not on GitHub (G-18)"),
    (Z, setp(["executable"], "../bin/worker"), "doesn't match", "executable escapes Contents/MacOS"),
    (Z, setp(["protocol"], 2), "expected 1", "protocol this schema doesn't describe"),
    (Z, delp(["models"]), "missing required 'models'", "no models"),
    (Z, setp(["models"], []), "fewer than 1 items", "empty models"),
    (Z, setp(["secrets"], {"token": "x"}), "unexpected property 'secrets'", "unknown top-level key"),
    (Z, setp(LANE0 + ["default"], False), "exactly one default lane, has 0", "no default lane"),
    (Z, setp(["models", 0, "lanes", 1, "default"], True), "exactly one default lane, has 2", "two default lanes"),
    (Z, setp(["models", 0, "lanes", 1, "id"], "int4"), "repeats a lane id", "duplicate lane"),
    (Z, setp(LANE0 + ["id"], "fast"), "name the lane after it", "lane named unlike its quant"),
    (Z, setp(RES0 + ["persistentSource"], "guess"), "not in", "unknown footprint source"),
    (Z, setp(RES0 + ["persistentBytes"], -1), "below 0", "negative bytes"),
    (Z, setp(RES0 + ["weightSources"], []), "fewer than 1 items", "engine materialization with no sources"),
    (Z, setp(RES0 + ["materialization"], "package"), "expected True", "package materialization not selfMaterializing"),
    (Z, setp(RES0 + ["weightSources", 0, "repo"], "Z-Image-Turbo"), "doesn't match", "weight repo not owner/name"),
    (Z, setp(RES0 + ["contractVersion", "minor"], 56), "was resolved under contract 1.56.0", "lane from another engine contract"),
    (Z, setp(RES0 + ["peakBytes"], 1), "unexpected property 'peakBytes'", "computed field written into the lane"),
    (Z, delp(["models", 0, "package", "requirements"]), "missing required 'requirements'", "package without requirements"),
    (Z, setp(OFFER0 + ["operation"], "image.Generate"), "doesn't match", "operation id not profile.verb"),
    (Z, setp(OFFER0 + ["profile"], "audio"), "is not in profile audio", "operation outside its profile"),
    (Z, setp(OFFER0 + ["model", "id"], "flux-2-klein"), "is not in models[]", "offer of a model the plugin lacks"),
    (Z, setp(OFFER0 + ["lanes"], ["int2"]), "is not a lane of", "offer of a lane the model lacks"),
    (Z, both(setp(RES0 + ["capabilities"], ["textToImage"]), setp(["offers", 1, "lanes"], ["int4"])),
     "no lane of 'z-image-turbo' backs", "edit offered only on a lane whose quant is below the edit surface's floor"),
    (Z, setp(["offers", 1, "operation"], "image.generate"), "a second offer", "same operation and model twice"),
    (Z, delp(OFFER0 + ["model", "license"]), "missing required 'license'", "MES offer without a licence"),
    (Z, setp(OFFER0 + ["model", "quality_tiers"], ["ultra"]), "not in", "quality tier MES doesn't define"),
    (Z, setp(OFFER0 + ["model", "remote_provider"], {"id": "x", "name": "X", "billed": True}), None,
     "remote provider — MES allows it, so this case documents that G-12 is policy, not schema"),
    (Z, setp(OFFER0 + ["params", "properties", "shift"], {"type": "number"}), "doesn't match", "model param not an x- extension (G-3)"),
    (Z, setp(OFFER0 + ["params", "properties", "x-zimage.shift", "x-mes-ui"], {"control": "slider"}),
     "unexpected property 'control'", "UI hint MESFormsUI doesn't know"),
    (Z, setp(OFFER0 + ["params", "required"], ["x-zimage.seed"]), "requires undeclared", "required param not declared"),
    (Z, setp(OFFER0 + ["limits", "max_pixels"], 0), "below 1", "zero pixel limit"),
    (Z, setp(OFFER0 + ["limits", "max_megapixels"], 4), "unexpected property 'max_megapixels'", "unknown limit"),
    (Z, setp(OFFER0 + ["adapters_meta"], {"tryon": {"status": "verified", "format": "diffusers-peft", "source": SRC}}),
     "which model.adapters doesn't offer", "metadata for an adapter the offer doesn't list"),
    (Z, setp(OFFER0 + ["adapters_meta"], {"tryon": {"clearance": {"z-image-turbo": "vibes"}, "format": "kohya", "source": SRC}}),
     "not in", "unknown clearance level"),
    (Z, setp(OFFER0 + ["adapters_meta"], {"tryon": {"format": "kohya"}}), "missing required 'source'", "adapter without a source"),
    (Z, setp(OFFER0 + ["adapters_meta"], {"tryon": {"format": "kohya", "source": dict(SRC, revision="main")}}),
     "doesn't match", "adapter revision not pinned to a commit"),
    (Z, setp(OFFER0 + ["model", "adapters"], [ADAPTER]), "has no adapters_meta", "listed adapter with no metadata"),
    (Z, setp(OFFER0 + ["model", "adapters"], [ADAPTER]), "declares no adapter_support", "listed adapter, no adapter_support"),
    (Z, setp(OFFER0 + ["adapter_support"], dict(SUPPORT, max_count=0)), "below 1", "adapter_support that takes none"),
    (Z, setp(["settings", 0, "apply"], "maybe"), "not in", "unknown setting apply mode"),
    (Z, delp(["settings", 0, "schema", "default"]), "has no default", "setting without a default"),
    (Z, setp(["settings", 0, "schema", "default"], "fp8"), "default is not in its enum", "setting default outside enum"),
    (Z, setp(["settings", 0, "key"], "Default-Lane"), "doesn't match", "setting key not snake_case"),
    (Z, setp(["storage", "schema_version"], 0), "below 1", "storage schema version 0"),
    (Z, setp(["engine", "package"], "mlx-swift"), "expected 'mlx-engine-swift'", "engine block naming another package"),
    (D, setp(["helpers", 0, "operation"], "demo.matmul"), "doesn't match", "helper operation without the x- prefix"),
    (D, setp(["helpers", 0, "model"], "other"), "is not in models[]", "helper for an unknown model"),
    (D, setp(["helpers"], []), "offers nothing and no helpers", "a plugin Gaea could never call"),
    (D, both(setp(["offers"], []), delp(["helpers"])), "offers nothing and no helpers", "no offers, helpers omitted"),
]


def main():
    results = []
    for f in sorted(INVALID.glob("*.gpp")):
        expect = next((line.split(":", 1)[1].strip() for line in f.read_text().splitlines()
                       if line.startswith("# expect:")), None)
        errs = v.check_transcript(f)
        ok = bool(errs) and expect is not None and any(expect in e for e in errs)
        results.append((f"invalid/{f.name}", ok, errs[:1] if not ok else [], expect))
    for name in ["demo.json", "z-image.json"]:
        errs = v.check_manifest(v.load(v.EXAMPLES / "manifest" / name), name)
        results.append((f"{name} starts valid", not errs, errs[:1], None))
    for name, mutate, expect, why in MANIFEST_CASES:
        doc = copy.deepcopy(v.load(v.EXAMPLES / "manifest" / name))
        mutate(doc)
        errs = v.check_manifest(doc, name)
        if expect is None:  # documents something the schema deliberately accepts
            results.append((why, not errs, errs[:1], "accepted"))
        else:
            results.append((why, any(expect in e for e in errs), errs[:2], expect))
    failed = [r for r in results if not r[1]]
    for why, ok, errs, expect in results:
        print(("ok    " if ok else "FAIL  ") + why + ("" if ok else f"  (wanted {expect!r}; got {errs})"))
    print(f"{len(results) - len(failed)}/{len(results)} cases behave")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
