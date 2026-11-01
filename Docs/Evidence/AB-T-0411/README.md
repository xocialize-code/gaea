# AB-T-0411: the trust list (G4 order 3, PLG-3, UI-3, G-7, G-25)

**Done:** Gaea 0.13.0 ran with its own team treated as unknown (`GAEA_UNTRUST_OWN_TEAM=1`, the injected trust set
G-25 calls for). With the plugins' releases on GitHub, the run showed:
- the demo plugin was held, declined, held again and approved;
- the approved demo ran a job;
- Z-Image followed without a prompt, because its team was now trusted;
- both plugins were stopped when the team was removed, and stayed installed;
- an update was held while the team was untrusted;
- approving that update brought both plugins back.

The run is `tools/acceptance-trust.sh`, 42 of 42 ([acceptance.log](acceptance.log), [events.txt](events.txt),
[gaea.log](gaea.log)).

## What Gaea does

- **The list:**
  - Teams live in `gaea.sqlite` (`trusted_team`, migration v3). Gaea's own team, `CFZS6RXUCP`, is built in and can't be
    removed.
  - `GAEA_UNTRUST_OWN_TEAM=1` drops it from the built-in set for one run. That only ever narrows trust, so it ships
    in the release build.
  - Gaea itself, its updates (G-24) and the operator CLI's peer check stay pinned to our team alone, whatever the list
    says.
- **The verifier** (`PluginVerifier`) works in two steps:
  1. It checks what doesn't depend on the list: the seal, a Developer ID Application certificate, hardened runtime,
     and notarization.
  2. It then checks the team against a requirement built from the trusted teams
     (`… and (certificate leaf[subject.OU] = "A" or …)`).

  This runs at install and again before every launch, and a worker's `launchRequirement` is pinned to its own
  plugin's team.
- **Held, not refused:**
  - A release that passes every check except the team's is kept in `<GAEA_HOME>/Held/<id>/` and recorded in
    `held_release`, whether it came from an add or an update.
  - `gaea plugins add` and `gaea plugins update` print the hold: the certificate's name, team id, notarization, repo
    and tag, and the models it adds.
  - The console's Plugins page gets the same release as MESEngineUI's trust prompt (`PluginInstallOutcome.needsTrust`).
- **Approve** (`gaea trust approve <id>`, or Trust and Install in the console):
  - The team joins the list.
  - The held bundle is verified again, then installed. An update switches in when the plugin is idle and keeps the old
    version for rollback.
  - `gaea trust approve <TEAM>` trusts a team again from one of its installed or held plugins. A team with neither is
    refused, because Gaea would have no certificate to show.
- **Decline** (`gaea trust decline <id>`, or Don't Trust): the download is deleted.
- **Remove** (`gaea trust remove <TEAM>`, or Remove on the Trusted Teams card):
  - The team's workers stop, and its models leave the offers.
  - Jobs for those models are refused.
  - The plugins stay installed, with their on and off choices kept, and are marked stopped in `gaea plugins` and
    "Can't run" in the console.
  - This survives a restart, and the plugins run again when the team is trusted again.
- **`gaea trust`** lists the trusted teams (built in, or approved with the date), the installed plugins whose team
  isn't trusted, and what's held. `gaea status` has a `Trust:` line.

## The run

| Step | What happened |
|---|---|
| Nothing trusted | Adding the demo held v0.3.1 as `h-640490b4`. The hold showed "Developer ID Application: Dustin Nielson (CFZS6RXUCP)", notarized, the repo and tag, and both models. Nothing was installed or offered, and a job was refused. Declining emptied `Held/`. |
| Approved | v0.3.0, named, was held as `h-06d0df71` and approved. The team was listed as "Dustin Nielson, approved …", and a `demo-gradient` job succeeded ([job-approved.json](job-approved.json)). Z-Image 0.1.0 then installed without a hold. |
| Team removed | The demo's idle worker stopped and neither plugin was offered. A job was refused, and both plugins were still on disk and marked stopped, through a restart. `gaea plugins update` of the demo to 0.3.1 was held (`h-f83fdeef`). |
| Trusted again | Approving that update trusted the team and switched the demo to 0.3.1, keeping 0.3.0. Both plugins were offered, and a job ran on 0.3.1 ([job-trusted-again.json](job-trusted-again.json)). Removing the team and approving it by id brought both back. |
| Default | Without the variable, our team was built in. The demo installed at once, and `trust remove CFZS6RXUCP` was refused. |

The console's Plugins page was rendered with `Gaea --snapshot` at two points:
- **Team removed:** both plugins showed "Can't run" with the reason, and the Trusted Teams card was empty
  ([light](console-plugins-untrusted-light.png), [dark](console-plugins-untrusted-dark.png)).
- **Trusted again:** the card listed the approved team with Remove ([light](console-plugins-light.png),
  [dark](console-plugins-dark.png)).

`swift test`: 73 tests, including `TrustTests`:
- the requirement text;
- the tables;
- a stubbed GitHub serving the demo's local release, held, declined, approved, removed and trusted again;
- the built-in team refused.

## Left

- **The console's trust prompt sheet** is MESEngineUI's own. Gaea answers it through `needsTrust`, `trust` and
  `decline`. The run drove the same approval through `gaea trust`, and only the page itself was rendered, not the
  sheet.
- **A plugin signed by a real second team** is the 1.0 exit's test (G-25).
- **The author guide (order 4)** should tell third-party authors what the operator sees when their team is new.
