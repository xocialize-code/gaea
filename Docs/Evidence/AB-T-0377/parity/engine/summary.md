# Tier bench — Pixel Agency Image Engine

Run 2026-10-29T06:34:13Z, engine http://127.0.0.1:17611/mes/v0.

### generate

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | iqa | recall | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|
| image.generate | klein-4b-base | named | 9 | 76641 | 78579 | 0.9113 | 1.0000 | 0.0 | 0 |
| image.generate | klein-4b | named | 9 | 7180 | 9722 | 0.9060 | 1.0000 | 0.0 | 0 |
| image.generate | qwen-image-flash | named | 9 | 13540 | 15957 | 0.9109 | 1.0000 | 0.0 | 0 |
| image.generate | z-image-turbo | named | 9 | 11164 | 13361 | 0.9126 | 0.9583 | 0.0 | 0 |
| image.generate | z-image | named | 9 | 68988 | 71570 | 0.8811 | 0.9375 | 0.0 | 0 |

### judge

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | score | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|
| image.describe | mage-vl | default | 40 | 1215 | — | — | 0.0 | 0 |
| image.score | siglip2-quality | default | 40 | 99 | — | 0.9044 | 0.0 | 0 |

### restore-deblur

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | psnr-degraded | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|---|
| image.restore | nafnet-restore | named | 8 | 147 | 159 | 26.7577 | 25.6038 | 0.7514 | 0.0 | 0 |
| image.restore | restormer-defocus | named | 7 | 2770 | 2819 | 26.5801 | — | 0.7962 | 0.0 | 0 |
| image.restore | restormer-motion | named | 7 | 2791 | 2848 | 25.9420 | — | 0.7480 | 0.0 | 0 |
| reference | (degraded input) | default | 6 | 0 | — | 26.7690 | — | 0.7564 | — | 0 |

### restore-denoise

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | psnr-degraded | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|---|
| image.restore | drunet-denoise | named | 7 | 310 | 343 | 27.6719 | — | 0.6437 | 0.0 | 0 |
| image.restore | nafnet-restore | named | 8 | 189 | 330 | 32.6385 | 24.0793 | 0.8914 | 0.0 | 0 |
| image.restore | restormer-denoise | named | 7 | 2824 | 2890 | 27.0476 | — | 0.8188 | 0.0 | 0 |
| image.restore | scunet-denoise | named | 7 | 1229 | 1290 | 33.3216 | — | 0.9032 | 0.0 | 0 |
| reference | (degraded input) | default | 6 | 0 | — | 23.9536 | — | 0.4658 | — | 0 |

### singles

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | score | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|
| image.colorize | ddcolor-colorize | default | 3 | 264 | 288 | — | 0.0 | 0 |
| image.describe | mage-vl | default | 3 | 1485 | 5818 | — | 0.0 | 0 |
| image.matte | birefnet-matte | default | 3 | 641 | 561 | — | 0.0 | 0 |
| image.relight | cidnet-relight | default | 3 | 658 | 735 | — | 0.0 | 0 |
| image.score | siglip2-quality | default | 3 | 116 | 391 | 0.9125 | 0.0 | 0 |

### upscale-x2

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|
| image.upscale | anime4k-upscale | named | 7 | 112 | 109 | 33.1656 | 0.9230 | 0.0 | 0 |
| image.upscale | heart-upscale | named | 7 | 2087 | 2091 | 33.1117 | 0.9344 | 0.0 | 0 |
| image.upscale | nacre-upscale | named | 7 | 12516 | 12481 | 29.3621 | 0.8775 | 0.0 | 0 |
| image.upscale | nerve-upscale | named | 7 | 193 | 197 | 30.1837 | 0.8748 | 0.0 | 0 |
| image.upscale | realplksr-upscale | named | 7 | 582 | 606 | 31.9626 | 0.9226 | 0.0 | 0 |
| image.upscale | seedvr2-upscale | named | 7 | 4701 | 4314 | 26.8793 | 0.7792 | 0.0 | 0 |
| image.upscale | vosr2-upscale | named | 7 | 1661 | 1700 | 28.8615 | 0.8436 | 0.0 | 0 |

### upscale-x4

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|
| image.upscale | anime4k-upscale | named | 7 | 99 | 105 | 27.2325 | 0.7781 | 0.0 | 0 |
| image.upscale | heart-upscale | named | 7 | 552 | 1649 | 27.0521 | 0.7824 | 0.0 | 0 |
| image.upscale | nacre-upscale | named | 7 | 4614 | 24164 | 25.6290 | 0.7474 | 0.0 | 0 |
| image.upscale | nerve-upscale | named | 7 | 153 | 139 | 26.9734 | 0.7791 | 0.0 | 0 |
| image.upscale | realplksr-upscale | named | 7 | 219 | 259 | 26.4587 | 0.7557 | 0.0 | 0 |
| image.upscale | seedvr2-upscale | named | 7 | 10253 | 10497 | 25.6371 | 0.7357 | 0.0 | 0 |
| image.upscale | vosr2-upscale | named | 7 | 1627 | 2078 | 26.3457 | 0.7468 | 0.0 | 0 |
