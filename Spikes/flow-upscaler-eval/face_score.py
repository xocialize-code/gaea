"""ArcFace identity per face, as the G-5 kit's face_score.py measured it (its facelib.py is gone; this rebuilds the
two calls it used on insightface's model_zoo with the same local buffalo_l files: SCRFD det_10g and ArcFace
w600k_r50, measurement only, non-commercial, never shipped).
Reference = GT at the scale (Commons) or the input bicubic-upscaled (Z-Image renders). Every output is embedded at
the REFERENCE's landmarks; faces with < 8 px between the eyes are dropped. 'input-bicubic' rows are the calibration
against the stored faces.json.
usage: python face_score.py <cu> <out.json> [arm ...]
"""
import json, os, sys
import cv2, numpy as np
from insightface.model_zoo import get_model
from insightface.utils.face_align import norm_crop

M = "/Volumes/Satechi/Models/_measure/insightface_buffalo_l"
CU, OUT = sys.argv[1], sys.argv[2]
arms = sys.argv[3:]
det = get_model(f"{M}/det_10g.onnx", providers=["CPUExecutionProvider"]); det.prepare(ctx_id=-1, input_size=(640, 640))
rec = get_model(f"{M}/w600k_r50.onnx", providers=["CPUExecutionProvider"]); rec.prepare(ctx_id=-1)


def embed(img, kps):
    e = rec.get_feat(norm_crop(img, kps, image_size=112)).ravel()
    return e / np.linalg.norm(e)


res = {}
NAMES = ["face-man", "face-woman", "group", "poster", "zt-reader", "zt-jazz", "zt-cats"]
for s in (2, 4):
    for n in NAMES:
        gt = f"{CU}/set/gt{s}/{n}.png"
        if os.path.exists(gt):
            ref = cv2.imread(gt); kind = "gt"
        else:
            i = cv2.imread(f"{CU}/set/in/{n}.png")
            ref = cv2.resize(i, (i.shape[1] * s, i.shape[0] * s), interpolation=cv2.INTER_CUBIC); kind = "input"
        boxes, kps = det.detect(ref, max_num=0)
        faces = [k for k in (kps if kps is not None else []) if np.linalg.norm(k[1] - k[0]) >= 8]
        if not faces:
            continue
        e_ref = [embed(ref, k) for k in faces]
        for arm in ["input-bicubic"] + arms:
            if arm == "input-bicubic":
                i = cv2.imread(f"{CU}/set/in/{n}.png")
                out = cv2.resize(i, (ref.shape[1], ref.shape[0]), interpolation=cv2.INTER_CUBIC)
            else:
                p = f"{CU}/runs/{arm}/x{s}/{n}.png"
                if not os.path.exists(p):
                    continue
                out = cv2.imread(p)
                if out.shape != ref.shape:
                    out = cv2.resize(out, (ref.shape[1], ref.shape[0]), interpolation=cv2.INTER_LANCZOS4)
            ids = [float(embed(out, k) @ e) for k, e in zip(faces, e_ref)]
            res[f"{arm}|x{s}|{n}"] = {"ref": kind, "faces": len(faces), "id_mean": float(np.mean(ids)),
                                      "id_min": float(np.min(ids)), "eye_px": [float(np.linalg.norm(k[1] - k[0])) for k in faces]}
json.dump(res, open(OUT, "w"), indent=0)
print(len(res), "rows")
