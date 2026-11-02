# Tier bench — Gaea

Run 2026-11-02T14:30:19Z, engine http://127.0.0.1:17761/mes/v0.

### restore-deblur

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | psnr-degraded | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|---|
| image.restore | nafnet-restore | named | 8 | 151 | 173 | 26.7577 | 25.6038 | 0.7514 | 0.0 | 0 |
| image.restore | restormer-defocus | named | 7 | 2821 | 2870 | 26.5801 | — | 0.7962 | 0.0 | 0 |
| image.restore | restormer-motion | named | 7 | 2829 | 2885 | 25.9420 | — | 0.7480 | 0.0 | 0 |
| reference | (degraded input) | default | 6 | 0 | — | 26.7690 | — | 0.7564 | — | 0 |

### restore-denoise

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | psnr-degraded | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|---|
| image.restore | drunet-denoise | named | 7 | 302 | 325 | 27.6719 | — | 0.6437 | 0.0 | 0 |
| image.restore | nafnet-restore | named | 8 | 186 | 237 | 32.6385 | 24.0793 | 0.8914 | 0.0 | 0 |
| image.restore | restormer-denoise | named | 7 | 2849 | 2907 | 27.0476 | — | 0.8188 | 0.0 | 0 |
| image.restore | scunet-denoise | named | 7 | 1166 | 1234 | 33.3216 | — | 0.9032 | 0.0 | 0 |
| reference | (degraded input) | default | 6 | 0 | — | 23.9536 | — | 0.4658 | — | 0 |

### upscale-x2

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|
| image.upscale | anime4k-upscale | named | 7 | 106 | 103 | 33.1656 | 0.9230 | 0.0 | 0 |
| image.upscale | heart-upscale | named | 7 | 2070 | 2101 | 33.1117 | 0.9344 | 0.0 | 0 |
| image.upscale | nacre-upscale | named | 7 | 12149 | 12139 | 29.3621 | 0.8775 | 0.0 | 0 |
| image.upscale | nerve-upscale | named | 7 | 198 | 198 | 30.1837 | 0.8748 | 0.0 | 0 |
| image.upscale | realplksr-upscale | named | 7 | 594 | 608 | 31.9626 | 0.9226 | 0.0 | 0 |
| image.upscale | vosr2-upscale | named | 7 | 1732 | 1768 | 28.8615 | 0.8436 | 0.0 | 0 |

### upscale-x4

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|
| image.upscale | anime4k-upscale | named | 7 | 95 | 92 | 27.2325 | 0.7781 | 0.0 | 0 |
| image.upscale | heart-upscale | named | 7 | 554 | 646 | 27.0521 | 0.7824 | 0.0 | 0 |
| image.upscale | nacre-upscale | named | 7 | 4504 | 4589 | 25.6290 | 0.7474 | 0.0 | 0 |
| image.upscale | nerve-upscale | named | 7 | 138 | 145 | 26.9734 | 0.7791 | 0.0 | 0 |
| image.upscale | realplksr-upscale | named | 7 | 220 | 852 | 26.4587 | 0.7557 | 0.0 | 0 |
| image.upscale | vosr2-upscale | named | 7 | 1708 | 2126 | 26.3457 | 0.7468 | 0.0 | 0 |
