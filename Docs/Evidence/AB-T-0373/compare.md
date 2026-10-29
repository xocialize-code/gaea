| Suite | Operation | Model | Tier | Pairs | Same bytes | Same pixels | Worst PSNR (dB) | Max diff | Gaea warm (ms) | Engine warm (ms) | Ratio | Errors |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| tiers | image.generate | klein-4b | draft | 1 | 0/1 | 0/1 | 7.8 | 255 | 5210 | 4445 | 1.17 |  |
| tiers | image.generate | z-image-turbo | standard | 1 | 0/1 | 0/1 | 15.6 | 255 | 4081 | 3674 | 1.11 |  |
| tiers | image.generate | z-image-turbo | best | 1 | 0/1 | 0/1 | 13.0 | 243 | 2631 | 2556 | 1.03 |  |
| tiers | image.edit | klein-4b | draft | 1 | 0/1 | 0/1 | 16.5 | 252 | 2835 | 12431 | 0.23 |  |
| tiers | image.edit | klein-4b | standard | 1 | 0/1 | 0/1 | 17.4 | 253 | 2805 | 12052 | 0.23 |  |
| tiers | image.edit | klein-4b | best | 1 | 0/1 | 0/1 | 15.7 | 253 | 2802 | 12071 | 0.23 |  |
| tiers | image.fill | lama-inpaint | draft | 1 | 1/1 | 1/1 | ∞ | 0 | 505 | 586 | 0.86 |  |
| tiers | image.fill | lama-inpaint | standard | 1 | 1/1 | 1/1 | ∞ | 0 | 214 | 929 | 0.23 |  |
| tiers | image.fill | lama-inpaint | best | 1 | 1/1 | 1/1 | ∞ | 0 | 105 | 113 | 0.93 |  |
| tiers | image.erase | lama-inpaint | draft | 1 | 1/1 | 1/1 | ∞ | 0 | 78 | 78 | 1.00 |  |
| tiers | image.erase | lama-inpaint | standard | 1 | 1/1 | 1/1 | ∞ | 0 | 113 | 115 | 0.98 |  |
| tiers | image.erase | lama-inpaint | best | 0 | 0/0 | 0/0 | — | — | — | — | — | 1: only on Gaea |
| tiers | image.extend | lama-inpaint | draft | 1 | 1/1 | 1/1 | ∞ | 0 | 99 | 99 | 1.00 |  |
| tiers | image.extend | lama-inpaint | standard | 1 | 1/1 | 1/1 | ∞ | 0 | 191 | 198 | 0.96 |  |
| tiers | image.extend | lama-inpaint | best | 1 | 1/1 | 1/1 | ∞ | 0 | 155 | 156 | 0.99 |  |
| tiers | image.upscale | nerve-upscale | draft | 1 | 1/1 | 1/1 | ∞ | 0 | 230 | 880 | 0.26 |  |
| tiers | image.upscale | realplksr-upscale | standard | 1 | 1/1 | 1/1 | ∞ | 0 | 620 | 1283 | 0.48 |  |
| tiers | image.upscale | heart-upscale | best | 1 | 1/1 | 1/1 | ∞ | 0 | 2069 | 3694 | 0.56 |  |
| tiers | image.restore | nafnet-restore | draft | 1 | 1/1 | 1/1 | ∞ | 0 | 100 | 152 | 0.66 |  |
| tiers | image.restore | nafnet-restore | standard | 1 | 1/1 | 1/1 | ∞ | 0 | 86 | 86 | 1.00 |  |
| tiers | image.restore | nafnet-restore | best | 1 | 1/1 | 1/1 | ∞ | 0 | 91 | 84 | 1.08 |  |
| tiers | image.matte | birefnet-matte | - | 1 | 2/2 | 2/2 | ∞ | 0 | 365 | 1350 | 0.27 |  |
| tiers | image.segment | sam21-segment | - | 1 | 1/1 | 1/1 | ∞ | 0 | 70 | 920 | 0.08 |  |
| tiers | image.enhance_prompt | qwen3.5-4b | - | 1 | 0/1 | 0/1 | ∞ | — | 1124 | 1153 | 0.97 |  |
| upscale-x4 | image.upscale | realplksr-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 213 | 211 | 1.01 |  |
| upscale-x4 | image.upscale | heart-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 526 | 530 | 0.99 |  |
| upscale-x4 | image.upscale | nerve-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 130 | 124 | 1.05 |  |
| upscale-x2 | image.upscale | realplksr-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 579 | 572 | 1.01 |  |
| upscale-x2 | image.upscale | heart-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 2022 | 1998 | 1.01 |  |
| upscale-x2 | image.upscale | nerve-upscale | - | 7 | 7/7 | 7/7 | ∞ | 0 | 194 | 188 | 1.03 |  |
| restore-denoise | image.restore | nafnet-restore | - | 8 | 8/8 | 8/8 | ∞ | 0 | 184 | 179 | 1.03 |  |
| restore-denoise | image.restore | scunet-denoise | - | 7 | 7/7 | 7/7 | ∞ | 0 | 1185 | 1152 | 1.03 |  |
| restore-denoise | image.restore | restormer-denoise | - | 7 | 7/7 | 7/7 | ∞ | 0 | 2796 | 2754 | 1.02 |  |
| restore-denoise | reference | (degraded input) | - | 6 | 0/0 | 0/0 | — | — | 0 | 0 | — |  |
| restore-deblur | image.restore | nafnet-restore | - | 8 | 8/8 | 8/8 | ∞ | 0 | 157 | 148 | 1.06 |  |
| restore-deblur | image.restore | restormer-motion | - | 7 | 7/7 | 7/7 | ∞ | 0 | 2786 | 2738 | 1.02 |  |
| restore-deblur | image.restore | restormer-defocus | - | 7 | 7/7 | 7/7 | ∞ | 0 | 2786 | 2736 | 1.02 |  |
| restore-deblur | reference | (degraded input) | - | 6 | 0/0 | 0/0 | — | — | 0 | 0 | — |  |
| segment-1click | image.segment | sam21-segment | - | 51 | 51/51 | 51/51 | ∞ | 0 | 44 | 46 | 0.96 |  |
| segment-1click | image.segment | edgetam-segment | - | 51 | 51/51 | 51/51 | ∞ | 0 | 40 | 42 | 0.95 |  |
| generate | image.generate | z-image-turbo | - | 9 | 9/9 | 9/9 | ∞ | 0 | 11204 | 11029 | 1.02 |  |
| generate | image.generate | klein-4b | - | 9 | 9/9 | 9/9 | ∞ | 0 | 7296 | 7035 | 1.04 |  |
| generate | image.generate | klein-4b-base | - | 9 | 9/9 | 9/9 | ∞ | 0 | 74779 | 76801 | 0.97 |  |
| generate | image.generate | qwen-image-flash | - | 9 | 9/9 | 9/9 | ∞ | 0 | 14109 | 13661 | 1.03 |  |
| generate | image.generate | z-image | - | 9 | 9/9 | 9/9 | ∞ | 0 | 72293 | 69700 | 1.04 |  |
| judge | image.score | ? | - | 0 | 0/0 | 0/0 | — | — | — | — | — | 40: only on Gaea: 404 unknown_operation: No operation image.score on this engine. |
| judge | image.describe | ? | - | 0 | 0/0 | 0/0 | — | — | — | — | — | 40: only on Gaea: 404 unknown_operation: No operation image.describe on this engine. |
| edits | image.edit | klein-4b | draft | 2 | 0/2 | 0/2 | 17.6 | 254 | 13381 | 12363 | 1.08 |  |
| edits | image.edit | klein-4b | best | 2 | 0/2 | 0/2 | 17.5 | 255 | 13383 | 12347 | 1.08 |  |
| edits | image.fill | klein-4b | standard | 2 | 0/2 | 0/2 | 22.8 | 246 | 13380 | 12418 | 1.08 |  |
| edits | image.fill | klein-4b | best | 2 | 0/2 | 0/2 | 24.4 | 233 | 13399 | 12377 | 1.08 |  |
| edits | image.erase | lama-inpaint | standard | 2 | 2/2 | 2/2 | ∞ | 0 | 435 | 428 | 1.02 |  |
| edits | image.erase | lama-inpaint | best | 0 | 0/0 | 0/0 | — | — | — | — | — | 2: only on Gaea |
| edits | image.extend | lama-inpaint | draft | 2 | 2/2 | 2/2 | ∞ | 0 | 252 | 248 | 1.02 |  |
| edits | image.extend | lama-inpaint | standard | 2 | 2/2 | 2/2 | ∞ | 0 | 619 | 597 | 1.04 |  |
| edits | image.extend | lama-inpaint | best | 2 | 2/2 | 2/2 | ∞ | 0 | 619 | 595 | 1.04 |  |
| erase-objd | image.erase | lama-inpaint | draft | 61 | 61/61 | 61/61 | ∞ | 0 | 171 | 167 | 1.02 |  |
| erase-eff | image.erase | lama-inpaint | draft | 43 | 43/43 | 43/43 | ∞ | 0 | 165 | 162 | 1.02 |  |
| erase-objd | image.erase | lama-inpaint | standard | 61 | 61/61 | 61/61 | ∞ | 0 | 402 | 388 | 1.04 |  |
| erase-eff | image.erase | lama-inpaint | standard | 43 | 43/43 | 43/43 | ∞ | 0 | 398 | 386 | 1.03 |  |

