# AB-T-0429: G4's exit, Gaea 1.0.0 (order 7)

All runs were on an M5 Max (128 GB, macOS 27.3) against CI-built, notarized releases from GitHub.

| Exit test | Result | Evidence |
|---|---|---|
| A clean install (G4 exit) | **13/13**, Gaea 1.0.0-rc.1 in a throwaway clone of AppProbe's golden macOS 26.6.2 VM (Tart, VirtualMac2,1, 16 GB). See note 1 | `clean-install/`, `tools/acceptance-clean-install.sh` |
| A plugin from a real second team (G-25) | **23/23**, Gaea 1.0.0-rc.1. See note 2 | `second-team/`, `tools/acceptance-second-team.sh` |
| The 24-hour soak (G-26) | **7,413/7,413** mixed jobs, the self-update rc.1 → rc.2 answering in 63 s, 24 of 24 injected crashes failed as designed, nothing quarantined. See note 3 | `soak/`, `tools/soak.py` |
| The LTX leak the soak found | 5,264 bytes a run → 56–96 bytes total on LTX 0.1.3, through Gaea. See note 4 | `ltx-leak/` |
| Conformance with every plugin | **83 passed, 0 failed, 8 skipped**. See note 5 | `conformance/`, `tools/conformance-with.sh` |
| 1.0.0 tagged and released by CI | the `v1.0.0` release | `release-1.0.0.json` |

Notes:

1. **Clean install.** The VM had never seen Gaea. The checks:
   - the release zip downloaded quarantined and matched its sha256;
   - Gatekeeper accepted the app as notarized Developer ID, with its ticket stapled;
   - the app and headless Gaea both served;
   - the demo plugin installed from GitHub and ran on the guest's paravirtualized GPU;
   - the console rendered its pages.

   A throwaway VM, not a second user account, was the operator's choice.
2. **Second team.** The plugin is signed and notarized by MOUNTAIN VIEW STAGING SERVICES INC (F84FKGN358). The checks:
   - it was held with the certificate, team, notarization and models shown;
   - approving it trusted the team and ran the plugin, its worker signed by F84FKGN358;
   - it ran beside our own team's demo;
   - removing the team stopped only its plugin, and approving the team again ran it.
3. **Soak.** Two LTX workers hit MLX's 499,000-buffer limit; both jobs were requeued and succeeded.
4. **LTX leak.** The cause was mlx-swift's `_updateInternal` leaking every quantized load (AB-L-0330). It was fixed
   through mlx-engine-swift 0.74.1's mlx-swift fork (AB-A-0249, AB-D-0208).
5. **Conformance.** All 22 public plugins were installed from GitHub on 1.0.0-rc.2. Base, Image, Audio and Video 0.1
   conform.

1.0.0 is rc.2 with its version bumped. Per the operator's decision AB-D-0207, it stays labelled alpha (README,
`Docs/Releases/1.0.0.md`): more plugins (AuK) may still change MES.
