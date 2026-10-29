# Tier bench — Pixel Agency Image Engine

Run 2026-10-29T03:29:36Z, engine http://127.0.0.1:17611/mes/v0.

### edits

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) |  | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|
| image.edit | klein-4b | best | 2 | 12347 | 12378 |  | 0.0 | 0 |
| image.edit | klein-4b | draft | 2 | 12363 | 13829 |  | 0.0 | 0 |
| image.erase | lama-inpaint | standard | 2 | 428 | 523 |  | 0.0 | 0 |
| image.erase | mage-flow-edit-turbo | best | 2 | 8024 | 9592 |  | 0.0 | 0 |
| image.extend | lama-inpaint | best | 2 | 595 | 601 |  | 0.0 | 0 |
| image.extend | lama-inpaint | draft | 2 | 248 | 247 |  | 0.0 | 0 |
| image.extend | lama-inpaint | standard | 2 | 597 | 638 |  | 0.0 | 0 |
| image.fill | klein-4b | best | 2 | 12377 | 12383 |  | 0.0 | 0 |
| image.fill | klein-4b | standard | 2 | 12418 | 12383 |  | 0.0 | 0 |

### erase-eff

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | fallback | left | psnr_box | psnr_eff | psnr_hole | ring | ssim_box | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| image.erase | lama-inpaint | draft | 43 | 162 | — | 0.0000 | 0.0000 | 21.1678 | 18.3208 | 18.3208 | 19.2094 | 0.8271 | 0.0 | 0 |
| image.erase | lama-inpaint | standard | 43 | 386 | — | 0.0000 | 0.0000 | 22.1746 | 19.3607 | 19.3607 | 17.2711 | 0.8564 | 0.0 | 0 |

### erase-objd

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | fallback | left | psnr_box | psnr_eff | psnr_hole | ring | ssim_box | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| image.erase | lama-inpaint | draft | 61 | 167 | 173 | 0.0000 | 0.0333 | 17.8125 | 14.5649 | 15.5096 | 36.4158 | 0.7674 | 0.0 | 0 |
| image.erase | lama-inpaint | standard | 61 | 388 | 398 | 0.0000 | 0.0500 | 18.3096 | 15.0936 | 16.1320 | 36.4158 | 0.7824 | 0.0 | 0 |

### generate

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | iqa | recall | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|
| image.generate | klein-4b-base | named | 9 | 76801 | 79053 | 0.9113 | 1.0000 | 0.0 | 0 |
| image.generate | klein-4b | named | 9 | 7035 | 8765 | 0.9060 | 1.0000 | 0.0 | 0 |
| image.generate | qwen-image-flash | named | 9 | 13661 | 16324 | 0.9109 | 1.0000 | 0.0 | 0 |
| image.generate | z-image-turbo | named | 9 | 11029 | 10998 | 0.9126 | 0.9583 | 0.0 | 0 |
| image.generate | z-image | named | 9 | 69700 | 71608 | 0.8811 | 0.9375 | 0.0 | 0 |

### judge

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | score | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|
| image.describe | mage-vl | default | 40 | 1211 | — | — | — | 0 |
| image.score | siglip2-quality | default | 40 | 94 | — | 0.9044 | — | 0 |

### restore-deblur

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | psnr-degraded | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|---|
| image.restore | nafnet-restore | named | 8 | 148 | 156 | 26.7577 | 25.6038 | 0.7514 | 0.0 | 0 |
| image.restore | restormer-defocus | named | 7 | 2736 | 2785 | 26.5801 | — | 0.7962 | 0.0 | 0 |
| image.restore | restormer-motion | named | 7 | 2738 | 2790 | 25.9420 | — | 0.7480 | 0.0 | 0 |
| reference | (degraded input) | default | 6 | 0 | — | 26.7690 | — | 0.7564 | — | 0 |

### restore-denoise

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | psnr-degraded | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|---|
| image.restore | drunet-denoise | named | 7 | 300 | 321 | 27.6719 | — | 0.6437 | 0.0 | 0 |
| image.restore | nafnet-restore | named | 8 | 179 | 429 | 32.6385 | 24.0793 | 0.8914 | 0.0 | 0 |
| image.restore | restormer-denoise | named | 7 | 2754 | 2811 | 27.0476 | — | 0.8188 | 0.0 | 0 |
| image.restore | scunet-denoise | named | 7 | 1152 | 1199 | 33.3216 | — | 0.9032 | 0.0 | 0 |
| reference | (degraded input) | default | 6 | 0 | — | 23.9536 | — | 0.4658 | — | 0 |

### segment-1click

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | iou | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|
| image.segment | edgetam-segment | named | 51 | 42 | 47 | 0.6508 | 0.0 | 0 |
| image.segment | sam21-segment | named | 51 | 46 | 55 | 0.7721 | 0.0 | 0 |

