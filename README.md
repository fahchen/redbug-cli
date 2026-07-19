# redbug-cli

A terminal UI for tracing remote Erlang and Elixir nodes with
[redbug](https://hex.pm/packages/redbug), without adding code, installing an agent, or deploying
anything to the target node.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Demo

<!--
Add the demo GIF here before publishing, for example:

![redbug-cli tracing demo](docs/demo.gif)
-->

_Demo GIF coming soon._

## Why redbug-cli?

- **Nothing to install on the target.** No code change, no restart, no agent — attach to a running
  node and start watching.
- **Watch live activity.** See function calls, their return values, and messages between processes
  as they happen.
- **See what belongs together.** Each call and its return share a number and indent by depth, and
  fold into a single row on demand.
- **Follow messages.** Track messages sent and received to understand how processes talk to each
  other.
- **Run and reuse snippets.** Execute commands against the node from a built-in console and save the
  ones you come back to.
- **Reach nodes anywhere.** On your machine, across a private network, or behind SSH — including
  containerized deployments.
- **Pick up where you left off.** Sessions, trace patterns, snippets, and node config are saved.
- **Dig into any event.** Read payloads and stack traces in the TUI, or open an event in `$EDITOR`.

## Quick Start

Tool versions are pinned in [mise.toml](mise.toml). Install the toolchain, then run the dev task:

```sh
mise install   # Erlang, Elixir, Bun (from [tools])
mise run dev    # installs deps if needed, then boots controller + TUI
```

This starts the controller on a random local port and opens the TUI.

The workflow is driven by three [mise tasks](mise.toml) (`mise tasks` to list, `mise run <task>`):

| Task | Does |
|---|---|
| `setup` | Fetch Elixir controller deps + install Bun/TUI deps |
| `dev` | Boot the controller on a free port, then the TUI (`RB_COOKIE`, default `rbtest`) |
| `package` | Build the single-file `dist/redbug` (server release embedded) |

`dev` and `package` depend on `setup`, so a fresh checkout only needs `mise install` first.

In another terminal, start a throwaway target node with the same cookie:

```sh
iex --name target@127.0.0.1 --cookie rbtest
```

Define and call something in that `iex` session:

```elixir
defmodule Demo do
  def add(a, b), do: a + b
end

Demo.add(1, 2)
```

In redbug-cli (press `?` at any time for the active screen's keys):

1. Add node `target@127.0.0.1` with cookie `rbtest`.
2. Connect to it.
3. Create a session under the node (name it, pick a preset).
4. Open the session, add the trace `Demo.add/2 -> return`, and enable it.
5. Start tracing.
6. Call `Demo.add(1, 2)` again in `iex`.

The call and return events stream into the session.

## Install / Package

Build the single-file executable:

```sh
mise run package
./dist/redbug
```

The packaged binary embeds the Elixir controller release and the Bun TUI launcher. On first run it
extracts the controller to a per-build cache directory, starts it locally, and tears it down when
the TUI exits.

Current packaging target: macOS arm64.

## Keybindings

Press `?` in the TUI for the active screen's keymap.

## Tracing Remote Nodes

redbug-cli supports three remote-node paths:

| Target shape | Use |
|---|---|
| SSH-only host with a Docker/Kamal container | Built-in SSH tunnel |
| Routable host over VPN/LAN/WireGuard | Direct Erlang distribution |
| CI or custom tunnel setup | `REDBUG_NODES` |

For details, see [Remote nodes](docs/remote-nodes.md).

## Configuration

Config is persisted to `~/.config/redbug/config.json` and honors `$XDG_CONFIG_HOME`. The file
stores nodes, sessions, presets, snippets, and settings. Cookies are stored in plaintext, so keep
the config local and private.

| Variable | Component | Default | Purpose |
|---|---|---|---|
| `REDBUG_HOST` | TUI | `127.0.0.1` | Controller host |
| `REDBUG_PORT` | TUI / server | random when unset | WebSocket port |
| `REDBUG_PORT_FILE` | server | - | Writes the chosen port for launchers |
| `REDBUG_NODES` | server | - | Env-injected nodes: `name@host\|dial_ip:port\|cookie` |
| `RB_COOKIE` | dev | `rbtest` | Cookie used by `mise run dev` |
| `CONTROLLER_NODE` | server | `redbug_controller@127.0.0.1` | Controller node name |
| `CONTROLLER_DISTRIBUTION` | server | `name` | Use `sname` for shortname targets |
| `XDG_CONFIG_HOME` | server | `~/.config` | Config base directory |

## Security

- The Erlang distribution cookie is remote-code-execution capability on the target.
- Keep the WebSocket bound to `127.0.0.1`.
- Erlang distribution is unencrypted unless tunnelled; use SSH or a trusted private network.
- Do not expose epmd or distribution ports to untrusted networks.

## Development

```sh
cd server && mix test
cd tui && bun run typecheck
```

The full session-root test drives the store layer against a real target node, so start a target
like the quick-start `iex` node first when running the whole server test suite.

### Running Pieces Separately

Pin the port with `REDBUG_PORT` when starting the controller and TUI yourself:

```sh
cd server
REDBUG_PORT=4010 elixir --name redbug_controller@127.0.0.1 --cookie rbtest -S mix phx.server

cd ../tui
REDBUG_HOST=127.0.0.1 REDBUG_PORT=4010 bun run dev
```

### Architecture

redbug-cli has two parts:

- **Controller**: an Elixir [musubi](https://hex.pm/packages/musubi) app with
  server-authoritative state over a Phoenix WebSocket. It owns config, connects to target nodes,
  and runs redbug.
- **TUI**: an [opentui](https://opentui.com) / React client on Bun.

The domain model is:

```text
Node -> Session -> Trace patterns -> Events
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Remote nodes](docs/remote-nodes.md)
- [Testing & screenshots](docs/testing.md)
- [Demo script](docs/demo-script.md)

## License

[MIT](LICENSE) © Phil Chen
