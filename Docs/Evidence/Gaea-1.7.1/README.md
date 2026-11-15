# Gaea 1.7.1: fill, extend and erase only where the server can finish them (AB-A-0267)

PixelAgencyEditor found that a Gaea with only Z-Image listed `z-image` and `z-image-turbo` on `image.fill` and
`image.extend`, and every such job failed with `model_unavailable`, "No plugin model offers image.fill".

## The cause

The report guessed the request's model wasn't passed to the fill route. It was. A reproduction on Gaea 1.5.0 with
Z-Image 0.2.0 showed two `image.edit` runs on the named model, then the failure:

1. The image normalizer offers every edit model on fill, extend and erase. It shows the model the region in magenta and
   tells it what to paint there.
2. Z-Image's edit re-generates the whole picture at a strength. It can't paint a marked region, so its result was
   rejected twice.
3. The normalizer then fell back to the server's default inpainter (LaMa, in gaea-plugin-forge), which wasn't installed.
   That lookup, with no model named, produced the message.

`image.extend` uses the inpainter even when the edit model succeeds, to bridge the seam, so without one it can never
finish.

## The fix

- **Gaea 1.7.1:**
  - an `image.edit` offer can say `supports.image_to_image` (GPP-1 §4.3), and such a model isn't offered on fill,
    extend or erase (`GaeaEngine.finishable`);
  - `image.extend` is offered only with a default inpainter enabled;
  - the fallback's error names the inpainting model and gaea-plugin-forge.
- **gaea-plugin-z-image 0.2.1:** both `image.edit` offers carry the key. Nothing else changes.

## Results

Run on a Mac Studio (M5 Max, 128 GB, macOS 27.3) with a Release build of 1.7.1 and the plugins from GitHub.

- **Unit tests:** 113/113 (`FillOfferTests` adds 4).
- **Acceptance** ([acceptance-fill-offers.log](acceptance-fill-offers.log), `tools/acceptance-fill-offers.sh`): 20/20.
  - Only Z-Image 0.2.1: fill, extend and erase aren't offered; a fill naming `z-image-turbo` is refused when it
    arrives; `image.edit` by name still runs.
  - Only Z-Image 0.2.0 (no key): extend isn't offered; fill still lists it, and the job's failure now says the
    inpainting model is missing and comes with gaea-plugin-forge.
  - Z-Image 0.2.1, Klein and Forge: fill and extend offer LaMa and Klein, not Z-Image; a fill by Klein changes only the
    masked area; an extend by Klein is 1024×512 and keeps the original's pixels; a fill naming `z-image-turbo` is
    refused when it arrives.
- **Conformance with the image plugins** ([conformance.md](conformance.md)): 43 passed, 0 failed, 73 skipped (no audio,
  video or mesh plugin installed). Base and Image conform.

## Not covered

- The extend in the acceptance came back with `model_fallback`: on the synthetic gradient Klein left the new area
  unpainted and LaMa filled it. So the seam-bridging path after a successful paint wasn't exercised here.
- `image.erase`: no plugin set in the run offered it, so only its absence was checked.
- PixelAgencyEditor's own live test (`PA_MES_LIVE_FILL=1`) wasn't run from here.
