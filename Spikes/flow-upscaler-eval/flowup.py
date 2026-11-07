"""FlowUpscaler (TensorForger, Unlicense) reference pipeline, as its ComfyUI node and training notebook define it.

Latent space: FLUX.2's VAE latents (32 channels at 1/8), normalised by the VAE's batch-norm statistics the way the
training data was stored (patchify to 128 channels at 1/16, subtract bn mean, divide by sqrt(var + eps),
unpatchify). One Euler step of a rectified flow from pure noise at t = 1000: x = noise - v(noise, 1000, small).
Trained only on 512 -> 1024 (latents 64 -> 128) from FLUX.2 klein-4B generations.
"""
import sys, time
from pathlib import Path
import numpy as np, torch
from PIL import Image
from safetensors.torch import load_file

WEIGHTS = Path("/Volumes/DEV_VOL1/Models/Models/models--TensorForger--FlowUpscaler")
KLEIN = Path("/Volumes/DEV_VOL1/Models/models--mlx-community--FLUX.2-klein-4B-bf16")
sys.path.insert(0, str(WEIGHTS))
from upscaler_unet import UpscalerUNet  # noqa: E402

DEV = torch.device("mps")
torch.set_grad_enabled(False)


def sync():
    torch.mps.synchronize()


def patchify(x):
    b, c, h, w = x.shape
    return x.view(b, c, h // 2, 2, w // 2, 2).permute(0, 1, 3, 5, 2, 4).reshape(b, c * 4, h // 2, w // 2)


def unpatchify(x):
    b, c, h, w = x.shape
    return x.reshape(b, c // 4, 2, 2, h, w).permute(0, 1, 4, 2, 5, 3).reshape(b, c // 4, h * 2, w * 2)


class Flow:
    def __init__(self, dtype=torch.float32):
        from diffusers import AutoencoderKLFlux2
        self.dtype = dtype
        self.vae = AutoencoderKLFlux2.from_pretrained(KLEIN / "vae", torch_dtype=torch.float32).to(DEV).eval()
        self.bn_mean = self.vae.bn.running_mean.view(1, -1, 1, 1).to(DEV)
        self.bn_std = torch.sqrt(self.vae.bn.running_var.view(1, -1, 1, 1) + self.vae.config.batch_norm_eps).to(DEV)
        self.unet = UpscalerUNet()
        self.unet.load_state_dict(load_file(WEIGHTS / "flow_upscaler.safetensors"))
        self.unet = self.unet.to(DEV, dtype).eval()

    def norm(self, raw):
        return unpatchify((patchify(raw) - self.bn_mean) / self.bn_std)

    def denorm(self, z):
        return unpatchify(patchify(z) * self.bn_std + self.bn_mean)

    def encode(self, img: Image.Image):
        x = torch.from_numpy(np.asarray(img.convert("RGB"), dtype=np.float32) / 255).permute(2, 0, 1)[None].to(DEV)
        raw = self.vae.encode(x * 2 - 1).latent_dist.mode()
        return self.norm(raw)

    def decode(self, z, tiled=False):
        if tiled:
            self.vae.enable_tiling()
        else:
            self.vae.disable_tiling()
        x = self.vae.decode(self.denorm(z).float(), return_dict=False)[0]
        a = ((x[0].clamp(-1, 1) + 1) / 2).permute(1, 2, 0).float().cpu().numpy()
        return Image.fromarray((a * 255 + 0.5).astype(np.uint8))

    def up2(self, z_small, seed=0):
        """One 2x pass: the node's single FlowMatchEuler step (sigma 1 -> 0)."""
        b, c, h, w = z_small.shape
        g = torch.Generator(device="cpu").manual_seed(seed)
        noise = torch.randn((b, 32, h * 2, w * 2), generator=g).to(DEV, self.dtype)
        t = torch.full((1,), 1000.0, device=DEV, dtype=self.dtype)
        v = self.unet(sample=noise, timestep=t, latents_small=z_small.to(self.dtype))
        return (noise - v).float()
