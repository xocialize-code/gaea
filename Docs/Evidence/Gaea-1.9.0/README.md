# Gaea 1.9.0: `image.locate`, and a subject on `image.matte`

2026-11-15, Mac Studio (Mac17,14, M5 Max, 128 GB, macOS 27.3). A Release build of Gaea 1.9.0 (`bd3a158`), run headless
on throwaway homes and ports; mes-conformance from media-engine-spec v0.15.0.

mlx-3d asked for two things HairDeck's head crop needs (AB-A-0278, AB-A-0279): a box round something named in words,
and a matte of one subject. Both became MES surfaces in media-engine-spec 0.15.0 (RFCs 0010 and 0011, mlx-apps'
AB-A-0291 and AB-A-0292), and Gaea serves both from 1.9.0 (AB-T-0483, AB-T-0491).

## What changed

- **Gaea 1.9.0:** on media-engine-spec 0.15.0, pixel-agency-normalizer 0.4.0 and mlx-engine-swift 0.80.0 (contract
  1.65.0).
  - **`image.locate`.** The image normalizer has no table entry for it, so Gaea serves it from MESKit's table with each
    plugin offer run as itself (`Sources/GaeaCore/Engine/GaeaImage.swift`), as audio, video and mesh offers are. The
    worker gets the picture upright and `count`; MESKit keeps each box inside the picture, sorts by score and cuts the
    list to `count` (GPP-1 §3.3.5).
  - **`image.matte` with a `subject`.** The normalizer does the step: the segmenter's mask of the box or points times
    the matte. It is offered only while a segmenter is enabled beside the matting model.
- **GaeaPluginKit 0.15.0** (`05f67b9`): on the same engine.
- **gaea-plugin-demo 0.6.0** (`6c8d5ae`, needs Gaea 1.9.0): `demo-locate`, a stand-in that boxes the shapes standing
  out from the border colour, so the suite's locate cases run without weights.
- **gaea-plugin-locate 0.1.0** (`c17cea6`, new, needs Gaea 1.9.0): Qwen3-VL-4B-Instruct (Apache-2.0) on mlx-image's
  mlx-locate-swift 0.1.0 (AB-A-0293). One model, `qwen3-vl-locate`, the default on `image.locate`; lanes `int8`
  (8.0 GB) and `int4` (5.95 GB); at most 16 boxes; no seed.

## Results

| Run | Result | Log |
|---|---|---|
| Gaea unit tests | 116 passed | |
| Locate plugin: `scripts/golden.sh`, the signed bundle over GPP against `locate-inproc` | 8 passed, 0 failed | [golden-locate.log](golden-locate.log) |
| Locate acceptance, the plugin's local build through a stand-in | 13 passed, 0 failed | [acceptance-locate-standin.log](acceptance-locate-standin.log) |
| Locate acceptance, the plugin's 0.1.0 release from GitHub (notarized) | 13 passed, 0 failed | [acceptance-locate-github.log](acceptance-locate-github.log) |
| Locate acceptance through the released app: `Gaea-1.9.0.zip` from GitHub (sha256 `565345fd…0c55f136`, Gatekeeper: Notarized Developer ID), the plugin from GitHub | 13 passed, 0 failed | [acceptance-locate-released.log](acceptance-locate-released.log) |
| Matte subject acceptance, the Forge pack 0.2.1 from GitHub | 15 passed, 0 failed | [acceptance-matte-subject.log](acceptance-matte-subject.log) |
| Conformance IMAGE-020 and IMAGE-021 with the Forge pack alone | 2 passed, 0 failed | [conformance-matte.md](conformance-matte.md) |
| Conformance with all 30 published plugins from GitHub and the 7 opt-in models | 112 passed, 0 failed, 9 skipped: Base, Image, Audio, Video and Mesh 0.1 conform | [conformance-all.md](conformance-all.md), [conformance-plugins.txt](conformance-plugins.txt) |

