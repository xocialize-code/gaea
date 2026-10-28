# Spike: plugins as downloaded executables

**Question:** can a Gaea plugin be an executable that Gaea downloads at runtime (from GitHub Releases) and then
calls? **Answer: yes.** It works on this Mac (macOS 27.2, Mac17,14) with a Developer ID host app that is neither
sandboxed nor on the App Store. Every check below passed on 2026-10-27.

## What a plugin is

It is a signed bundle, not an app. It has no UI of its own: Gaea draws the UI from the plugin's descriptors.

```
demo.gaeaplugin/Contents/
  Info.plist                      CFBundleIdentifier, version
  MacOS/gaea-demo-worker          the model worker (MLX statically linked), 4.6 MB zipped with the metallib
  Resources/mlx-swift_Cmlx.bundle default.metallib (MLX finds it through the plugin's own main bundle)
  Resources/manifest.json         id, version, protocol, operations, footprint, licence
```

- **Signing.** Developer ID with hardened runtime and a timestamp. The bundle seal covers the metallib and the
  manifest.
- **Protocol.** One JSON object per line over stdin and stdout. The worker sends `hello`; the host sends a job; the
  worker answers with `progress`, then `result` or `error`. The host can also send `cancel` and `shutdown`.

## How Gaea installs and runs a plugin

1. **Discover.** Read the catalog (here a local `catalog.json`; in Gaea, a GitHub release). Find updates with
   `GET /repos/{owner}/{repo}/releases/latest`.
2. **Download** with URLSession. A non-sandboxed app without `LSFileQuarantineEnabled` puts no quarantine flag on
   the file.
3. **Check the checksum** (sha256) against the catalog.
4. **Unpack** with `ditto -x -k`.
5. **Check the signature** with `SecStaticCodeCheckValidity` (all architectures, strict validation, nested code)
   against a Developer ID requirement pinned to our team ID.
6. **Launch** with `Process.launchRequirement` set to `TeamIdentifier` and `ValidationCategory(.developerID)`
   (LightweightCodeRequirements, macOS 14.4 and later). The kernel then enforces the same rule at exec.

## Results

| # | Check | Result |
|---|---|---|
| 1 | Discovery: the catalog lists 3 plugins (good, ad-hoc, tampered) | PASS |
| 2 | Download not quarantined; signature accepted (Developer ID, CFZS6RXUCP) | PASS |
| 3 | Launch, through to the worker's hello | **263 ms** |
| 4 | Real MLX job on the GPU from the installed plugin, build folder hidden | PASS, `Device(gpu, 0)`, 1.53 s first job, including metallib load |
| 5 | Host reads the worker's footprint (`proc_pid_rusage`, `ri_phys_footprint`) | idle 0 → peak 2.37 GB |
| 6 | Second job on the warm process | **0.12 s** |
| 7 | Cooperative cancel reaches the model loop | PASS |
| 8 | SIGKILL during a job | 5.12 GB resident → gone in **65 ms** |
| 9 | Ad-hoc signed plugin | refused at install (-67050, requirement not met) |
| 10 | Tampered plugin (manifest edited after signing) | refused at install (-67054, seal broken) |
| 11 | Ad-hoc worker launched directly, skipping our own check | **the kernel kills it at exec**: `SIGKILL (Code Signature Invalid)`, and a crash report is logged |
| 12 | A zip the user downloaded with a browser (quarantined), quarantine stripped after our check passes | PASS |
| 13 | GitHub latest-release lookup (ml-explore/mlx-swift) | PASS, 0.33.0 |

The bare-executable spike done first, in the scratchpad:

- A *quarantined* worker, ad-hoc or Developer ID-signed but **not notarized**, is held at `_dyld_start` behind a
  Gatekeeper "Not Opened" dialog.
- Without quarantine, both run.

## What the spike establishes

- **Gatekeeper.** It only gets involved when a file is quarantined. Gaea's own downloader doesn't quarantine, so our
  signature check plus the kernel's launch requirement is the gate.
- **Notarization** is still worth doing in plugin CI:
  - it covers zips that users side-load;
  - it adds defence in depth.
  It needs `xcrun notarytool store-credentials`, which takes the owner's Apple ID app password and isn't set up on
  this Mac.
- **Memory can be managed per process.** The host sees each worker's real footprint, and killing a worker returns
  all of it at once. Nothing is left behind by MLX's cache or by fragmentation.
- **Each plugin pins its own dependencies,** including the mlx-swift version. Gaea never resolves one dependency
  graph across every model.
- **A refused launch is a SIGKILL, not an error thrown by `run()`.**
  - Gaea should end the wait for hello as soon as the process exits, using `terminationHandler`, rather than the
    10 s timeout this spike uses.
  - Each refusal writes a crash report, so the static check at install time stays the main gate.

## Not covered yet

- **Notarized workers** (no notary profile on this Mac).
- **Moving large inputs and outputs:**
  - images and video frames through spool paths or IOSurface;
  - streamed audio (MES RFC 0002).
- **Helper models shared by plugins.** An example is the prompt-enhance LLM:
  - it could be a plugin of its own;
  - or each plugin could carry its own copy.
- **A memory budget across processes,** built from each manifest's declared footprint and the measured
  `phys_footprint`. This replaces MLXServe's in-process governor at Gaea's level.
- **Accepting third-party team IDs:** a trust list the user approves.

## Running it again

```bash
cd Worker && xcrun swift build -c release
```

```bash
tools/package-plugins.sh
```

```bash
tools/build-host.sh
```

```bash
python3 -m http.server 8765 --bind 127.0.0.1 --directory dist
```

```bash
dist/GaeaPluginHost.app/Contents/MacOS/GaeaPluginHost --selftest http://127.0.0.1:8765/catalog.json
```

`open dist/GaeaPluginHost.app` opens the same flow as a small window: Refresh, Install, Run.

Hide `Worker/.build` while the self-test runs. That shows MLX loading the metallib from the plugin and not from the
build folder.
