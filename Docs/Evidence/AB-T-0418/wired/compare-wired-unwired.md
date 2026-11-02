| Suite | Operation | Model | Tier | Pairs | Same bytes | Same pixels | Worst PSNR (dB) | Max diff | Gaea warm (ms) | Engine warm (ms) | Ratio | Errors |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| upscale-x4 | image.upscale | realplksr-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 220 | 213 | 1.03 |  |
| upscale-x4 | image.upscale | anime4k-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 95 | 95 | 1.00 |  |
| upscale-x4 | image.upscale | heart-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 554 | 548 | 1.01 |  |
| upscale-x4 | image.upscale | nacre-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 4504 | 5378 | 0.84 |  |
| upscale-x4 | image.upscale | nerve-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 138 | 139 | 0.99 |  |
| upscale-x4 | image.upscale | vosr2-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 1708 | 1707 | 1.00 |  |
| upscale-x2 | image.upscale | realplksr-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 594 | 582 | 1.02 |  |
| upscale-x2 | image.upscale | anime4k-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 106 | 106 | 1.00 |  |
| upscale-x2 | image.upscale | heart-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 2070 | 2054 | 1.01 |  |
| upscale-x2 | image.upscale | nacre-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 12149 | 14911 | 0.81 |  |
| upscale-x2 | image.upscale | nerve-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 198 | 185 | 1.07 |  |
| upscale-x2 | image.upscale | vosr2-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 1732 | 1724 | 1.00 |  |
| restore-denoise | image.restore | nafnet-restore | - | 8 | 8/8 | 8/8 | ∞ | 0 | 186 | 184 | 1.01 |  |
| restore-denoise | image.restore | scunet-denoise | - | 7 | 7/7 | 7/7 | ∞ | 0 | 1166 | 1857 | 0.63 |  |
| restore-denoise | image.restore | restormer-denoise | - | 7 | 7/7 | 7/7 | ∞ | 0 | 2849 | 2892 | 0.99 |  |
| restore-denoise | image.restore | drunet-denoise | - | 7 | 7/7 | 7/7 | ∞ | 0 | 302 | 365 | 0.83 |  |
| restore-denoise | reference | (degraded input) | - | 6 | 0/0 | 0/0 | — | — | 0 | 0 | — |  |
| restore-deblur | image.restore | nafnet-restore | - | 8 | 8/8 | 8/8 | ∞ | 0 | 151 | 160 | 0.94 |  |
| restore-deblur | image.restore | restormer-motion | - | 7 | 7/7 | 7/7 | ∞ | 0 | 2829 | 3102 | 0.91 |  |
| restore-deblur | image.restore | restormer-defocus | - | 7 | 7/7 | 7/7 | ∞ | 0 | 2821 | 2889 | 0.98 |  |
| restore-deblur | reference | (degraded input) | - | 6 | 0/0 | 0/0 | — | — | 0 | 0 | — |  |

| Operation | Tier | Gaea | Engine | Same |
|---|---|---|---|---|
