# Blip ◉

**A little blip on your radar when your agent needs you.**

Blip lives in your Mac's menu bar – right next to Bluetooth and Wi-Fi – and shows what your
**GitHub Copilot CLI** agents are doing, live. When an agent needs permission, you can approve it right from
the menu bar, whether the terminal is in front or buried behind ten other windows.

| State | Menu bar icon |
|---|---|
| Idle | a calm radar blip (monochrome) |
| Working | three bouncing dots (monochrome) |
| Needs you | an orange hand, waving |
| Done | a green checkmark pops in until you've seen it |
| Error | a red warning triangle shakes its head |

Click the icon to see all sessions. Click a session for its **live feed**: your prompt, every command with its
output, permission requests and the agent's answer. **Jump to Session** brings the exact terminal tab to the front.

## Approvals from the menu bar

When the agent wants to do something that needs permission (run a command, write a file, fetch a URL …), a card
appears in the popover and you get a notification. Choose **Allow**, **For Session** (e.g. all `npm` commands
in this session) or **Deny** (the agent is told you declined).

Copilot still asks **in the terminal as usual** at the same time – whoever answers first wins. Answer in the
terminal and the card disappears by itself. If Blip isn't running, nothing changes for you.

## Installation

Blip is a **Copilot CLI plugin**:

```sh
copilot plugin install pfstl/blip
```

Then start a new Copilot session. On first launch the plugin's extension checks whether the Blip app is there.
If not, it **builds the app once, locally**, from the plugin's source (about 1–2 minutes, in the background)
and launches it. After a plugin update (`copilot plugin update blip`) the app is rebuilt automatically the next
time a session starts.

**Requirements:** macOS 14+, the Xcode Command Line Tools (if they're missing, Blip starts the installer) and
experimental features enabled in the Copilot CLI (`/experimental`).

Because the app is built on your machine, it doesn't need an Apple signature. Everything stays in your home folder:

| What | Where |
|---|---|
| Plugin incl. extension and source | `~/.copilot/installed-plugins/…/blip` |
| App | `~/Applications/Blip.app` |
| Command-line tool | `~/.local/bin/blip` |
| Launch at login | `~/Library/LaunchAgents/io.github.blip-agents.plist` |
| Build, socket, logs | `~/.blip/` (`build.log`, `debug.log`) |

On first use, macOS asks whether Blip may send notifications and – for **Jump to Session** – control Terminal
or iTerm.

## Commands

```
blip demo        watch two fake sessions incl. a test permission request
blip status      state + active sessions
blip doctor      check the installation
blip log         debug log
blip start|stop|restart
blip update      updates come through `copilot plugin update blip`
blip uninstall   remove everything (then: copilot plugin uninstall blip)
```

## How it works

```
Copilot CLI ── plugin extension (extensions/blip) ── stream socket ~/.blip/blip-ext.sock ──► Blip.app
                 • reports prompts, tool calls, output, permission requests, "done"               (menu bar)
                 • answers permission requests via handlePendingPermissionRequest
```

The extension joins every session (`joinSession`). It registers its own permission handler – that's what
allows it to answer permission requests – but replies with `no-result`, so the terminal prompts as usual.
Your answer from Blip then reaches Copilot through `session.rpc.permissions.handlePendingPermissionRequest`.

Copilot CLI extensions are still marked experimental. VS Code and the Copilot app aren't supported.

## Development

```sh
make install                # build and install the app from this folder
make dev                    # run the app from the debug build
make demo                   # send fake sessions
copilot plugin install ./   # install the plugin from the local folder
```

When bumping the version, update `version` in `.plugin/plugin.json` **and** `BlipInfo.version` in
`Sources/BlipShared/Paths.swift` – that's how the extension knows the app needs a rebuild.

```
.plugin/plugin.json          plugin manifest
extensions/blip/             Copilot CLI extension (live feed, approvals, app setup)
Sources/
  BlipShared/                paths, sockets, protocol
  blip/                      command-line tool (install, demo, status …)
  BlipApp/                   menu bar app (NSStatusItem + SwiftUI popover)
```
