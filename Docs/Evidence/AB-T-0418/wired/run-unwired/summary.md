# Tier bench — Gaea

Run 2026-11-02T14:35:10Z, engine http://127.0.0.1:17761/mes/v0.

### restore-deblur

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | psnr-degraded | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|---|
| image.restore | nafnet-restore | named | 8 | 160 | 167 | 26.7577 | 25.6038 | 0.7514 | 0.0 | 0 |
| image.restore | restormer-defocus | named | 7 | 2889 | 2917 | 26.5801 | — | 0.7962 | 0.0 | 0 |
| image.restore | restormer-motion | named | 7 | 3102 | 3120 | 25.9420 | — | 0.7480 | 0.0 | 0 |
| reference | (degraded input) | default | 6 | 0 | — | 26.7690 | — | 0.7564 | — | 0 |

### restore-denoise

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | psnr-degraded | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|---|
| image.restore | drunet-denoise | named | 7 | 365 | 415 | 27.6719 | — | 0.6437 | 0.0 | 0 |
| image.restore | nafnet-restore | named | 8 | 184 | 210 | 32.6385 | 24.0793 | 0.8914 | 0.0 | 0 |
| image.restore | restormer-denoise | named | 7 | 2892 | 6742 | 27.0476 | — | 0.8188 | 0.0 | 0 |
| image.restore | scunet-denoise | named | 7 | 1857 | 1287 | 33.3216 | — | 0.9032 | 0.0 | 0 |
| reference | (degraded input) | default | 6 | 0 | — | 23.9536 | — | 0.4658 | — | 0 |

### upscale-x2

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|
| image.upscale | anime4k-upscale | named | 7 | 106 | 100 | 33.1656 | 0.9230 | 0.0 | 0 |
| image.upscale | heart-upscale | named | 7 | 2054 | 2086 | 33.1117 | 0.9344 | 0.0 | 0 |
| image.upscale | nacre-upscale | named | 7 | 14911 | 14765 | 29.3621 | 0.8775 | 0.0 | 0 |
| image.upscale | nerve-upscale | named | 7 | 185 | 207 | 30.1837 | 0.8748 | 0.0 | 0 |
| image.upscale | realplksr-upscale | named | 7 | 582 | 601 | 31.9626 | 0.9226 | 0.0 | 0 |
| image.upscale | vosr2-upscale | named | 7 | 1724 | 1753 | 28.8615 | 0.8436 | 0.0 | 0 |

### upscale-x4

| Operation | Model | Tier | Runs | Median warm (ms) | First run (ms) | psnr | ssim | Footprint (GB) | Errors |
|---|---|---|---|---|---|---|---|---|---|
| image.upscale | anime4k-upscale | named | 7 | 95 | 90 | 27.2325 | 0.7781 | 0.0 | 0 |
| image.upscale | heart-upscale | named | 7 | 548 | 614 | 27.0521 | 0.7824 | 0.0 | 0 |
| image.upscale | nacre-upscale | named | 7 | 5378 | 5426 | 25.6290 | 0.7474 | 0.0 | 0 |
| image.upscale | nerve-upscale | named | 7 | 139 | 134 | 26.9734 | 0.7791 | 0.0 | 0 |
| image.upscale | realplksr-upscale | named | 7 | 213 | 355 | 26.4587 | 0.7557 | 0.0 | 0 |
| image.upscale | vosr2-upscale | named | 7 | 1707 | 1891 | 26.3457 | 0.7468 | 0.0 | 0 |
