# Tier bench — Gaea

Run 2026-10-29T07:06:32Z, engine http://127.0.0.1:17761/mes/v0.

### generate

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | iqa | recall | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|
| image.generate | klein-4b-base | named | 9 | 72967 | 74521 | 0.9113 | 1.0000 | 0.0 | 0 |
| image.generate | klein-4b | named | 9 | 7469 | 10658 | 0.9060 | 1.0000 | 0.0 | 0 |
| image.generate | qwen-image-flash | named | 9 | 13722 | 21482 | 0.9109 | 1.0000 | 0.0 | 0 |
| image.generate | z-image-turbo | named | 9 | 11364 | 13895 | 0.9126 | 0.9583 | 0.0 | 0 |
| image.generate | z-image | named | 9 | 68896 | 71989 | 0.8811 | 0.9375 | 0.0 | 0 |

### judge

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | score | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|
| image.describe | mage-vl | default | 40 | 1212 | — | — | 0.0 | 0 |
| image.score | siglip2-quality | default | 40 | 93 | — | 0.9044 | 0.0 | 0 |

### restore-deblur

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | psnr-degraded | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|---|
| image.restore | nafnet-restore | named | 8 | 156 | 164 | 26.7577 | 25.6038 | 0.7514 | 0.0 | 0 |
| image.restore | restormer-defocus | named | 7 | 2893 | 3045 | 26.5801 | — | 0.7962 | 0.0 | 0 |
| image.restore | restormer-motion | named | 7 | 2855 | 2917 | 25.9420 | — | 0.7480 | 0.0 | 0 |
| reference | (degraded input) | default | 6 | 0 | — | 26.7690 | — | 0.7564 | — | 0 |

### restore-denoise

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | psnr-degraded | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|---|
| image.restore | drunet-denoise | named | 7 | 378 | 426 | 27.6719 | — | 0.6437 | 0.0 | 0 |
| image.restore | nafnet-restore | named | 8 | 189 | 197 | 32.6385 | 24.0793 | 0.8914 | 0.0 | 0 |
| image.restore | restormer-denoise | named | 7 | 2865 | 2914 | 27.0476 | — | 0.8188 | 0.0 | 0 |
| image.restore | scunet-denoise | named | 7 | 1330 | 1385 | 33.3216 | — | 0.9032 | 0.0 | 0 |
| reference | (degraded input) | default | 6 | 0 | — | 23.9536 | — | 0.4658 | — | 0 |

### singles

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | score | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|
| image.colorize | ddcolor-colorize | default | 3 | 249 | 297 | — | 0.0 | 0 |
| image.describe | mage-vl | default | 3 | 1110 | 3324 | — | 0.0 | 0 |
| image.matte | birefnet-matte | default | 3 | 460 | 824 | — | 0.0 | 0 |
| image.relight | cidnet-relight | default | 3 | 701 | 976 | — | 0.0 | 0 |
| image.score | siglip2-quality | default | 3 | 102 | 423 | 0.9125 | 0.0 | 0 |

### upscale-x2

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|
| image.upscale | anime4k-upscale | named | 7 | 105 | 103 | 33.1656 | 0.9230 | 0.0 | 0 |
| image.upscale | heart-upscale | named | 7 | 2015 | 2040 | 33.1117 | 0.9344 | 0.0 | 0 |
| image.upscale | nacre-upscale | named | 7 | 14521 | 14492 | 29.3621 | 0.8775 | 0.0 | 0 |
| image.upscale | nerve-upscale | named | 7 | 194 | 195 | 30.1837 | 0.8748 | 0.0 | 0 |
| image.upscale | realplksr-upscale | named | 7 | 581 | 591 | 31.9626 | 0.9226 | 0.0 | 0 |
| image.upscale | vosr2-upscale | named | 7 | 1683 | 1710 | 28.8615 | 0.8436 | 0.0 | 0 |

### upscale-x4

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|
| image.upscale | anime4k-upscale | named | 7 | 94 | 96 | 27.2325 | 0.7781 | 0.0 | 0 |
| image.upscale | heart-upscale | named | 7 | 527 | 585 | 27.0521 | 0.7824 | 0.0 | 0 |
| image.upscale | nacre-upscale | named | 7 | 5321 | 5434 | 25.6290 | 0.7474 | 0.0 | 0 |
| image.upscale | nerve-upscale | named | 7 | 129 | 142 | 26.9734 | 0.7791 | 0.0 | 0 |
| image.upscale | realplksr-upscale | named | 7 | 221 | 230 | 26.4587 | 0.7557 | 0.0 | 0 |
| image.upscale | vosr2-upscale | named | 7 | 1654 | 2032 | 26.3457 | 0.7468 | 0.0 | 0 |
