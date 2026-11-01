# AB-T-0410: Gaea updates itself (G4 order 2, DST-3, G-24)

**Done:** Gaea 0.12.1 updated itself to 0.12.2-rc.1 and rolled back. It did so headless and as the app, with jobs
queued during each update finishing. Both versions are CI releases on GitHub:
[v0.12.1](https://github.com/xocialize-code/gaea/releases/tag/v0.12.1) is Latest, and
[v0.12.2-rc.1](https://github.com/xocialize-code/gaea/releases/tag/v0.12.2-rc.1) is a test pre-release built from a
side branch and never merged. The run is `tools/acceptance-update.sh`, 28 of 28 ([acceptance.log](acceptance.log)).

## What Gaea does

Everything is in `Sources/GaeaCore/Update/`, and the same actions are in `gaea update` and Settings' Updates tab.

- **Checks** `xocialize-code/gaea`'s releases at start, every six hours, and on demand.
  - It offers only full releases, unless pre-releases are on (`--prereleases on`) or the operator names a version.
  - A release must carry `Gaea-<v>.zip`, its `.sha256` and `release.json`.
- **Refuses before downloading** when `release.json` says the release would drop a GPP or manifest version that an
  installed plugin uses. The refusal names the plugin.
- **Verifies the download** before anything on disk changes:
  - the zip's sha256 against both the `.sha256` asset and `release.json`;
  - a Developer ID signature from our team, with hardened runtime, notarized, and identifier `com.xocialize.gaea`;
  - the Info.plist version and the minimum macOS.
- **Asks the staged app itself** with `Gaea --version`, which loads MESCore's bundled tables first.
  - An app that crashes there is refused.
  - Its answer, `{"version","gpp","manifest"}`, is checked against the installed plugins again.
  - A Gaea before 0.12.0 exits 2 on the unknown flag, and is taken as GPP 1 and manifest version 1.
- **Waits until quiet:** no job received, fetching, waiting or running, and no held output younger than the grace
  (`--update-grace`, 60 s by default), so its client can fetch it. `gaea update --check` says what it waits for, and
  `gaea update --cancel` drops a waiting update.
- **Swaps the app** in one `renamex_np(RENAME_SWAP)` beside the old one, and keeps the replaced app in
  `<GAEA_HOME>/Updates/`. Only one version is kept.
- **Relaunches:**
  - **Headless:** Gaea stops serving, stops its workers, and execs the new binary in place. The pid, arguments,
    environment, port and folder stay the same, so a terminal or launchd job sees one process.
  - **The app:** a shell waits for the old process to exit and then starts the new binary with the same arguments
    and environment.
- **`gaea update --rollback`** goes back to the kept app the same way, and the version it leaves is kept in turn.
  The kept app's signature is checked again, but not its notarization, since a local build may be the one kept.

## The runs

| Run | From → to | Releases from | Result |
|---|---|---|---|
| GitHub | v0.12.1 (downloaded, Gatekeeper-accepted) → v0.12.2-rc.1 → back | GitHub | 28/28 ([acceptance.log](acceptance.log), [gaea.log](gaea.log)) |
| Rehearsal | 0.12.0 (local build) → 0.12.1-rc.0 (a local notarized build, never published) → back | `tools/release-standin.py` | 30/30 ([acceptance-standin.log](acceptance-standin.log)), which adds a release with a wrong digest refused and nothing staged |

Highlights of the GitHub run:
- **Headless:**
  - With pre-releases skipped, Gaea is up to date; with them on, 0.12.2-rc.1 is offered.
  - `gaea update` answered "once no job is running or waiting (now: 1 running)".
  - A second Z-Image job was queued during the wait. Both finished, and the queued one's PNG was fetched
    ([queued-during-update.png](queued-during-update.png)).
  - Gaea relaunched as 0.12.2-rc.1 10 s after the jobs settled (the 10 s grace). It kept pid 60730 and port 17761,
    and kept 0.12.1.
  - Z-Image ran on the new version, the app on disk passed `codesign` and `spctl`, and a rollback came back as
    0.12.1 in the same pid.
- **The app:** `gaea update 0.12.2-rc.1`, with pre-releases off, waited for a job, whose output was fetched
  ([app-during-update.png](app-during-update.png)). The app relaunched as 0.12.2-rc.1 as a new process
  (61072 → 61200), not headless, and answered MES on its port. The rollback returned 0.12.1 (pid 61236).
- **Settings' Updates tab** after the run: [light](settings-updates-light.png), [dark](settings-updates-dark.png).

## What the first run from GitHub found

The first attempt started from v0.12.0 as CI released it. That headless Gaea trapped as soon as a plugin was added:
`could not load resource bundle: from …/Gaea.app/MESKit_MESCore.bundle or /Users/runner/work/…/.build/…/MESKit_MESCore.bundle`.

- **Why:** GitHub's Swift 6.3 builds with the native build system. Its `Bundle.module` looks beside `Contents` and in
  the runner's `.build` folder, never in `Contents/Resources`.
- **Why nothing caught it:** this Mac's Swift 6.4 defaults to Swift Build, which looks in `Contents/Resources`. So
  the local rehearsal passed, and CI's smoke test passed with the runner's `.build` folder beside it.
- **Scope:** v0.11.3 had the same flaw. The released plugins don't: ming-image 0.3.0 and ltx 0.1.1 carry no
  build-folder paths.
- **Fixed in 0.12.1:**
  - `build-app.sh` names `--build-system swiftbuild` and refuses a binary that names a `.build` bundle path;
  - `release.sh` smoke-tests with `.build` hidden, through `Gaea --version`, which loads the tables;
  - the updater refuses an app that crashes answering `--version`.
- **Cost:** the CI build now takes about 16 minutes instead of 9.4.
- **Cleanup:** v0.11.3, v0.12.0 and the 0.12.1-rc.1 pre-release were deleted with their tags, with the operator's
  agreement (nothing had installed them).
- **Lesson:** AB-L-0322.

## Left

- Updates install only when asked (`gaea update`, Settings). Gaea checks on its own but doesn't install unattended.
  An automatic install for a studio server is a later option.
- A launchd-managed headless Gaea gets the same pid back. The 1.0 soak (G-26) will exercise an update under launchd.
- With a kept version newer than the running one, Settings' button still reads "Roll Back to …".