### tiers

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | score | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|
| image.colorize | ddcolor-colorize | best | 1 | 159 | — | — | — | 0 |
| image.colorize | ddcolor-colorize | draft | 1 | 896 | — | — | — | 0 |
| image.colorize | ddcolor-colorize | standard | 1 | 160 | — | — | — | 0 |
| image.describe | mage-vl | default | 1 | 884 | — | — | — | 0 |
| image.edit | klein-4b | best | 1 | 12071 | — | — | 0.0 | 0 |
| image.edit | klein-4b | draft | 1 | 12431 | — | — | 0.0 | 0 |
| image.edit | klein-4b | standard | 1 | 12052 | — | — | 0.0 | 0 |
| image.enhance_prompt | qwen3.5-4b | default | 1 | 1153 | — | — | — | 0 |
| image.erase | lama-inpaint | draft | 1 | 78 | — | — | 0.0 | 0 |
| image.erase | lama-inpaint | standard | 1 | 115 | — | — | 0.0 | 0 |
| image.erase | mage-flow-edit-turbo | best | 1 | 9382 | — | — | 0.0 | 0 |
| image.extend | lama-inpaint | best | 1 | 156 | — | — | 0.0 | 0 |
| image.extend | lama-inpaint | draft | 1 | 99 | — | — | 0.0 | 0 |
| image.extend | lama-inpaint | standard | 1 | 198 | — | — | 0.0 | 0 |
| image.fill | lama-inpaint | best | 1 | 113 | — | — | 0.0 | 0 |
| image.fill | lama-inpaint | draft | 1 | 586 | — | — | 0.0 | 0 |
| image.fill | lama-inpaint | standard | 1 | 929 | — | — | 0.0 | 0 |
| image.generate | klein-4b | draft | 1 | 4445 | — | — | 0.0 | 0 |
| image.generate | z-image-turbo | best | 1 | 2556 | — | — | 0.0 | 0 |
| image.generate | z-image-turbo | standard | 1 | 3674 | — | — | 0.0 | 0 |
| image.matte | birefnet-matte | default | 1 | 1350 | — | — | — | 0 |
| image.relight | cidnet-relight | best | 1 | 32 | — | — | — | 0 |
| image.relight | cidnet-relight | draft | 1 | 56 | — | — | — | 0 |
| image.relight | cidnet-relight | standard | 1 | 32 | — | — | — | 0 |
| image.restore | nafnet-restore | best | 1 | 84 | — | — | 0.0 | 0 |
| image.restore | nafnet-restore | draft | 1 | 152 | — | — | 0.0 | 0 |
| image.restore | nafnet-restore | standard | 1 | 86 | — | — | 0.0 | 0 |
| image.score | siglip2-quality | default | 1 | 360 | — | 0.9331 | — | 0 |
| image.segment | sam21-segment | default | 1 | 920 | — | — | 0.0 | 0 |
| image.upscale | heart-upscale | best | 1 | 3694 | — | — | 0.0 | 0 |
| image.upscale | nerve-upscale | draft | 1 | 880 | — | — | 0.0 | 0 |
| image.upscale | realplksr-upscale | standard | 1 | 1283 | — | — | 0.0 | 0 |

### upscale-x2

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|
| image.upscale | anime4k-upscale | named | 7 | 105 | 104 | 33.1656 | 0.9230 | 0.0 | 0 |
| image.upscale | heart-upscale | named | 7 | 1998 | 2007 | 33.1117 | 0.9344 | 0.0 | 0 |
| image.upscale | nacre-upscale | named | 7 | 11767 | 11741 | 29.3621 | 0.8775 | 0.0 | 0 |
| image.upscale | nerve-upscale | named | 7 | 188 | 185 | 30.1837 | 0.8748 | 0.0 | 0 |
| image.upscale | realplksr-upscale | named | 7 | 572 | 671 | 31.9626 | 0.9226 | 0.0 | 0 |
| image.upscale | seedvr2-upscale | named | 7 | 4337 | 4063 | 26.8793 | 0.7792 | 0.0 | 0 |
| image.upscale | vosr2-upscale | named | 7 | 1638 | 1685 | 28.8615 | 0.8436 | 0.0 | 0 |

### upscale-x4

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|
| image.upscale | anime4k-upscale | named | 7 | 94 | 555 | 27.2325 | 0.7781 | 0.0 | 0 |
| image.upscale | heart-upscale | named | 7 | 530 | 539 | 27.0521 | 0.7824 | 0.0 | 0 |
| image.upscale | nacre-upscale | named | 7 | 4391 | 30308 | 25.6290 | 0.7474 | 0.0 | 0 |
| image.upscale | nerve-upscale | named | 7 | 124 | 161 | 26.9734 | 0.7791 | 0.0 | 0 |
| image.upscale | realplksr-upscale | named | 7 | 211 | 214 | 26.4587 | 0.7557 | 0.0 | 0 |
| image.upscale | seedvr2-upscale | named | 7 | 4403 | 5443 | 25.6371 | 0.7357 | 0.0 | 0 |
| image.upscale | vosr2-upscale | named | 7 | 1616 | 3290 | 26.3457 | 0.7468 | 0.0 | 0 |