| Operation | Tier | Gaea | Engine | Same |
|---|---|---|---|---|
| image.colorize | best | — | ddcolor-colorize | **no** |
| image.colorize | draft | — | ddcolor-colorize | **no** |
| image.colorize | standard | — | ddcolor-colorize | **no** |
| image.describe | default | — | mage-vl | **no** |
| image.edit | best | klein-4b | klein-4b | yes |
| image.edit | draft | klein-4b | klein-4b | yes |
| image.edit | standard | klein-4b | klein-4b | yes |
| image.enhance_prompt | default | qwen3.5-4b | qwen3.5-4b | yes |
| image.erase | best | lama-inpaint | mage-flow-edit-turbo | **no** |
| image.erase | draft | lama-inpaint | lama-inpaint | yes |
| image.erase | standard | lama-inpaint | lama-inpaint | yes |
| image.extend | best | lama-inpaint | lama-inpaint | yes |
| image.extend | draft | lama-inpaint | lama-inpaint | yes |
| image.extend | standard | lama-inpaint | lama-inpaint | yes |
| image.fill | best | lama-inpaint, klein-4b | lama-inpaint, klein-4b | yes |
| image.fill | draft | lama-inpaint | lama-inpaint | yes |
| image.fill | standard | lama-inpaint, klein-4b | lama-inpaint, klein-4b | yes |
| image.generate | best | z-image-turbo | z-image-turbo | yes |
| image.generate | draft | klein-4b | klein-4b | yes |
| image.generate | standard | z-image-turbo | z-image-turbo | yes |
| image.matte | default | birefnet-matte | birefnet-matte | yes |
| image.relight | best | — | cidnet-relight | **no** |
| image.relight | draft | — | cidnet-relight | **no** |
| image.relight | standard | — | cidnet-relight | **no** |
| image.restore | best | nafnet-restore | nafnet-restore | yes |
| image.restore | draft | nafnet-restore | nafnet-restore | yes |
| image.restore | standard | nafnet-restore | nafnet-restore | yes |
| image.score | default | — | siglip2-quality | **no** |
| image.segment | default | sam21-segment | sam21-segment | yes |
| image.upscale | best | heart-upscale | heart-upscale | yes |
| image.upscale | draft | nerve-upscale | nerve-upscale | yes |
| image.upscale | standard | realplksr-upscale | realplksr-upscale | yes |

Only on the engine: edits|image.erase|mage-flow-edit-turbo|best, judge|image.describe|mage-vl|-, judge|image.score|siglip2-quality|-, restore-denoise|image.restore|drunet-denoise|-, tiers|image.colorize|ddcolor-colorize|best, tiers|image.colorize|ddcolor-colorize|draft, tiers|image.colorize|ddcolor-colorize|standard, tiers|image.describe|mage-vl|-, tiers|image.erase|mage-flow-edit-turbo|best, tiers|image.relight|cidnet-relight|best, tiers|image.relight|cidnet-relight|draft, tiers|image.relight|cidnet-relight|standard, tiers|image.score|siglip2-quality|-, upscale-x2|image.upscale|anime4k-upscale|-, upscale-x2|image.upscale|nacre-upscale|-, upscale-x2|image.upscale|seedvr2-upscale|-, upscale-x2|image.upscale|vosr2-upscale|-, upscale-x4|image.upscale|anime4k-upscale|-, upscale-x4|image.upscale|nacre-upscale|-, upscale-x4|image.upscale|seedvr2-upscale|-, upscale-x4|image.upscale|vosr2-upscale|-
