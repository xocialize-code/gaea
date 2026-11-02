| Suite | Operation | Model | Tier | Pairs | Same bytes | Same pixels | Worst PSNR (dB) | Max diff | Gaea warm (ms) | Engine warm (ms) | Ratio | Errors |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| upscale-x4 | image.upscale | realplksr-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 213 | 219 | 0.97 |  |
| upscale-x4 | image.upscale | anime4k-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 95 | 99 | 0.96 |  |
| upscale-x4 | image.upscale | heart-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 548 | 552 | 0.99 |  |
| upscale-x4 | image.upscale | nacre-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 5378 | 4614 | 1.17 |  |
| upscale-x4 | image.upscale | nerve-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 139 | 153 | 0.91 |  |
| upscale-x4 | image.upscale | vosr2-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 1707 | 1627 | 1.05 |  |
| upscale-x2 | image.upscale | realplksr-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 582 | 582 | 1.00 |  |
| upscale-x2 | image.upscale | anime4k-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 106 | 112 | 0.95 |  |
| upscale-x2 | image.upscale | heart-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 2054 | 2087 | 0.98 |  |
| upscale-x2 | image.upscale | nacre-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 14911 | 12516 | 1.19 |  |
| upscale-x2 | image.upscale | nerve-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 185 | 193 | 0.96 |  |
| upscale-x2 | image.upscale | vosr2-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 1724 | 1661 | 1.04 |  |
| restore-denoise | image.restore | nafnet-restore | - | 8 | 0/8 | 0/8 | ∞ | — | 184 | 189 | 0.97 |  |
| restore-denoise | image.restore | scunet-denoise | - | 7 | 0/7 | 0/7 | ∞ | — | 1857 | 1229 | 1.51 |  |
| restore-denoise | image.restore | restormer-denoise | - | 7 | 0/7 | 0/7 | ∞ | — | 2892 | 2824 | 1.02 |  |
| restore-denoise | image.restore | drunet-denoise | - | 7 | 0/7 | 0/7 | ∞ | — | 365 | 310 | 1.18 |  |
| restore-denoise | reference | (degraded input) | - | 6 | 0/0 | 0/0 | — | — | 0 | 0 | — |  |
| restore-deblur | image.restore | nafnet-restore | - | 8 | 0/8 | 0/8 | ∞ | — | 160 | 147 | 1.09 |  |
| restore-deblur | image.restore | restormer-motion | - | 7 | 0/7 | 0/7 | ∞ | — | 3102 | 2791 | 1.11 |  |
| restore-deblur | image.restore | restormer-defocus | - | 7 | 0/7 | 0/7 | ∞ | — | 2889 | 2770 | 1.04 |  |
| restore-deblur | reference | (degraded input) | - | 6 | 0/0 | 0/0 | — | — | 0 | 0 | — |  |

| Operation | Tier | Gaea | Engine | Same |
|---|---|---|---|---|

Only on the engine: generate|image.generate|klein-4b-base|-, generate|image.generate|klein-4b|-, generate|image.generate|qwen-image-flash|-, generate|image.generate|z-image-turbo|-, generate|image.generate|z-image|-, judge|image.describe|mage-vl|-, judge|image.score|siglip2-quality|-, singles|image.colorize|ddcolor-colorize|-, singles|image.describe|mage-vl|-, singles|image.matte|birefnet-matte|-, singles|image.relight|cidnet-relight|-, singles|image.score|siglip2-quality|-, upscale-x2|image.upscale|seedvr2-upscale|-, upscale-x4|image.upscale|seedvr2-upscale|-
