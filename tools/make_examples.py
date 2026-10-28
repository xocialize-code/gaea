#!/usr/bin/env python3
"""Regenerates the example manifests in examples/v1/manifest from the engine's own encoding.

  tools/make_examples.py      (builds tools/manifest-gen first if needed)

models[] comes from tools/manifest-gen, which encodes MLXToolKit's PackageManifest and ResolvedLane
with mlx-engine-swift itself; everything else is Gaea's and is written here. The transcripts in
examples/v1/gpp are hand-written and not touched.
"""
import hashlib
import json
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
GEN = ROOT / "tools" / "manifest-gen"
OUT = ROOT / "examples" / "v1" / "manifest"
ENGINE = {"package": "mlx-engine-swift", "version": "0.72.0", "contract": "1.57.0"}
APACHE = {"spdx": "Apache-2.0", "commercial_use": True, "terms_url": "https://www.apache.org/licenses/LICENSE-2.0"}


def models(model_set):
    binary = GEN / ".build" / "release" / "gaea-manifest-gen"
    if not binary.exists():
        subprocess.run(["xcrun", "swift", "build", "-c", "release"], cwd=GEN, check=True)
    return json.loads(subprocess.run([binary, model_set], check=True, capture_output=True).stdout)


def demo():
    # The plugin-exec spike's demo worker, upgraded from its v0 manifest
    # ({"id","version","protocol","operations":["demo.matmul"],"footprint":{"residentBytes":…},"license"}).
    return {
        "manifest_version": 1,
        "id": "com.xocialize.gaea.demo",
        "version": "0.2.0",
        "protocol": 1,
        "min_gaea": "0.1.0",
        "team": "CFZS6RXUCP",
        "repo": "https://github.com/xocialize/gaea-plugin-demo",
        "title": "Gaea demo worker",
        "summary": "A GPU matmul loop that proves the plugin path end to end: download, verify, launch, run, cancel.",
        "license": "Apache-2.0",
        "executable": "gaea-demo-worker",
        "models": models("demo"),
        "offers": [],
        "helpers": [{
            "operation": "x-gaea.demo.matmul",
            "model": "demo-matmul",
            "title": "Matmul smoke test",
            "summary": "n×n fp32 matmul, repeated; holds holdBytes to exercise the memory ledger.",
            "params": {
                "type": "object",
                "properties": {
                    "n": {"type": "integer", "minimum": 16, "maximum": 16384, "default": 4096},
                    "iterations": {"type": "integer", "minimum": 1, "maximum": 1000, "default": 10},
                    "holdBytes": {"type": "integer", "minimum": 0, "default": 0},
                },
                "additionalProperties": False,
            },
        }],
        "settings": [],
    }


def z_image_turbo():
    return {
        "manifest_version": 1,
        "id": "com.xocialize.gaea.z-image",
        "version": "0.1.0",
        "protocol": 1,
        "min_gaea": "0.1.0",
        "team": "CFZS6RXUCP",
        "repo": "https://github.com/xocialize/gaea-plugin-z-image",
        "title": "Z-Image",
        "summary": "Tongyi-MAI's Z-Image Turbo: fast photoreal text-to-image and image-to-image.",
        "license": "MIT",
        "executable": "gaea-z-image-worker",
        "engine": ENGINE,
        "models": models("z-image-turbo"),
        "offers": [
            {
                "operation": "image.generate",
                "profile": "image",
                "model": {
                    "id": "z-image-turbo",
                    "title": "Z-Image Turbo",
                    "license": APACHE,
                    "memory_class": "large",
                    "speed_class": "fast",
                    "quality_tiers": ["draft", "standard"],
                    "default": True,
                    "notes": "Distilled 8-step, no CFG: negative prompts do nothing. Low seed variance is a model trait.",
                },
                "defaults": {"steps": 8},
                "limits": {"max_pixels": 2359296, "min_side": 256, "max_side": 1536, "size_multiple": 16},
                "params": {
                    "type": "object",
                    "properties": {
                        "x-zimage.shift": {"type": "number", "minimum": 1, "maximum": 6, "default": 3,
                                           "description": "Flow-matching shift; higher favours composition over detail.",
                                           "x-mes-ui": {"widget": "slider", "label": "Shift", "advanced": True}},
                    },
                    "additionalProperties": False,
                },
            },
            {
                "operation": "image.edit",
                "profile": "image",
                "model": {
                    "id": "z-image-turbo",
                    "title": "Z-Image Turbo (image to image)",
                    "license": APACHE,
                    "memory_class": "large",
                    "speed_class": "fast",
                    "quality_tiers": ["draft"],
                    "named_only": True,
                    "notes": "Re-generates from the input image; strength 0–1 (default 0.75). Not an instruction editor.",
                },
                "limits": {"max_pixels": 2359296, "size_multiple": 16, "max_images": 1},
            },
        ],
        "helpers": [],
        "settings": [{
            "key": "default_lane",
            "title": "Default precision",
            "description": "Which lane Gaea loads when memory allows more than one.",
            "schema": {"type": "string", "enum": ["int4", "int8", "bf16"], "default": "int4"},
            "apply": "reload_models",
        }],
        "storage": {"schema_version": 1, "migrations": ["0001_presets"]},
    }


def refresh_digests():
    """A transcript's hello carries its manifest's sha256; keep it current after a rebuild."""
    for path in sorted((ROOT / "examples" / "v1").glob("*/*.gpp")):
        if path.name == "wrong-digest.gpp":  # breaks the digest on purpose
            continue
        text = path.read_text()
        named = re.search(r"^#\s*manifest:\s*(\S+)", text, re.M)
        if not named:
            continue
        digest = hashlib.sha256((OUT / named.group(1)).read_bytes()).hexdigest()
        fresh = re.sub(r'("type":"hello".*?"manifest_sha256":")[0-9a-f]{64}"', rf'\g<1>{digest}"', text)
        if fresh != text:
            path.write_text(fresh)
            print("refreshed", path.relative_to(ROOT))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, build in [("demo.json", demo), ("z-image.json", z_image_turbo)]:
        (OUT / name).write_text(json.dumps(build(), indent=2, ensure_ascii=False) + "\n")
        print("wrote", OUT / name)
    refresh_digests()


if __name__ == "__main__":
    main()
