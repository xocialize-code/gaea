# G-32: a notarized plugin runs whoever signed it

2026-11-25, Mac Studio (Mac17,14, M5 Max, 128 GB, macOS 27.3). A local Release build of main (labelled 1.9.3, with the
change; not released).

The operator's decision (AB-D-0295): a plugin needs a Developer ID signature and Apple's notarization, not a place on a
list of developers. The trust list stays for builds that aren't notarized.

## What changed

- `PluginVerifier.admits`: a bundle may run when Apple notarized it, or when its team is on the trust list. The seal,
  the Developer ID certificate, hardened runtime and the manifest checks are as before.
- `PluginManager.holdReason`: what still waits for the operator. A build that isn't notarized, from a team that isn't
  on the list; and an update signed by another team than the plugin it updates, notarized or not.
- `gaea trust remove <team>` stops only that team's plugins that aren't notarized.
- A launch goes by the notarization its install recorded for the same sealed bytes, so it needs no network.
- Gaea itself, its updates and the operator CLI stay pinned to our team.

## Results

| Run | Result | Log |
|---|---|---|
| Gaea unit tests | 120 passed | |
| `tools/acceptance-trust.sh`, our team treated as unknown (`GAEA_UNTRUST_OWN_TEAM=1`) | 31 passed, 0 failed | [acceptance.log](acceptance.log) |

What the acceptance shows, with the demo plugin 0.6.1 standing in for a stranger's:

- **Notarized (its release on GitHub).** It installs at once, nothing is held, no team joins the list, and a job runs,
  also after a restart. Approving and then removing its team stops nothing.
- **Not notarized (its local build, through the stand-in).** It is held, and the hold says why. Declined, the download
  goes. Approved, the team joins the list and a job runs. The team removed, the plugin stops, leaves the offers and
  stays installed, through a restart. Trusted again, it runs.
- **Without the injected set** our own build that isn't notarized installs at once, as it did.

## Not covered

- **An update signed by another team.** It needs one plugin id signed by two teams. `TrustTests` covers the decision,
  not a real install.
- **A plugin from a real second team.** `tools/acceptance-second-team.sh` (team F84FKGN358) was not rerun; its plugin
  would now install without the approval that script expects.
- **A launch with no network** of a bundle with no stapled ticket.
- **The console.** The Plugins page's wording for a stopped build was changed and not looked at.
