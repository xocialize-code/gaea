"""1024³ (Space) vs 1536³ (HF Jobs): faces, components, shards, boundary edges, and each run's timing and memory."""
import json
import sys
from pathlib import Path

import numpy as np
import trimesh

root = Path(sys.argv[1])


def stats(path):
    m = trimesh.load(path, force="mesh", process=True)
    comps = trimesh.graph.connected_components(m.face_adjacency, nodes=np.arange(len(m.faces)), engine="scipy")
    areas = m.area_faces
    shards = sum(1 for c in comps if areas[c].sum() < m.area * 1e-4)
    _, counts = np.unique(m.edges_sorted, axis=0, return_counts=True)
    return f"{len(m.faces):>9,} faces {len(comps):>5} comps {shards:>5} shards {int((counts == 1).sum()):>4} open edges"


for item in sys.argv[2:]:
    space = root / "out" / f"{item}_t2_hi3d1024"
    s_info = json.loads((space / "info.json").read_text())
    print(f"{item}\n  1024 Space {stats(space / 'hi3d_refined.glb')} | {s_info['timings']['gpu_total_s']:.0f} s, "
          f"{s_info['peak_gpu_memory_gb']} GB")
    for res in (1024, 1536):
        run = root / "run31" / f"run_{item}_{res}"
        if not run.exists():
            continue
        info = json.loads((run / "info.json").read_text())
        vox = "/".join(str(p["voxels"]) for p in info["passes"])
        print(f"  {res} Jobs  {stats(run / 'hi3d_refined.glb')} | {info['refine_s']:.0f} s, "
              f"{info['peak_gpu_memory_gb']} GB, voxels {vox}, warnings {len(info['warnings'])}")
