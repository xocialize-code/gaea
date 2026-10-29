"""Find the axis rotation that best maps a TRELLIS.2 mesh onto a reference mesh (chamfer, normalized)."""
import itertools
import sys

import numpy as np
import trimesh
from scipy.spatial import cKDTree


def normalized_points(mesh, n=20000):
    pts = mesh.sample(n, seed=0) if hasattr(mesh, "sample") else mesh
    lo, hi = pts.min(0), pts.max(0)
    return (pts - (lo + hi) / 2) / np.linalg.norm(hi - lo)


def rotations():
    # The 24 proper axis-aligned rotations.
    for perm in itertools.permutations(range(3)):
        for signs in itertools.product((1, -1), repeat=3):
            r = np.zeros((3, 3))
            for i, (p, s) in enumerate(zip(perm, signs)):
                r[i, p] = s
            if np.isclose(np.linalg.det(r), 1):
                yield r


def chamfer(a, b):
    return cKDTree(b).query(a)[0].mean() + cKDTree(a).query(b)[0].mean()


def main():
    src = trimesh.load(sys.argv[1], force="mesh", process=False)
    ref = trimesh.load(sys.argv[2], force="mesh", process=False)
    print("src extents", src.extents.round(3), "ref extents", ref.extents.round(3))
    p_src = src.sample(20000, seed=0)
    p_ref = normalized_points(ref)
    scores = sorted(
        (chamfer(normalized_points(p_src @ r.T), p_ref), r.astype(int).tolist()) for r in rotations()
    )
    for s, r in scores[:5]:
        print(f"{s:.4f}", r)


if __name__ == "__main__":
    main()
