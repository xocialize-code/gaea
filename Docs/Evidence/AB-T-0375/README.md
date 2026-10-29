# AB-T-0375: G1 exit

| | |
|---|---|
| **Date** | 2026-10-29 |
| **Gaea** | The code at 0836429 (Gaea 0.7.1). The binary reports 0.7.0: it was built from that code just before the version string moved to 0.7.1, with no other change between them |
| **Plugins** | Every G1 plugin from its GitHub release: z-image 0.1.0, flux2-klein 0.2.1, qwen-image 0.2.0, forge 0.2.0, prompt-enhance 0.1.0, mage-vl 0.1.0 (and the demo 0.3.0) |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |

## The exit tests

| Exit test | Result | Receipts and evidence |
|---|---|---|
| **The Image conformance suite** | **Pass.** Open: 40 passed, 0 failed, 4 skipped (paired-mode tests and BASE-071, which needs a short outputs TTL). Paired: 43 passed, 0 failed, 1 skipped (BASE-071). Base 0.1 and Image 0.1 conform, with every G1 plugin, adapters included (BASE-013, BASE-029, IMAGE-013) | [conformance-open](conformance-open/report.md), [conformance-paired](conformance-paired/report.md); AB-R-0653 (0.7.0), AB-R-0649 (0.6.0) |
| **TierBench parity** with pixel-agency-image-engine v0.9.1 | **Pass.** Every seeded output byte-identical, warm medians 0.95–1.08 with every exceedance named (0.5.0). The coverage parity found missing: 278/278 (0.6.0). Adapters: 34/34 byte-identical (0.7.0). An edit on a large input: 8/8, and Qwen Edit (c2dd23e) | AB-R-0645 ([AB-T-0373](../AB-T-0373/README.md)), AB-R-0649 ([AB-T-0377](../AB-T-0377/README.md)), AB-R-0653 ([AB-T-0378](../AB-T-0378/README.md)), AB-R-0654 ([AB-T-0383](../AB-T-0383/README.md)) |
| **Gaea Lab against Gaea** | **Pass.** App → Gaea → model → LoRA; the MES client conformance suite passes 11 of 11 against `lab-run`, in place of Lite | AB-R-0655 ([AB-T-0372](../AB-T-0372/README.md)) |
| **Pixel Agency Desktop against Gaea** | **Pass.** Desktop's own `TicketRunner` (PixelAgencyCore at acdb2aa, linked unchanged by [desktop-gaea-check](desktop-gaea-check)) over two real Gaea servers: scaling ×2 (the picker's choice) and ×4 on NERVE went to the server with the upscalers, the only one onboarding's Gaea step lists; generate on Z-Image Turbo went to that server, and on Qwen-Image Flash to the other. 4 of 4 completed with their outputs in the library | [desktop-against-gaea.txt](desktop-against-gaea.txt); the receipt for this run |
| **Two servers, each job routed** | **Pass.** Six jobs over two Gaea servers with different plugins, each to the only server that could run it; Desktop's run above is a second client doing the same | AB-R-0655 ([AB-T-0372/two-servers.log](../AB-T-0372/two-servers.log)) |

AB-T-0358 to AB-T-0362 (G-20) are done: ImageLibrary in pixel-agency-library, the normalizer published, the run workflow
in pixel-agency-run, Lite not on the Mac App Store, and Desktop sending scaling to Gaea through the engine picker.

## Not covered

- **Desktop as the sandboxed app.** The check links Desktop's PixelAgencyCore unchanged, but runs outside the app's
  sandbox and without its built-in ForgeCore engine, so every operation went to Gaea. With the built-in engine, Desktop
  keeps everything but scaling on it (D-20); its own tests cover that path.
- **Two Macs.** Both servers ran on this Mac (see AB-T-0372).

## Left open, not on the exit path

- AB-T-0382: plugin CI builds no metallib, so plugins release locally with the notary profile.
- AB-T-0380: the wired limit in workers.
