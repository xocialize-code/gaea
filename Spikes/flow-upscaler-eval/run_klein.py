"""Klein outputs through FlowUpscaler, and the multi-pass 8K claim.

For each prompt, FLUX.2 klein-4B (diffusers, bf16, MPS, 4 steps, guidance 1) draws 1024² and hands back its latents
(output_type="latent"; normalised here as the upscaler was trained). Saved, packed and bn-normalised, for VAEDecode
(flux2-vae-mlx-swift's exact row-band decode, the product's decoder):
  lat/<name>-base       the 1024² latents
  lat/<name>-native-2k  Klein drawing 2048² itself, same prompt and seed
  lat/<name>-flow-2k / -4k / -8k   1, 2 and 3 chained 2x passes (seeds 0, 1, 2)
TAEF2 (the tiny decoder the author recommends at 2048² and above) decodes each pass here: <name>-taef-<k>.png.
timings.json: generation, each pass and each TAEF2 decode (seconds), MPS peak.
usage: python run_klein.py <out>
"""
import json, os, sys, time
import numpy as np, torch
from PIL import Image
from safetensors.torch import load_file, save_file
from flowup import Flow, KLEIN, DEV, sync, patchify

sys.path.insert(0, "/Volumes/DEV_VOL1/Models/Models/models--madebyollin--taef2")
from taesd import TAESD  # noqa: E402

OUT = sys.argv[1]
os.makedirs(f"{OUT}/lat", exist_ok=True)
PROMPTS = [
    ("portrait", "A close-up photograph of an elderly fisherman with a weathered face and a grey beard, wearing a wool cap, soft morning light, harbour behind him", 11),
    ("forest", "A misty pine forest at dawn, sunbeams through the trees, moss and ferns on the ground, a narrow dirt path", 22),
    ("sign", "A vintage enamel shop sign on a brick wall that reads 'BAKERY - FRESH BREAD DAILY', photographed straight on", 33),
    ("cat", "A tabby cat sitting on a windowsill, detailed fur and whiskers, green eyes, a city street out of focus behind", 44),
    ("city", "An aerial photograph of a dense old European city with red tile roofs, a cathedral and narrow streets, midday", 55),
    ("illustration", "A detailed ink and watercolour illustration of a lighthouse on a rocky island with seabirds, storybook style", 66),
]


def taef2():
    def convert(sd):
        out = {}
        for k, v in sd.items():
            encdec, _layers, index, *suffix = k.split(".")
            out[".".join([encdec, str(int(index) + (1 if encdec == "decoder" else 0)), *suffix])] = v
        return out
    t = TAESD(encoder_path=None, decoder_path=None, latent_channels=32, arch_variant="flux_2")
    t.load_state_dict(convert(load_file("/Volumes/DEV_VOL1/Models/Models/models--madebyollin--taef2/taef2.safetensors")))
    return t.to(DEV, torch.float32).eval()


def tae_decode(z, band=128, halo=16):
    """TAEF2 in latent row bands with a halo (MPS can't convolve an 8K image in one go). It is almost all convs; its
    mid-block GroupNorm sees one band at a time, so banded output can differ slightly from whole-image output."""
    h = z.shape[2]
    if h <= 256:
        return tae.decoder(z)
    rows = []
    for y in range(0, h, band):
        a, b = max(0, y - halo), min(h, y + band + halo)
        x = tae.decoder(z[:, :, a:b])
        rows.append(x[:, :, (y - a) * 8:(y - a + min(band, h - y)) * 8].cpu())
        sync()
    return torch.cat(rows, dim=2)


def timed(fn):
    sync(); t = time.time(); r = fn(); sync(); return r, round(time.time() - t, 3)


def save(z, name):
    save_file({"latents": patchify(z).contiguous().cpu()}, f"{OUT}/lat/{name}.safetensors")


from diffusers import Flux2KleinPipeline  # noqa: E402
pipe = Flux2KleinPipeline.from_pretrained(KLEIN, torch_dtype=torch.bfloat16).to(DEV)
flow = Flow()
tae = taef2()
timings = {}
for name, prompt, seed in PROMPTS:
    rec = {}
    gen = lambda size: pipe(prompt=prompt, height=size, width=size, guidance_scale=1.0, num_inference_steps=4,
                            generator=torch.Generator("cpu").manual_seed(seed), output_type="latent").images
    raw, rec["generate_1024_s"] = timed(lambda: gen(1024))
    z = flow.norm(raw.float()); save(z, f"{name}-base")
    raw2k, rec["generate_2048_s"] = timed(lambda: gen(2048))
    save(flow.norm(raw2k.float()), f"{name}-native-2k")
    del raw, raw2k
    torch.mps.empty_cache()
    for k, label in ((1, "2k"), (2, "4k"), (3, "8k")):
        z, rec[f"pass_{label}_s"] = timed(lambda: flow.up2(z, seed=k - 1))
        save(z, f"{name}-flow-{label}")
        torch.mps.reset_peak_memory_stats() if hasattr(torch.mps, "reset_peak_memory_stats") else None
        x, rec[f"taef2_{label}_s"] = timed(lambda: tae_decode(z))
        rec[f"mps_alloc_after_taef2_{label}_gb"] = round(torch.mps.driver_allocated_memory() / 1e9, 2)
        a = x[0].clamp(0, 1).permute(1, 2, 0).float().cpu().numpy()
        Image.fromarray((a * 255 + 0.5).astype(np.uint8)).save(f"{OUT}/{name}-taef-{label}.png")
        del x, a
        torch.mps.empty_cache()
    timings[name] = rec
    print(name, json.dumps(rec), flush=True)
    json.dump(timings, open(f"{OUT}/timings.json", "w"), indent=1)
