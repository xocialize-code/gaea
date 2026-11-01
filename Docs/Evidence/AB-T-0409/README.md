# AB-T-0409: Gaea's release pipeline (G4 order 1)

Gaea 0.11.3 is the first release built by CI: `v0.11.3`, published 2026-11-01T19:21:09Z, not a pre-release.

**Withdrawn the same day.** AB-T-0410's run from GitHub found that 0.11.3 traps on MESCore's first bundled table on any
Mac but the runner (AB-L-0322): CI's Swift 6.3 built with the native build system, whose `Bundle.module` falls back to
the runner's `.build` folder, which the smoke test below had beside it. With the operator's agreement, 0.11.3 and 0.12.0
were deleted with their tags (nothing had installed them). 0.12.1 is the first good CI release
(`Docs/Evidence/AB-T-0410/`). The pipeline below is unchanged except for `--build-system swiftbuild`, a check of the
binary, and a smoke test with `.build` hidden.

## What ships it

- **`scripts/release.sh`**, the same on this Mac and in CI:
  - checks the tag against `Gaea.version`;
  - builds and signs with `scripts/build-app.sh`, and checks the Info.plist version;
  - smoke-tests the built app: headless in a fresh `GAEA_HOME`, it must answer `GET /mes/v0/engine` and
    `gaea status` must say `Gaea <version>`;
  - notarizes the zip and stops unless the status is Accepted;
  - staples the app, re-zips it, and runs `stapler validate` and `spctl --assess`;
  - writes the zip's sha256 and `release.json` (version, tag, zip, digest, minimum macOS, GPP versions, team,
    notarized), which the updater reads (G-24);
  - publishes the GitHub release, with notes and a link to the changes since the previous tag. `PUBLISH=no` stops
    before this step.
- **`.github/workflows/release.yml`**:
  - runs on a pushed `v*` tag, or on demand for a tag with `publish` off by default;
  - runs on `macos-26` with the newest Xcode;
  - imports the Developer ID p12 and the notary credentials (organization secrets) into a temporary keychain, runs
    the script, keeps `dist/`'s evidence as an artifact, and deletes the keychain.

## The run

Run [41340418451](https://github.com/xocialize-code/gaea/actions/runs/41340418451) was triggered by pushing tag v0.11.3
at b969e54. It ran from 19:10:52Z to 19:21:19Z, about 10.5 minutes. [ci-excerpt.log](ci-excerpt.log) has its key lines:
- Apple Swift 6.3.3;
- build 9.4 min;
- smoke passed;
- notarization Accepted in 28 s (submission `7119e698-c9b1-4651-b00e-10f3766a7907`);
- stapled and validated;
- Gatekeeper `source=Notarized Developer ID`;
- released.

## Checked on this Mac after downloading

`gh release download v0.11.3`, then:

| Check | Result |
|---|---|
| `shasum -a 256 -c Gaea-0.11.3.zip.sha256` | OK (`1c1b6ce2…7dda1e`, the same digest as [release.json](release.json)) |
| `codesign --verify --strict --deep` | valid on disk, satisfies its Designated Requirement |
| `codesign -dv` (app and `Contents/Helpers/gaea`) | TeamIdentifier CFZS6RXUCP, flags `runtime`, secure timestamp |
| `stapler validate` | worked |
| `spctl --assess --type execute`, on a copy unzipped from a zip carrying a Safari quarantine flag | accepted, `source=Notarized Developer ID` |
| Headless from that copy, a fresh `GAEA_HOME`, port 17798 | the handshake answered (implementation `gaea` 0.11.3, [engine.json](engine.json)); `gaea status` printed `Gaea 0.11.3` |

## What it took

- **GitHub's newest runner has Xcode 26 (Swift 6.3.3).** This Mac has Xcode 27 (Swift 6.4.2). Three kinds of code
  that 6.4 accepts fail on 6.3:
  - **Gaea's own:** `let x = x(…)` or `var offer = offer(model)` resolves to the local being declared. Qualified
    with `Self.` or `self.` in 0fe4763, with no change in behaviour.
  - **media-engine-spec 0.9.0:** two shift-or expressions in `WAV.swift` were too slow to type-check, and a `try` in
    `MCPBinding.swift` didn't cover the outer call. Fixed by mlx-apps in v0.9.1 (AB-A-0244, a6b107f), which now
    has its own macos-26 CI. Gaea requires 0.9.1 from b969e54.
  - **pixel-agency-normalizer** built unchanged.
- **The proof before 0.9.1:** branch `ci-xcode26-probe` ran the whole pipeline with `PUBLISH=no`, patching
  media-engine-spec in its own checkout. Run 41332318501 passed: notarized Accepted, stapled, Gatekeeper accepted.
  The branch is deleted.
- **Left:** `AudioPCM.swift:93–95` warns on 6.3 about a captured `var` in a `@Sendable` closure. It's a warning
  only, and 6.4 doesn't warn.
