# Gaea

Gaea is a media server for the Mac. It serves the Media Engine Spec (MES) Image, Audio, Video and Mesh (3D) profiles,
and its models come as plugins:
- each plugin is a signed `.gaeaplugin` bundle that Gaea installs from a GitHub repo and runs in a process of its own;
- Gaea does the MES front end, the queue, memory across processes, the plugins' lifecycle and the UI;
- the plugins do the generating.

> [!IMPORTANT]
> **Gaea is alpha software in active development.** Releases can still change how it behaves, so try it before you
> build on it, and read each release's notes before you update.

## Install

Download `Gaea-<version>.zip` from [Releases](https://github.com/xocialize-code/gaea/releases), unzip it, and move
`Gaea.app` to Applications. It needs macOS 26 on Apple silicon, and it updates itself from these releases
(`gaea update`, or Settings → Updates). The command-line tool is `Gaea.app/Contents/Helpers/gaea`.

## Running a server

This is the operator's guide: one Mac running Gaea for the MES clients on it or on its network.

### Starting it

- **As an app:** open `Gaea.app`. It lives in the menu bar, and its console has the Plugins, Models and System pages.
  Settings has the models root (General), adapters and updates.
- **Headless,** for a studio Mac with no one at it: `Gaea.app/Contents/MacOS/Gaea --headless`. Start it at login
  with a launch agent; an update relaunches it headless, on the same port and folder.
- **Where clients find it:** MES on port 17630 (`--port`), advertised over Bonjour (`--no-advertise` stops that).
  - Open, the default, it listens on this Mac only.
  - `--paired` serves the network over TLS (`--host` picks the address). Each client pairs once: the app asks you, and
    a headless server with `--approve-pairings` approves every pairing, which is only for a network you trust.
- **How it's configured:** MES clients can't configure Gaea. You configure it in its console, Settings, and with
  `gaea`, which talks to the running server over a socket on this Mac only (G-17).
- **Its folder** is `~/Library/Application Support/Gaea`: `gaea.sqlite` (plugins, models, trust, crashes and
  settings), `Plugins/`, `Held/`, `Updates/`, `Crashes/` and logs. `GAEA_HOME` moves it; keep that path short, because
  the socket's path is at most 103 bytes.
- **What it's doing:** `gaea status` gives the server, plugins, workers, memory and crashes; `gaea logs` is Gaea's own
  log.

### Plugins

Every model is a plugin's. A plugin is a signed bundle from a GitHub repo, and each one runs in a process of its own.

- **Adding one:** `gaea plugins add https://github.com/xocialize-code/gaea-plugin-z-image` installs the newest full
  release (or `… <version>`) and turns it on. The plugins listed in this repo's
  [CLAUDE.md](CLAUDE.md#where-things-are) are ours. `GAEA_GITHUB_TOKEN=$(gh auth token)` in Gaea's environment reads a
  private repo, and lifts GitHub's limit of 60 API calls an hour without a token, which a server with many plugins
  reaches when it checks them all. Gaea never stores the token.
- **Before anyone waits on one:** a model's first job downloads any weights that aren't under the models root, then
  loads them. A large model can take minutes; Z-Image's 19 GB took about nine on a fast connection.
  - `gaea plugins add` names the weights it didn't find there.
  - `gaea plugins warm <id> [model] [lane]` downloads and loads them now, so the next job starts at once.
  - A client that does wait is told, as MES progress stage `preparing`: "downloading the weights (first use): 4.2 of
    19.0 GB", then the load. The job's `x-gaea.worker.prepare_seconds` says how long it took.
- **Seeing them:** `gaea plugins` lists them, with each one's version, state and recent crashes. `gaea plugins logs
  <id>` shows its events and its worker's stderr.
- **Updates:** Gaea reads every plugin's repo when it starts, and `gaea plugins check` reads them again.
  - `gaea plugins update <id> [version]` installs the new version beside the current one, and switches when the
    plugin has no job.
  - `gaea plugins rollback <id>` goes back to the version kept.
  - A release that needs a newer Gaea isn't offered.
- **Switching off:** `gaea plugins disable <id>` keeps the plugin installed and takes its models out of what clients
  see; `enable` brings them back. `gaea plugins remove <id>` uninstalls it.
- **Settings:** a plugin's settings are on its row in the console's Plugins page, drawn from its manifest.

### Models

- **On and off:** `gaea models` lists every plugin's models. Research models and models whose licence needs
  accepting start off, and `gaea models enable <id>` turns one on. For a model whose licence asks each user to
  accept it too (LTX), clients see its terms and send their acceptance with the job; a job without it is refused with
  `terms_not_accepted`.
- **The models root** is the one folder every plugin reads and downloads weights into: MLXEngine's store
  (`~/Library/Application Support/MLXEngine/Models`) unless you move it.
  - `gaea models root <folder>` moves it, and `gaea models root default` goes back. Settings → General does the same.
  - `--models-root <folder>` moves it for one launch.
  - Workers restart when it changes, each one once its job ends.
  - A model downloads its weights the first time a job needs them. Put the root on a fast volume: a plugin can refuse
    a lane whose weights sit on a volume too slow for it, and the warning says what it measured.
  - Point it at the folder that holds the `models--org--name` snapshots themselves, not a folder above it. Otherwise
    every model downloads a copy of weights you already have. `gaea models` marks a model whose default lane's weights
    it doesn't find under the root.
- **Lanes:** many models come in several quantizations ("lanes", such as bf16, int8, int4).
  - Gaea loads a model's default lane when it fits in memory. Otherwise it loads the largest smaller lane that fits,
    and the result carries a `lane_fallback` warning naming both.
  - `gaea models lane <id> <lane>` sets the default, and `… default` goes back to the manifest's.
  - A request that names a lane (`x-gaea.lane`) gets that lane or is refused; it never falls back.
- **Tiers:** a plugin with tiers of very different cost ships each as its own model (LTX's compact24 … max128,
  TRELLIS.2's 512, 1024 and 1536). Turning the costly ones off keeps a server to the quick tiers, for a preview server
  that has to keep up with many requests: `gaea models disable trellis2-1024`. The server then offers only the
  qualities its remaining models serve and refuses the rest, and clients see it in the operation's descriptor. A
  smaller `--budget-bytes` drops every model that can't fit.
- **Adapters (LoRAs):** `gaea adapters` lists those the plugins ship and those you added. `gaea adapters add <hf-url>
  --model <id>` adds one from Hugging Face, pinned to its commit and sha256. One that needs accepting starts off, and
  `gaea adapters enable <id>` accepts its terms.

### Memory

Gaea runs one GPU job at a time across all its plugins, and it keeps workers warm so the next job doesn't reload.

- **The budget** is three quarters of the Mac's memory unless `--budget-bytes N` sets another for the launch.
- **Admission:** Gaea admits each job against the budget, counting what every worker holds. When a job doesn't fit,
  Gaea stops idle workers, least recently used first, to make room. A job that can't fit even then is refused with
  `no_capacity`, and a model larger than the whole budget isn't offered.
- **Peaks:** it learns each model's real peak from its runs, so a model that declares too little is charged what it
  used.
- **Idle workers** stop after 15 minutes, which frees their memory. A model then reloads on its next job (seconds,
  from disk).
  - `gaea workers idle <seconds>` changes it (30 or more), and `gaea workers idle default` goes back.
  - `--idle-seconds` sets it for one launch.
  - `gaea status` shows it.
- **Clients see the policy:** `GET /health` states the idle unload (`memory.idle_unload_s`) and when each loaded model
  will be unloaded if it stays idle (`resident_until`), and every job's timings report `prepare_ms`, the time it spent
  downloading or loading its model.
- **The ledger:** `gaea ledger` shows the budget, what each worker is charged and what it measures; the System page
  shows the same.
- **Wired memory:** a worker keeps its weights wired while its job runs, as an in-process engine does, and lets them
  go when the job ends. With one job at a time, that is never more than the job Gaea admitted. `GAEA_UNWIRED=1` in
  Gaea's environment turns it off.

### Trust

Gaea runs only plugins signed by a team you trust. It checks the signature, not the repo's URL, at install and again at
every launch.

- **Our team** (Dustin Nielson, CFZS6RXUCP) is trusted from the start.
- **A new team:** its release is held, not installed. The console's Plugins page and `gaea trust` show the
  certificate's name, the team id, notarization and the repo.
  - `gaea trust approve <held-id>` trusts the team and finishes the install. Later releases from that team then install
    without asking.
  - `gaea trust decline <held-id>` drops the release.
- **Removing a team:** `gaea trust remove <team>` stops its plugins and keeps them installed until you trust it again.

### Updates

- **Checks:** Gaea checks its GitHub releases every six hours, and `gaea update --check` checks now. Settings →
  Updates shows the same.
- **Gaea updates itself only while it runs.** A copy that has been closed for a while is updated by starting it, then
  `gaea update`.
- **Installing:** `gaea update [<version>]` downloads the release, checks its signature, notarization and sha256, and
  installs it once no job is running or waiting. It waits a minute after the last job (`--update-grace`), so that job's
  client can fetch its outputs, then swaps the app and relaunches.
- **Going back:** the version it replaced is kept in `Updates/`, and `gaea update --rollback` goes back to it.
  `gaea update --cancel` drops an update that is still waiting.
- **Pre-releases** are off; `gaea update --prereleases on` includes them.
- **Plugin versions:** an update that would drop a protocol version an installed plugin uses is refused, naming the
  plugin.

### Crashes

A worker that exits when Gaea didn't ask it to has crashed. Gaea records each crash.

- **The job:** a job whose worker crashed is run once more on a new worker. If that one crashes too, the job fails and
  its error names both crashes. A streamed job isn't run again.
- **The record:** `gaea crashes [<plugin>]` lists them, newest first, and `gaea crashes show <id>` gives one in full:
  - the plugin, version, model, lane and job;
  - the signal or exit code;
  - the last lines the worker wrote;
  - macOS's crash report, copied to `Crashes/` and summarised (a SIGKILL writes none).
- **Quarantine:** a plugin's third crash within ten minutes switches it off. Its models leave what clients see, its
  jobs are refused with the reason, and `gaea plugins`, `gaea status` and the console say why. Find the cause in its
  crashes, then `gaea plugins enable <id>` (or its On toggle) clears the quarantine, and the count starts again.
- **macOS's own dialog:** when Gaea runs as an app, macOS may also show "quit unexpectedly" for a crashed worker
  (`gaea-…-worker`). It is only macOS's notice. Gaea has already recorded the crash and dealt with the job, so you can
  close it.

## Write a plugin

The guide for plugin authors is [AUTHORING.md in gaea-plugin-demo](https://github.com/xocialize-code/gaea-plugin-demo/blob/main/AUTHORING.md).
It covers:
- the template;
- [GaeaPluginKit](https://github.com/xocialize-code/gaea-plugin-kit);
- signing with your own Developer ID;
- releasing;
- what an operator sees when your team is new to their server.

The protocol between Gaea and a plugin is [GPP-1](spec/GPP-1.md), with its schemas in [schemas/v1](schemas/v1).

## In this repo

| Path | What |
|---|---|
| [Docs/Gaea - PRD.md](Docs/Gaea%20-%20PRD.md) | The product requirements |
| [Docs/Gaea - Plan.md](Docs/Gaea%20-%20Plan.md) | Decisions, architecture, the plugin protocol and the phases |
| [spec/GPP-1.md](spec/GPP-1.md) | The Gaea Plugin Protocol v1 and manifest.json |
| [Sources/](Sources) | The host: GaeaCore, the console, the app, the `gaea` CLI |
| [Docs/Evidence/](Docs/Evidence) | The acceptance runs behind each piece of work |

## Licence

Apache-2.0.
