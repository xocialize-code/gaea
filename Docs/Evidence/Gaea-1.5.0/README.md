# Gaea 1.5.0: operator controls

Controls for keeping a server to quick work, asked for on 2026-11-09 for a preview server that has to keep up with many
requests: per-model caps (`gaea models limit`), lanes switched off (`gaea models lanes`), and a saved budget that
applies live (`gaea budget`).

**Unit tests:** 100/100 (`OperatorControlsTests`).

**Acceptance** ([acceptance-controls.log](acceptance-controls.log), `tools/acceptance-controls.sh`): 28/28. It ran on a
Mac Studio M5 Max with 128 GB, with FLUX.2 Klein 0.3.0, Z-Image 0.1.2 and TRELLIS.2 0.1.0 installed from GitHub.

- **The budget:** read, set to 50 GB (TRELLIS.2's 1024 and 1536 stop being offered, `gaea status` says who set it), kept
  across a restart, and back to the default.
- **Lanes:** with Z-Image Turbo's default lane (int4) off, a job runs on int8 and a request naming int4 is refused; with
  every lane off, the model isn't offered.
- **Caps:**
  - Klein 4B at 4.2 MP: its offer says so, a 1024² job runs, a 4096² request naming it is refused at submit, and an
    unnamed 4096² request goes to a model it fits;
  - TRELLIS.2 512 at 5,000 faces: a request for 20,000 is refused, and one that doesn't ask is made under 5,000 with
    `faces_reduced`;
  - an unknown cap is refused, caps and lanes survive a restart, `gaea models` shows them, and removing them restores
    the plugins' limits.

**What the first run found:** image model offers carried no per-model limits, so MESKit and the normalizer checked only
the operation's largest. A capped Klein took a 4096² job. Gaea now puts each capped model's limits in the descriptor,
refuses a named request past them at submit, and steers an unnamed one to a model it fits.

**Not covered:**
- A video or audio cap end to end. The same code narrows their offers, but no LTX or speech job ran here.
- A video offer whose default duration is above a cap: only mesh defaults are reduced to a cap.
