| Suite | Operation | Model | Tier | Pairs | Same bytes | Same pixels | Worst PSNR (dB) | Max diff | Gaea warm (ms) | Engine warm (ms) | Ratio | Errors |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| upscale-x4 | image.upscale | realplksr-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 220 | 219 | 1.00 |  |
| upscale-x4 | image.upscale | anime4k-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 95 | 99 | 0.96 |  |
| upscale-x4 | image.upscale | heart-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 554 | 552 | 1.00 |  |
| upscale-x4 | image.upscale | nacre-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 4504 | 4614 | 0.98 |  |
| upscale-x4 | image.upscale | nerve-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 138 | 153 | 0.90 |  |
| upscale-x4 | image.upscale | vosr2-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 1708 | 1627 | 1.05 |  |
| upscale-x2 | image.upscale | realplksr-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 594 | 582 | 1.02 |  |
| upscale-x2 | image.upscale | anime4k-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 106 | 112 | 0.95 |  |
| upscale-x2 | image.upscale | heart-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 2070 | 2087 | 0.99 |  |
| upscale-x2 | image.upscale | nacre-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 12149 | 12516 | 0.97 |  |
| upscale-x2 | image.upscale | nerve-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 198 | 193 | 1.03 |  |
| upscale-x2 | image.upscale | vosr2-upscale | - | 7 | 0/7 | 0/7 | ∞ | — | 1732 | 1661 | 1.04 |  |
| restore-denoise | image.restore | nafnet-restore | - | 8 | 0/8 | 0/8 | ∞ | — | 186 | 189 | 0.98 |  |
| restore-denoise | image.restore | scunet-denoise | - | 7 | 0/7 | 0/7 | ∞ | — | 1166 | 1229 | 0.95 |  |
| restore-denoise | image.restore | restormer-denoise | - | 7 | 0/7 | 0/7 | ∞ | — | 2849 | 2824 | 1.01 |  |
| restore-denoise | image.restore | drunet-denoise | - | 7 | 0/7 | 0/7 | ∞ | — | 302 | 310 | 0.97 |  |
| restore-denoise | reference | (degraded input) | - | 6 | 0/0 | 0/0 | — | — | 0 | 0 | — |  |
| restore-deblur | image.restore | nafnet-restore | - | 8 | 0/8 | 0/8 | ∞ | — | 151 | 147 | 1.03 |  |
| restore-deblur | image.restore | restormer-motion | - | 7 | 0/7 | 0/7 | ∞ | — | 2829 | 2791 | 1.01 |  |
| restore-deblur | image.restore | restormer-defocus | - | 7 | 0/7 | 0/7 | ∞ | — | 2821 | 2770 | 1.02 |  |
| restore-deblur | reference | (degraded input) | - | 6 | 0/0 | 0/0 | — | — | 0 | 0 | — |  |

| Operation | Tier | Gaea | Engine | Same |
|---|---|---|---|---|

Only on the engine: generate|image.generate|klein-4b-base|-, generate|image.generate|klein-4b|-, generate|image.generate|qwen-image-flash|-, generate|image.generate|z-image-turbo|-, generate|image.generate|z-image|-, judge|image.describe|mage-vl|-, judge|image.score|siglip2-quality|-, singles|image.colorize|ddcolor-colorize|-, singles|image.describe|mage-vl|-, singles|image.matte|birefnet-matte|-, singles|image.relight|cidnet-relight|-, singles|image.score|siglip2-quality|-, upscale-x2|image.upscale|seedvr2-upscale|-, upscale-x4|image.upscale|seedvr2-upscale|-
