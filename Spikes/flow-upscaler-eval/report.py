"""The photo-set table: FlowUpscaler and Lanczos (scored here) beside RealPLKSR, VOSR2 and Nacre (the stored G-5 scores
in mlxengine-todo/probes/creative-upscale/results), with the G-5 report's aggregation. First the calibration: the
rebuilt set's input IQA, input OCR and input-bicubic face identity against the stored values.
usage: python report.py <cu>
"""
import json, sys, statistics as st
CU = sys.argv[1]
OLD = "/Volumes/Satechi/Development/mlxengine-todo/probes/creative-upscale/results"
S = json.load(open(f"{OLD}/scores.json")); Q = json.load(open(f"{OLD}/iqa.json")); F = json.load(open(f"{OLD}/faces.json"))
S2 = json.load(open(f"{CU}/scores.json")); Q2 = json.load(open(f"{CU}/iqa.json")); F2 = json.load(open(f"{CU}/faces.json"))
names = sorted({k.split("|")[2] for k in S})
gtn = [n for n in names if not n.startswith("zt-")]
TEXT = ["sign-forge", "kiosk", "poster", "stamp", "zt-jazz"]


def m(xs):
    xs = [x for x in xs if x is not None]; return st.mean(xs) if xs else None


def f(x, d=3):
    return "—" if x is None else f"{x:.{d}f}"


print("## Calibration (rebuilt set vs stored)\n")
d_iqa = [abs(Q2[f"set/in/{n}.png"] - Q[f"set/in/{n}.png"]) for n in names if f"set/in/{n}.png" in Q and f"set/in/{n}.png" in Q2]
print(f"- input IQA: {len(d_iqa)} images, largest difference {max(d_iqa):.2e}")
d_f1 = [((S2.get(f"flow|x2|{n}") or {}).get("f1_in"), (S.get(f"plksr|x2|{n}") or {}).get("f1_in")) for n in TEXT]
print(f"- input word-F1 per text image (rebuilt, stored): {d_f1}")
d_face = [(k, round(F2[k]["id_mean"], 4), round(F[k]["id_mean"], 4)) for k in F2 if k.startswith("input-bicubic") and k in F]
print(f"- input-bicubic ArcFace (rebuilt, stored): {d_face}\n")

LABEL = {"plksr": "Precision: RealPLKSR (stored)", "vosr2": "Realistic: VOSR2 (stored)", "nacre": "Nacre v1 (stored)",
         "flow": "**FlowUpscaler** (exact FLUX.2 VAE decode)", "flow-dt": "FlowUpscaler, diffusers tiled decode (seams)", "lanczos": "Lanczos (floor)"}
for s in (2, 4):
    print(f"\n### ×{s}\n")
    print("| Arm | DISTS vs GT ↓ | LPIPS vs GT ↓ | SigLIP2 IQA ↑ (GT = {}) | ArcFace ↑ (min) | word-F1 (text set) | CORRUPTED / FIXED / INVENTED |".format(
        f(m([Q.get(f"set/gt{s}/{n}.png") for n in gtn]))))
    print("|---|---|---|---|---|---|---|")
    for a in ("plksr", "vosr2", "nacre", "flow", "flow-dt", "lanczos"):
        SS, QQ, FF = (S, Q, F) if a in ("plksr", "vosr2", "nacre") else (S2, Q2, F2)
        g = [SS.get(f"{a}|x{s}|{n}") or {} for n in gtn]
        t = [SS.get(f"{a}|x{s}|{n}") or {} for n in TEXT]
        iq = m([QQ.get(f"runs/{a}/x{s}/{n}.png") for n in names])
        fa = [v for k, v in FF.items() if k.startswith(f"{a}|x{s}|")]
        idm = m([v["id_mean"] for v in fa]); idmin = min([v["id_min"] for v in fa]) if fa else None
        cor = sum(r.get("corrupted", 0) for r in t); fix = sum(r.get("fixed", 0) for r in t); inv = sum(r.get("invented", 0) for r in t)
        print(f"| {LABEL[a]} | {f(m([r.get('dists_gt') for r in g]))} | {f(m([r.get('lpips_gt') for r in g]))} | {f(iq)} | "
              f"{f(idm)} ({f(idmin)}) | {f(m([r.get('f1') for r in t]))} | {cor} / {fix} / {inv} |")

print("\n### Per image, DISTS vs GT (×2 / ×4)\n")
print("| Image | RealPLKSR | VOSR2 | FlowUpscaler | Lanczos |\n|---|---|---|---|---|")
for n in gtn:
    cells = []
    for a, SS in (("plksr", S), ("vosr2", S), ("flow", S2), ("lanczos", S2)):
        cells.append(" / ".join(f((SS.get(f"{a}|x{s}|{n}") or {}).get("dists_gt")) for s in (2, 4)))
    print(f"| {n} | " + " | ".join(cells) + " |")
