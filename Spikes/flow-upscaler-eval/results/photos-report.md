## Calibration (rebuilt set vs stored)

- input IQA: 12 images, largest difference 5.96e-08
- input word-F1 per text image (rebuilt, stored): [(0.8461538461538461, 0.6666666666666666), (0.8, 0.5333333333333333), (0.5217391304347826, 0.5573770491803278), (0.75, 0.75), (1.0, 1.0)]
- input-bicubic ArcFace (rebuilt, stored): [('input-bicubic|x2|face-man', 0.9931, 0.9925), ('input-bicubic|x2|face-woman', 0.9939, 0.9931), ('input-bicubic|x2|group', 0.9173, 0.9204), ('input-bicubic|x2|poster', 0.993, 0.9917), ('input-bicubic|x2|zt-reader', 1.0, 1.0), ('input-bicubic|x4|face-man', 0.9883, 0.9881), ('input-bicubic|x4|face-woman', 0.989, 0.9892), ('input-bicubic|x4|group', 0.8873, 0.8906), ('input-bicubic|x4|poster', 0.9763, 0.9789), ('input-bicubic|x4|zt-reader', 1.0, 1.0)]


### ×2

| Arm | DISTS vs GT ↓ | LPIPS vs GT ↓ | SigLIP2 IQA ↑ (GT = 0.891) | ArcFace ↑ (min) | word-F1 (text set) | CORRUPTED / FIXED / INVENTED |
|---|---|---|---|---|---|---|
| Precision: RealPLKSR (stored) | 0.078 | 0.136 | 0.879 | 0.980 (0.800) | 0.747 | 9 / 27 / 21 |
| Realistic: VOSR2 (stored) | 0.115 | 0.189 | 0.905 | 0.959 (0.770) | 0.674 | 11 / 21 / 26 |
| Nacre v1 (stored) | 0.102 | 0.163 | 0.894 | 0.961 (0.743) | 0.646 | 8 / 12 / 34 |
| **FlowUpscaler** (exact FLUX.2 VAE decode) | 0.075 | 0.162 | 0.883 | 0.967 (0.839) | 0.628 | 20 / 3 / 21 |
| FlowUpscaler, diffusers tiled decode (seams) | 0.089 | 0.176 | 0.880 | 0.962 (0.828) | 0.674 | 15 / 4 / 17 |
| Lanczos (floor) | 0.074 | 0.244 | 0.876 | 0.980 (0.814) | 0.715 | 10 / 7 / 26 |

### ×4

| Arm | DISTS vs GT ↓ | LPIPS vs GT ↓ | SigLIP2 IQA ↑ (GT = 0.876) | ArcFace ↑ (min) | word-F1 (text set) | CORRUPTED / FIXED / INVENTED |
|---|---|---|---|---|---|---|
| Precision: RealPLKSR (stored) | 0.158 | 0.190 | 0.853 | 0.972 (0.839) | 0.829 | 5 / 9 / 16 |
| Realistic: VOSR2 (stored) | 0.165 | 0.234 | 0.904 | 0.955 (0.640) | 0.798 | 8 / 12 / 31 |
| Nacre v1 (stored) | 0.163 | 0.236 | 0.870 | 0.952 (0.701) | 0.587 | 11 / 6 / 40 |
| **FlowUpscaler** (exact FLUX.2 VAE decode) | 0.170 | 0.230 | 0.872 | 0.952 (0.778) | 0.710 | 18 / 3 / 20 |
| FlowUpscaler, diffusers tiled decode (seams) | 0.200 | 0.268 | 0.870 | 0.933 (0.780) | 0.643 | 17 / 3 / 24 |
| Lanczos (floor) | 0.188 | 0.358 | 0.859 | 0.969 (0.758) | 0.813 | 11 / 4 / 12 |

### Per image, DISTS vs GT (×2 / ×4)

| Image | RealPLKSR | VOSR2 | FlowUpscaler | Lanczos |
|---|---|---|---|---|
| boat | 0.067 / 0.129 | 0.096 / 0.132 | 0.075 / 0.156 | 0.071 / 0.190 |
| face-man | 0.094 / 0.180 | 0.123 / 0.194 | 0.091 / 0.193 | 0.085 / 0.201 |
| face-woman | 0.087 / 0.098 | 0.102 / 0.090 | 0.059 / 0.112 | 0.052 / 0.103 |
| group | 0.070 / 0.158 | 0.098 / 0.201 | 0.060 / 0.161 | 0.046 / 0.170 |
| kiosk | 0.062 / 0.143 | 0.067 / 0.135 | 0.062 / 0.148 | 0.061 / 0.176 |
| painting | 0.107 / 0.288 | 0.223 / 0.194 | 0.085 / 0.268 | 0.135 / 0.314 |
| poster | 0.079 / 0.161 | 0.143 / 0.227 | 0.082 / 0.162 | 0.077 / 0.187 |
| sign-forge | 0.066 / 0.137 | 0.082 / 0.126 | 0.072 / 0.150 | 0.076 / 0.183 |
| stamp | 0.074 / 0.132 | 0.097 / 0.189 | 0.085 / 0.175 | 0.060 / 0.167 |
