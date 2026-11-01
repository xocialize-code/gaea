# Gaea

Gaea is a media server for the Mac. It serves the Media Engine Spec (MES) Image, Audio and Video profiles, and its
models come as plugins:
- each plugin is a signed `.gaeaplugin` bundle that Gaea installs from a GitHub repo and runs in a process of its own;
- Gaea does the MES front end, the queue, memory across processes, the plugins' lifecycle and the UI;
- the plugins do the generating.

## Install

Download `Gaea-<version>.zip` from [Releases](https://github.com/xocialize-code/gaea/releases), unzip it, and move
`Gaea.app` to Applications. It needs macOS 26 on Apple silicon, and it updates itself from these releases
(`gaea update`, or Settings → Updates). The command-line tool is `Gaea.app/Contents/Helpers/gaea`.

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
