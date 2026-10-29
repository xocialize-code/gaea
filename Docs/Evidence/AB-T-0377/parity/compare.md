| Suite | Operation | Model | Tier | Pairs | Same bytes | Same pixels | Worst PSNR (dB) | Max diff | Gaea warm (ms) | Engine warm (ms) | Ratio | Errors |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| singles | image.relight | cidnet-relight | - | 3 | 3/3 | 3/3 | ∞ | 0 | 701 | 658 | 1.07 |  |
| singles | image.colorize | ddcolor-colorize | - | 3 | 3/3 | 3/3 | ∞ | 0 | 249 | 264 | 0.94 |  |
| singles | image.matte | birefnet-matte | - | 3 | 6/6 | 6/6 | ∞ | 0 | 460 | 641 | 0.72 |  |
| singles | image.describe | mage-vl | - | 3 | 3/3 | 3/3 | ∞ | 0 | 1110 | 1485 | 0.75 |  |
| singles | image.score | siglip2-quality | - | 3 | 3/3 | 3/3 | ∞ | 0 | 102 | 116 | 0.88 |  |
| upscale-x4 | image.upscale | realplksr-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 221 | 219 | 1.01 |  |
| upscale-x4 | image.upscale | anime4k-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 94 | 99 | 0.95 |  |
| upscale-x4 | image.upscale | heart-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 527 | 552 | 0.95 |  |
| upscale-x4 | image.upscale | nacre-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 5321 | 4614 | 1.15 |  |
| upscale-x4 | image.upscale | nerve-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 129 | 153 | 0.84 |  |
| upscale-x4 | image.upscale | vosr2-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 1654 | 1627 | 1.02 |  |
| upscale-x2 | image.upscale | realplksr-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 581 | 582 | 1.00 |  |
| upscale-x2 | image.upscale | anime4k-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 105 | 112 | 0.94 |  |
| upscale-x2 | image.upscale | heart-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 2015 | 2087 | 0.97 |  |
| upscale-x2 | image.upscale | nacre-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 14521 | 12516 | 1.16 |  |
| upscale-x2 | image.upscale | nerve-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 194 | 193 | 1.01 |  |
| upscale-x2 | image.upscale | vosr2-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 1683 | 1661 | 1.01 |  |
| restore-denoise | image.restore | nafnet-restore | - | 8 | 8/8 | 8/8 | ∞ | 0 | 189 | 189 | 1.00 |  |
| restore-denoise | image.restore | scunet-denoise | - | 7 | 7/7 | 7/7 | ∞ | 0 | 1330 | 1229 | 1.08 |  |
| restore-denoise | image.restore | restormer-denoise | - | 7 | 7/7 | 7/7 | ∞ | 0 | 2865 | 2824 | 1.01 |  |
| restore-denoise | image.restore | drunet-denoise | - | 7 | 7/7 | 7/7 | ∞ | 0 | 378 | 310 | 1.22 |  |
| restore-denoise | reference | (degraded input) | - | 6 | 0/0 | 0/0 | — | — | 0 | 0 | — |  |
| restore-deblur | image.restore | nafnet-restore | - | 8 | 8/8 | 8/8 | ∞ | 0 | 156 | 147 | 1.06 |  |
| restore-deblur | image.restore | restormer-motion | - | 7 | 7/7 | 7/7 | ∞ | 0 | 2855 | 2791 | 1.02 |  |
| restore-deblur | image.restore | restormer-defocus | - | 7 | 7/7 | 7/7 | ∞ | 0 | 2893 | 2770 | 1.04 |  |
| restore-deblur | reference | (degraded input) | - | 6 | 0/0 | 0/0 | — | — | 0 | 0 | — |  |
| generate | image.generate | z-image-turbo | - | 9 | 9/9 | 9/9 | ∞ | 0 | 11364 | 11164 | 1.02 |  |
| generate | image.generate | klein-4b | - | 9 | 9/9 | 9/9 | ∞ | 0 | 7469 | 7180 | 1.04 |  |
| generate | image.generate | klein-4b-base | - | 9 | 9/9 | 9/9 | ∞ | 0 | 72967 | 76641 | 0.95 |  |
| generate | image.generate | qwen-image-flash | - | 9 | 9/9 | 9/9 | ∞ | 0 | 13722 | 13540 | 1.01 |  |
| generate | image.generate | z-image | - | 9 | 9/9 | 9/9 | ∞ | 0 | 68896 | 68988 | 1.00 |  |
| judge | image.score | siglip2-quality | - | 40 | 40/40 | 40/40 | ∞ | 0 | 93 | 99 | 0.94 |  |
| judge | image.describe | mage-vl | - | 40 | 40/40 | 40/40 | ∞ | 0 | 1212 | 1215 | 1.00 |  |

| Operation | Tier | Gaea | Engine | Same |
|---|---|---|---|---|

Only on the engine: upscale-x2|image.upscale|seedvr2-upscale|-, upscale-x4|image.upscale|seedvr2-upscale|-