The conformance run includes the cases new in 0.15.0: IMAGE-017 to 019 (locate), IMAGE-020 and 021 (matte's subject)
and BASE-021 (a top-level member Base doesn't define is 400). The 9 skips are the usual ones: paired mode (4), expiry
waits (2), no Video offer with previews (1), and no `mesh.rig` offer (2). The run used `JOB_TIMEOUT=900`.

## Locate through Gaea

What `tools/acceptance-locate.sh` shows:

- **The offer.** `image.locate` takes an image and a prompt and returns `boxes`, with `qwen3-vl-locate` as its
  default: Apache-2.0, at most 16 boxes, no seed.
- **The fox.** One box over the fox, labelled with the prompt and scored. The boxes are `locate-inproc`'s, number for
  number.
- **Count.** "The fox's ears" with `count` 4 gives two boxes, best first.
- **Nothing found.** "A bicycle" succeeds with an empty list and the warning `nothing_found`.
- **Orientation.** A JPEG turned by its orientation tag gives the upright picture's box.
- **Lanes.** `int4`, named, runs on `int4`.
- **Refusals.** No prompt is 400; `count` 17 is 422 `out_of_limits`.

The yardstick is mlx-3d's 12 illustrations for HairDeck's head crop, against SAM 3's boxes (AB-R-0879). Through Gaea
on the `int8` lane:

| Measure | Result |
|---|---|
| Hair box IoU, median | 0.917 |
| Face box IoU, median | 0.750 |
| Head crop IoU, median | 0.939 |
| Head crop within tolerance | 12 of 12 |
| Time per query, warm, median | 0.64 s |

These are mlx-image's in-process numbers (0.917, 0.750, 12 of 12, 0.63 s). "Within tolerance" is the range in which a
different head crop changes HairDeck's hair less than another seed does (AB-R-0851).

## A subject on matte

What `tools/acceptance-matte-subject.sh` shows, with BiRefNet as the matting model and SAM 2.1 (hiera-small) as the
segmenter, both from the Forge pack:

- **Without a subject nothing changes:** no `subject` in `effective`, no segmenter in the provenance.
- **Points.** On a picture of two discs, points on the left disc give a mask over that disc and none over the right
  one. The plain matte covers both.
- **A box.** On a photo of a cup beside a book, a box round the cup gives the cup and not the book.
- **What ran.** `effective.subject` echoes the subject, and the segmenter is a helper with the role `subject`.
- **Refusals.** Both forms at once, a box outside the picture, and points without an include are 400.
- **No segmenter.** With both segmenters disabled the offers list no `supports.subject`, a subject is refused (422),
  and a plain matte still runs.

### What it does on hard pictures

mlx-3d's two hard illustrations, where a plain matte fails. IoU against the reference character mask:

| Picture | Plain matte | Box round the character | One click on the character |
|---|---|---|---|
| ex09 (the character small in a busy frame) | 0.203 | 0.545 | 0.066 |
| ex10 (the character fills the frame) | 0.579 | 0.198 | 0.010 |

- **A box helps where the matte keeps too much** (ex09), and hurts where the matte was mostly right (ex10): SAM 2.1's
  mask of the box is ragged there, and the product loses the character.
- **One click picks a small part** (a strand of hair, a hand), so the product is nearly empty. A click needs more
  points, or a box.
- **A box on the two-disc test picture gives an empty mask.** SAM 2.1 scores it 0.005. The same form works on photos
  and on the suite's IMAGE-020 picture. Reported to mlx-image; the acceptance records it and doesn't judge it.

The strip of these masks is kept outside the repo (the illustrations aren't ours to publish):
`/Volumes/DEV_VOL1/Evidence/matte-subject/hard-strip.png`.

## Not covered

- **The matte subject and conformance through the released app.** They ran on the local Release build of `bd3a158`;
  the released app (`9162a0c`, the same sources) ran the locate acceptance.
- **Memory.** The locate worker's peak wasn't measured here. The charges are mlx-locate-swift's declared footprints.
- **Crowded or small things.** The model reads pictures at up to 1024 px on the long side; nothing here tests what it
  misses.
- **EdgeTAM as the segmenter.** The normalizer prefers SAM 2.1 when both are enabled, and every subject run used it.
- **Gaea Lab.** It wasn't run against either surface.
