# AB-T-0372: Gaea Lab, the reference MES client

| | |
|---|---|
| **Date** | 2026-10-29 |
| **Gaea Lab** | 0.1.0, `dist/Gaea Lab.app` (`scripts/build-lab.sh`): Release, Developer ID with the hardened runtime, notarized (submission 4750ae46-…) and stapled; Gatekeeper `accepted, source=Notarized Developer ID`. Every run below used the notarized app's own `lab-run` or binary |
| **Built on** | pixel-agency-run 0.1.0 (PixelAgencyRun, PixelAgencyRunUI: Lite's workflow, AB-T-0360), MESKit 0.5.0 (MESClientKit's `EnginePicker`, MESFormsUI), DesignScaffold |
| **Servers** | Gaea 0.7.1 (this change), two installs on this Mac, each advertised over Bonjour: **A** on port 17791 with Z-Image 0.1.0 and the forge pack 0.2.0; **B** on 17792 with Qwen-Image 0.2.0 and FLUX.2 Klein 0.2.1, `qwen-image:martha` switched on |
| **Machine** | Mac17,14 (Apple M5 Max, 128 GB), macOS 27.2 |

## What it is

`Apps/GaeaLab`, a package of its own so Gaea's host doesn't link its UI:

- **`EnginePool`** (GaeaLabCore): every usable server as one `EngineConnection`. Its operations are the servers'
  together, each with every model any of them offers. A job goes where MESClientKit's `EnginePicker` sends it (a server
  that offers the operation, model and adapters, preferring the model resident and a short queue), and everything after
  the submit follows it there. Uploads wait for the choice: `upload` keeps the file, `submit` sends it to the chosen
  server first.
- **`AdapterChoices`**: the run's LoRAs. MESFormsUI renders a descriptor's params and extensions but not its adapters,
  so Lab keeps them and the pool puts them on a request that names none.
- **The app**: Lite's window (`RunWorkflowView`) with "Every server" as one more engine, the servers Bonjour finds, and
  a LoRA panel showing where the run went.
- **`lab-run`**: the same workflow without a window, in `Contents/Helpers`.

## Result

| Done = | Result |
|---|---|
| Lab runs App → SPM → Gaea → model → LoRA for image | **Pass.** The app, on "Every server", ran Qwen-Image Flash with `qwen-image:martha` at 0.8 on server B ([app/lab-before-light.png](app/lab-before-light.png), [app/lab-after-light.png](app/lab-after-light.png), and dark). `lab-run` does the same ([two-servers.log](two-servers.log), jobs 2 and 3); provenance lists the adapter at revision a60485ca… |
| With two Gaea servers that have different plugins, each job reaches the server with its model (G-19), in a recorded run | **Pass, 6 of 6** ([two-servers.log](two-servers.log), [two-servers/](two-servers)) |
| The MES client conformance suite runs against Lab in place of Lite | **Pass: 11 of 11** CLIENT tests, Base 0.1 (client) conforms ([client-conformance/client-report.md](client-conformance/client-report.md)), with `mes-conformance client --command "lab-run --engine {url} --operation image.generate --text prompt={prompt} --out {out}"` |

### The recorded run

`tools/lab-two-servers.sh` gives `lab-run` both servers and six jobs, each needing something only one has:

| Job | Needs | Ran on | Model |
|---|---|---|---|
| Generate on Z-Image Turbo | Z-Image | A (17791) | z-image-turbo |
| Generate on Flash with `qwen-image:martha` 0.8 | Qwen-Image | B (17792) | qwen-image-flash, the adapter in provenance |
| Generate with only the adapter named | the adapter's model (Base §6.3 rule 2) | B | qwen-image-flash |
| Upscale ×2 | the forge pack | A | realplksr-upscale |
| Edit on Klein 4B | Klein | B | klein-4b |
| Score | the forge pack (SigLIP2) | A | siglip2-quality |

## Found on the way, fixed in Gaea 0.7.1

**Two Gaea servers on one Mac had the same MES engine id**, `eng_gaea_<mac>`, so the pool sent the second server's job
lookups to the first ("No job …"). An id is now kept per install in gaea.sqlite (`engine.id`): a new install takes
the Mac's name and a random suffix; an install that existed keeps `eng_gaea_<mac>`, which its clients paired with.
`lab-run` also tells two servers with one id apart by address.

## Not covered

- **Two Macs.** Both servers ran on this Mac, advertised over Bonjour. The pool routes by engine id and URL, so nothing
  in it depends on that, but no second Mac was used.
- **Discovery in the window.** The snapshot added both servers by address (`--engine`). The app browses Bonjour too,
  which this run didn't exercise.
- **Paired servers in `lab-run`.** It takes open-mode URLs; the app pairs through Lite's flow.
