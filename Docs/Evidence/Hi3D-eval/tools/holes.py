"""Boundary loops of each Hi3D mesh (count, edge lengths), and what trimesh's fill_holes closes."""
import sys
from pathlib import Path

import numpy as np
import trimesh

root = Path(sys.argv[1])
for item in sys.argv[2:]:
    m = trimesh.load(root / "out" / f"{item}_t2_hi3d1024" / "hi3d_refined.glb", force="mesh", process=True)
    e, counts = np.unique(m.edges_sorted, axis=0, return_counts=True)
    boundary = e[counts == 1]
    nonmanifold = int((counts > 2).sum())
    g = trimesh.graph.nx.from_edgelist(boundary.tolist())
    loops = [len(c) for c in trimesh.graph.nx.connected_components(g)]
    diag = np.linalg.norm(m.extents)
    perim = np.linalg.norm(m.vertices[boundary[:, 0]] - m.vertices[boundary[:, 1]], axis=1).sum() / diag
    filled = m.copy()
    filled.fill_holes()
    e2, c2 = np.unique(filled.edges_sorted, axis=0, return_counts=True)
    print(f"{item}: {len(loops)} loops, edges per loop max {max(loops)} median {int(np.median(loops))}, "
          f"perimeter {perim:.3f}×diag, non-manifold edges {nonmanifold} | after fill_holes: "
          f"{int((c2 == 1).sum())} boundary edges, +{len(filled.faces) - len(m.faces)} faces")
