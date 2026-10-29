# Tier bench — Gaea

Run 2026-10-29T04:02:46Z, engine http://127.0.0.1:17761/mes/v0.

### edits

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) |  | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|
| image.edit | klein-4b | best | 2 | 13383 | 13403 |  | 0.0 | 0 |
| image.edit | klein-4b | draft | 2 | 13381 | 15009 |  | 0.0 | 0 |
| image.erase | lama-inpaint | best | 2 | 431 | 429 |  | 0.0 | 0 |
| image.erase | lama-inpaint | standard | 2 | 435 | 699 |  | 0.0 | 0 |
| image.extend | lama-inpaint | best | 2 | 619 | 618 |  | 0.0 | 0 |
| image.extend | lama-inpaint | draft | 2 | 252 | 264 |  | 0.0 | 0 |
| image.extend | lama-inpaint | standard | 2 | 619 | 667 |  | 0.0 | 0 |
| image.fill | klein-4b | best | 2 | 13399 | 13428 |  | 0.0 | 0 |
| image.fill | klein-4b | standard | 2 | 13380 | 13386 |  | 0.0 | 0 |

### erase-eff

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | fallback | left | psnr_box | psnr_eff | psnr_hole | ring | ssim_box | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| image.erase | lama-inpaint | draft | 43 | 165 | — | 0.0000 | 0.0000 | 21.1678 | 18.3208 | 18.3208 | 19.2094 | 0.8271 | 0.0 | 0 |
| image.erase | lama-inpaint | standard | 43 | 398 | — | 0.0000 | 0.0000 | 22.1746 | 19.3607 | 19.3607 | 17.2711 | 0.8564 | 0.0 | 0 |

### erase-objd

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | fallback | left | psnr_box | psnr_eff | psnr_hole | ring | ssim_box | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| image.erase | lama-inpaint | draft | 61 | 171 | 191 | 0.0000 | 0.0333 | 17.8125 | 14.5649 | 15.5096 | 36.4158 | 0.7674 | 0.0 | 0 |
| image.erase | lama-inpaint | standard | 61 | 402 | 428 | 0.0000 | 0.0500 | 18.3096 | 15.0936 | 16.1320 | 36.4158 | 0.7824 | 0.0 | 0 |

### generate

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) |  | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|
| image.generate | klein-4b-base | named | 9 | 74779 | 73921 |  | 0.0 | 0 |
| image.generate | klein-4b | named | 9 | 7296 | 7360 |  | 0.0 | 0 |
| image.generate | qwen-image-flash | named | 9 | 14109 | 21030 |  | 0.0 | 0 |
| image.generate | z-image-turbo | named | 9 | 11204 | 11089 |  | 0.0 | 0 |
| image.generate | z-image | named | 9 | 72293 | 74773 |  | 0.0 | 0 |

### judge

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) |  | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|
| image.describe | ? | default | 0 | — | — |  | — | 40 |
| image.score | ? | default | 0 | — | — |  | — | 40 |

### restore-deblur

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | psnr-degraded | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|---|
| image.restore | nafnet-restore | named | 8 | 157 | 158 | 26.7577 | 25.6038 | 0.7514 | 0.0 | 0 |
| image.restore | restormer-defocus | named | 7 | 2786 | 2829 | 26.5801 | — | 0.7962 | 0.0 | 0 |
| image.restore | restormer-motion | named | 7 | 2786 | 2829 | 25.9420 | — | 0.7480 | 0.0 | 0 |
| reference | (degraded input) | default | 6 | 0 | — | 26.7690 | — | 0.7564 | — | 0 |

