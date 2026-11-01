# AB-T-0412: a guide for plugin authors (G4 order 4, DST-4)

**Done:** a fresh session, given only the guide, made a plugin and released it from CI. Gaea 0.13.0, with its own team
treated as unknown, held the plugin; the operator approved it; and it ran.

The guide is [AUTHORING.md](https://github.com/xocialize-code/gaea-plugin-demo/blob/main/AUTHORING.md) in the template
repo. Gaea's new [README](../../../README.md) links it.

## What had to change first

The template and the kit could only make plugins signed by Gaea's own team:
- the kit's manifest builder refused any other team;
- `gaea-plugin-check` pinned CFZS6RXUCP;
- the template's scripts and CI hard-coded it.

That was right for v1 (G-22) but blocks a third-party author. AB-T-0411's trust list makes another team usable, so:
- **GaeaPluginKit 0.10.0** ([bf50773](https://github.com/xocialize-code/gaea-plugin-kit/commit/bf50773)):
  - the manifest builder accepts any Apple Team ID (`GPP.isTeamID`) and refuses anything else;
  - `gaea-plugin-check` verifies and launches against the manifest's team, and `--team` asserts which;
  - `hello.kit.version` is now right (it still said 0.8.0).
- **The template** ([c5ca4eb](https://github.com/xocialize-code/gaea-plugin-demo/commit/c5ca4eb),
  [c05e7fc](https://github.com/xocialize-code/gaea-plugin-demo/commit/c05e7fc)):
  - `build-plugin.sh` signs with the keychain identity whose team the manifest names. This Mac also holds another
    team's certificate, and the build picked the right one.
  - CI notarizes for the imported certificate's team.
  - `check-plugin.sh` has one block an author edits: the job, the expected output and the control.
  - The release notes say what was checked where. A GPU-less runner checks the launch and the `hello` only.
  - The pointers lead to the guide.
  - The template requires the kit from 0.10.0.

## The cold run

A fresh agent got the guide, the machine's facts (our Developer ID, the org's secrets, a downloaded Gaea 0.13.0 run
with `GAEA_UNTRUST_OWN_TEAM=1`) and the Done criteria, nothing else. It made **Ripple**: one `.custom` model that draws
wave interference on the GPU with MLX, with one option, `x-ripple.sources`, and no weights.

| Done item | Result |
|---|---|
| Builds and passes `scripts/check-plugin.sh` with its own job | Passed: 2048×2048, 12 sources, `Device(gpu, 0)`, the session validated, and the control couldn't load the metallib outside the bundle ([check-image-0.png](check-image-0.png), [session.gpp](session.gpp)). |
| A `v0.1.0` tag releases from CI, notarized | Run 41363506248 passed in 3m23s: notarization Accepted, stapled, `source=Notarized Developer ID` ([ci-excerpt.log](ci-excerpt.log)). The release has the zip, its `.sha256` and `manifest.json`, and isn't a pre-release. The repo was private, `xocialize-code/gaea-plugin-guide-test`, and is now archived. |
| `gaea plugins add` holds it | `Held h-7b11f629: Ripple 0.1.0 …`, with the certificate, team, "Notarized: yes", the repo and the models ([hold.txt](hold.txt)) |
| `gaea trust approve` installs it | `Trusted its team. Installed Ripple 0.1.0 (com.xocialize.gaea.guide-test), enabled.` |
| An MES job runs and its PNG is fetched | `succeeded` on Ripple 0.1.0, lane fp32, `x-ripple.sources: 8` ([job2.json](job2.json), [job2-image-0.png](job2-image-0.png)) |

The run took about an hour.

## What the run found, and what changed

The run reported 13 problems. Each is fixed in AUTHORING.md or the template (c05e7fc). Four mattered most:
- **How a client sends an `x-` option.** It goes under the request's top-level `extensions`, and
  `GET /mes/v0/operations` shows them. In `params` it's refused, and a top-level `model_params` was accepted and
  silently dropped ([job1-submit-model_params-ignored.json](job1-submit-model_params-ignored.json)). That last one is
  an MES server bug, filed as **AB-A-0245** to mlx-apps.
- **Custom models and surfaces.** "A `.custom` model with no surfaces can still be offered" was wrong. An offered
  model needs a surface whose capability backs its operation (GPP-1 §4.7).
- **Limits.** These are snapped as well as refused. A size off `sizeMultiple` is snapped by Gaea, with a
  `size_snapped` warning, before the worker sees it. Past `maxPixels` is refused.
- **The first tag on a new repo.** A tag pushed in the same push as the workflow file started no run. The guide now
  says to push `main` first, and how to start the run by hand.

The smaller ones:
- where to clone the spec repo;
- creating the GitHub repo;
- template leftovers;
- the naming rules;
- the card's allowed values;
- the `internal` error code;
- lane names and a weightless configuration;
- what the measured peak counts;
- the check block's flags (no `--help`, `--model-params`);
- a `CHECK_EXPECT` that can match the request's own text;
- an image `CONTROL_RUN`;
- `notarytool` prompting for the password;
- release notes that claimed a GPU job CI never ran;
- re-encoded outputs.

## Left

- **AB-A-0245** (mlx-apps): refuse unknown top-level job fields.
- **A plugin signed by a real second team** is still the 1.0 exit's test (G-25).
