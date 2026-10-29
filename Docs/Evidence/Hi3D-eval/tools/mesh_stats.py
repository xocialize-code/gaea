"""Per-item mesh stats: faces, components (and tiny shards), boundary edges, Hi3D's run info."""
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
    edges = m.edges_sorted
    _, counts = np.unique(edges, axis=0, return_counts=True)
    return {
        "faces": len(m.faces),
        "components": len(comps),
        "shards<0.01%area": shards,
        "boundary_edges": int((counts == 1).sum()),
        "watertight": bool(m.is_watertight),
    }


for item in sys.argv[2:]:
    t2 = stats(root / "coarse" / f"{item}_trellis2.ply")
    out = root / "out" / f"{item}_t2_hi3d1024"
    if not (out / "hi3d_refined.glb").exists():
        print(item, "TRELLIS.2", t2, "Hi3D missing")
        continue
    h = stats(out / "hi3d_refined.glb")
    info = json.loads((out / "info.json").read_text())
    print(f"{item}\n  TRELLIS.2 {t2}\n  Hi3D      {h}\n  run gpu {info['timings']['gpu_total_s']}s "
          f"peak {info['peak_gpu_memory_gb']} GB warn {len(info['warnings'])}")