### restore-denoise

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | psnr-degraded | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|---|
| image.restore | nafnet-restore | named | 8 | 184 | 188 | 32.6385 | 24.0793 | 0.8914 | 0.0 | 0 |
| image.restore | restormer-denoise | named | 7 | 2796 | 2826 | 27.0476 | — | 0.8188 | 0.0 | 0 |
| image.restore | scunet-denoise | named | 7 | 1185 | 1233 | 33.3216 | — | 0.9032 | 0.0 | 0 |
| reference | (degraded input) | default | 6 | 0 | — | 23.9536 | — | 0.4658 | — | 0 |

### segment-1click

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | iou | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|
| image.segment | edgetam-segment | named | 51 | 40 | 46 | 0.6508 | 0.0 | 0 |
| image.segment | sam21-segment | named | 51 | 44 | 53 | 0.7721 | 0.0 | 0 |

### tiers

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) |  | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|
| image.edit | klein-4b | best | 1 | 2802 | — |  | 0.0 | 0 |
| image.edit | klein-4b | draft | 1 | 2835 | — |  | 0.0 | 0 |
| image.edit | klein-4b | standard | 1 | 2805 | — |  | 0.0 | 0 |
| image.enhance_prompt | qwen3.5-4b | default | 1 | 1124 | — |  | — | 0 |
| image.erase | lama-inpaint | best | 1 | 113 | — |  | 0.0 | 0 |
| image.erase | lama-inpaint | draft | 1 | 78 | — |  | 0.0 | 0 |
| image.erase | lama-inpaint | standard | 1 | 113 | — |  | 0.0 | 0 |
| image.extend | lama-inpaint | best | 1 | 155 | — |  | 0.0 | 0 |
| image.extend | lama-inpaint | draft | 1 | 99 | — |  | 0.0 | 0 |
| image.extend | lama-inpaint | standard | 1 | 191 | — |  | 0.0 | 0 |
| image.fill | lama-inpaint | best | 1 | 105 | — |  | 0.0 | 0 |
| image.fill | lama-inpaint | draft | 1 | 505 | — |  | 0.0 | 0 |
| image.fill | lama-inpaint | standard | 1 | 214 | — |  | 0.0 | 0 |
| image.generate | klein-4b | draft | 1 | 5210 | — |  | 0.0 | 0 |
| image.generate | z-image-turbo | best | 1 | 2631 | — |  | 0.0 | 0 |
| image.generate | z-image-turbo | standard | 1 | 4081 | — |  | 0.0 | 0 |
| image.matte | birefnet-matte | default | 1 | 365 | — |  | — | 0 |
| image.restore | nafnet-restore | best | 1 | 91 | — |  | 0.0 | 0 |
| image.restore | nafnet-restore | draft | 1 | 100 | — |  | 0.0 | 0 |
| image.restore | nafnet-restore | standard | 1 | 86 | — |  | 0.0 | 0 |
| image.segment | sam21-segment | default | 1 | 70 | — |  | 0.0 | 0 |
| image.upscale | heart-upscale | best | 1 | 2069 | — |  | 0.0 | 0 |
| image.upscale | nerve-upscale | draft | 1 | 230 | — |  | 0.0 | 0 |
| image.upscale | realplksr-upscale | standard | 1 | 620 | — |  | 0.0 | 0 |

### upscale-x2

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|
| image.upscale | heart-upscale | named | 7 | 2022 | 2038 | 33.1117 | 0.9344 | 0.0 | 0 |
| image.upscale | nerve-upscale | named | 7 | 194 | 189 | 30.1837 | 0.8748 | 0.0 | 0 |
| image.upscale | realplksr-upscale | named | 7 | 579 | 584 | 31.9626 | 0.9226 | 0.0 | 0 |

### upscale-x4

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|
| image.upscale | heart-upscale | named | 7 | 526 | 555 | 27.0521 | 0.7824 | 0.0 | 0 |
| image.upscale | nerve-upscale | named | 7 | 130 | 137 | 26.9734 | 0.7791 | 0.0 | 0 |
| image.upscale | realplksr-upscale | named | 7 | 213 | 219 | 26.4587 | 0.7557 | 0.0 | 0 |
