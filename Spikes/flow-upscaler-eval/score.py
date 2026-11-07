"""G-5 creative-upscale scorer.
runs/<arm>/x<s>/<name>.png ; set/{in,gt2,gt4}/<name>.png ; reference precision arm = 'plksr'.
Per output: LPIPS-Alex + DISTS vs the precision result (structure fidelity) and vs GT (when it exists), on a fixed
3x2 grid of 512² crops; Vision OCR word-F1 vs pseudo-truth (OCR of GT; Z-Image renders: OCR of the input) and N7
accounting per token: CORRUPTED = truth tokens the input read that the output no longer reads, FIXED = the reverse,
INVENTED = output tokens not in the truth. usage: python score.py <S/cu> <vosrgate> <out.json> [arm ...]"""
import json, os, re, subprocess, sys
from collections import Counter
import numpy as np, torch, lpips, piq
from PIL import Image
Image.MAX_IMAGE_PIXELS = None
torch.set_grad_enabled(False); torch.set_num_threads(8)
CU, VG, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
arms = sys.argv[4:] or sorted(os.listdir(f'{CU}/runs'))
L = lpips.LPIPS(net='alex', verbose=False); D = piq.DISTS(reduction='none')

def load(p): return np.asarray(Image.open(p).convert('RGB'), dtype=np.float32) / 255
def crops(a, b, n=(3, 2), s=512):
    H, W = a.shape[:2]; s = min(s, H, W); out = []
    for j in range(n[1]):
        for i in range(n[0]):
            x = int(i * (W - s) / max(n[0] - 1, 1)); y = int(j * (H - s) / max(n[1] - 1, 1))
            out.append((a[y:y+s, x:x+s], b[y:y+s, x:x+s]))
    return out
def pair(a, b):
    if a.shape != b.shape: return None
    lp, ds = [], []
    for ca, cb in crops(a, b):
        ta = torch.from_numpy(ca).permute(2, 0, 1)[None]; tb = torch.from_numpy(cb).permute(2, 0, 1)[None]
        lp.append(L(ta * 2 - 1, tb * 2 - 1).item()); ds.append(D(ta, tb).item())
    return float(np.mean(lp)), float(np.mean(ds))
def toks(items):
    out = []
    for it in items:
        for w in re.split(r"\s+", it.get("text", "")):
            w = re.sub(r"[^A-Z0-9]", "", w.upper())
            if len(w) >= 2: out.append(w)
    return out
def f1(gt, rec):
    g, r = Counter(gt), Counter(rec); m = sum((g & r).values())
    if not gt: return None
    p = m / len(rec) if rec else 0.0; rc = m / len(gt)
    return 2 * p * rc / (p + rc) if p + rc else 0.0
def n7(truth, inp, out):
    t, i, o = Counter(truth), Counter(inp), Counter(out)
    cor = fix = 0
    for w, n in t.items():
        ni, no = min(n, i[w]), min(n, o[w]); cor += max(0, ni - no); fix += max(0, no - ni)
    inv = sum((o - t).values())
    return cor, fix, inv
def ocr(d):
    p = os.path.join(d, 'ocr.json')
    if not os.path.exists(p): subprocess.run([VG, 'ocr', d, p], check=True, capture_output=True)
    return json.load(open(p))

names = sorted(f[:-4] for f in os.listdir(f'{CU}/set/in') if f.endswith('.png'))
in_ocr = ocr(f'{CU}/set/in'); gt_ocr = {s: ocr(f'{CU}/set/gt{s}') for s in (2, 4)}
res = json.load(open(OUT)) if os.path.exists(OUT) else {}
for arm in arms:
    for s in (2, 4):
        d = f'{CU}/runs/{arm}/x{s}'
        if not os.path.isdir(d): continue
        o = ocr(d)
        for n in names:
            p = f'{d}/{n}.png'
            if not os.path.exists(p): continue
            key = f'{arm}|x{s}|{n}'
            if key in res and res[key].get('mtime') == os.path.getmtime(p): continue
            a = load(p); r = {'mtime': os.path.getmtime(p), 'size': list(a.shape[1::-1])}
            pr = f'{CU}/runs/plksr/x{s}/{n}.png'
            if arm != 'plksr' and os.path.exists(pr):
                v = pair(a, load(pr)); r['lpips_p'], r['dists_p'] = v if v else (None, None)
            g = f'{CU}/set/gt{s}/{n}.png'
            if os.path.exists(g):
                v = pair(a, load(g)); r['lpips_gt'], r['dists_gt'] = v if v else (None, None)
                truth = toks(gt_ocr[s].get(f'{n}.png', []))
            else:
                truth = toks(in_ocr.get(f'{n}.png', []))
            inp = toks(in_ocr.get(f'{n}.png', [])); outw = toks(o.get(f'{n}.png', []))
            r['truth_words'] = len(truth); r['f1'] = f1(truth, outw); r['f1_in'] = f1(truth, inp)
            r['corrupted'], r['fixed'], r['invented'] = n7(truth, inp, outw)
            res[key] = r
            print(key, {k: (round(v, 4) if isinstance(v, float) else v) for k, v in r.items() if k != 'mtime'}, flush=True)
        json.dump(res, open(OUT, 'w'), indent=0)
