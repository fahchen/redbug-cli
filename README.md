# redbug-cli

A terminal UI for [redbug](https://hex.pm/packages/redbug)-style tracing of remote
Erlang/Elixir nodes — with no code, agent, or install on the target.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## What it is

- **Server** — an Elixir [musubi](https://hex.pm/packages/musubi) app (server-authoritative
  state over a Phoenix WebSocket). It owns the config, talks Erlang distribution to the
  target node, and runs the redbug tracer.
- **TUI** — an [opentui](https://opentui.com)/React client on Bun that renders the trace
  screens and drives the server over the WebSocket.

The redbug tracer is injected into the **target** node over distribution, so the target
needs no code changes and nothing installed on it — just a reachable node name and a
matching cookie.

The domain model is **Node ▸ Session ▸ Traces → Events**: connect a node, open a session,
add trace patterns (RTP), and the matching calls/returns/sends/receives stream in live.

## Requirements

Tooling is pinned in `mise.toml`:

```
erlang 28.3 · elixir 1.19.5-otp-28 · bun 1.3
```

```sh
mise install
```

## Quick start

```sh
mise run dev
```

This starts the server on a **random free port** (announced via a port file), waits for
it, then launches the TUI pointed at that port. The controller node is
`redbug_controller@127.0.0.1`; the distribution cookie comes from `RB_COOKIE`
(default `rbtest`).

### A throwaway target to trace

In another terminal, start an `iex` node with the **same cookie**:

```sh
iex --name target@127.0.0.1 --cookie rbtest
```

Then in that shell, define a module and call it:

```elixir
defmodule Demo do
  def add(a, b), do: a + b
end

Demo.add(1, 2)
```

Then in the TUI:

1. **Add the node.** Press `n`. Type the node name `target@127.0.0.1` (the `--name`
   you launched `iex` with), Enter. Type the cookie `rbtest`, Enter.
2. **Connect.** With the node selected, press `c`. The dot turns green (`●`) when the
   controller reaches it over distribution.
3. **Add a session.** Press `s`. Type a label, e.g. `demo`, Enter. On the "init from"
   picker leave `(blank)` selected, Enter.
4. **Add a trace pattern.** Press `enter` to open the session, then `e` for the trace
   editor. Press `a`, type `Demo.add/2 -> return`, Enter. Press `space` to enable it
   (it must be on), then `esc` to leave the editor.
5. **Trace.** Press `Shift+S` to start. Back in the iex target, call `Demo.add(1, 2)`
   again — the call and its return stream into the session live.

### Running the pieces separately

Pin the port with `REDBUG_PORT` so both sides agree on it (otherwise the server picks a
random free port and prints `redbug ws port: <n>`).

```sh
# server (controller must be a distributed longname node)
cd server
REDBUG_PORT=4010 elixir --name redbug_controller@127.0.0.1 --cookie rbtest -S mix phx.server

# TUI (point it at the server)
cd tui
REDBUG_HOST=127.0.0.1 REDBUG_PORT=4010 bun run dev
```

### Tests

```sh
cd server && mix test
```

The e2e test (`test/session_root_test.exs`) drives the full store layer against a real
target node, so start a target like the one above first.

## Keybindings

Every screen carries a slim hint statusline at the bottom; press `?` on any screen
for the full per-page keymap. Toggle the hints off via Settings → `show hints`.

**Tree**
`j/k` move · `enter` open session · `n` node · `s` session · `e` edit node ·
`c` connect/disconnect · `d` delete · `p` presets · `l` library · `,` settings · `?` help · `q` quit

**Session · Events**
`enter` detail · `v` view event in `$EDITOR` · `z` zoom · `o` sort · `/` filter · `g` group · `l` limits ·
`t` edit traces · `Shift+S`/`Shift+X` start/stop · `Ctrl+S` apply (restart) · `Ctrl+L` clear · `]` Console

**Session · Console**
`n` new · `e` edit · `v` view · `r` run · `s` stop · `c` clear · `[` Events

**Presets / Snippets / Settings**
`j/k` move · `enter`/`tab` edit · `space` toggle · `n` new · `esc` back

**Event kinds**
`↓` call · `↑` return · `→` send · `←` receive

## Configuration

Config is persisted to `~/.config/redbug/config.json` (file mode `0600`, dir `0700`;
honors `$XDG_CONFIG_HOME`). It stores nodes, sessions, presets, and settings. The cookie is
stored in plaintext, so keep the file local and the WebSocket channel trusted.

| Variable | Component | Default | Purpose |
|---|---|---|---|
| `REDBUG_HOST` | TUI | `127.0.0.1` | Server host the TUI connects to |
| `REDBUG_PORT` | TUI / server | `4010`* | WS port (server pins it when set, else picks a free one) |
| `REDBUG_NODES` | server | — | Comma-separated env-injected nodes (epmd-free): `name@host\|dial_ip:port\|cookie` (see [Remote nodes](docs/remote-nodes.md)) |
| `REDBUG_PORT_FILE` | server | — | If set, the chosen port is written here (used by the launcher) |
| `RB_COOKIE` | dev | `rbtest` | Distribution cookie for the controller (`mise run dev`) |
| `CONTROLLER_NODE` | server | `redbug_controller@127.0.0.1` | Controller node name |
| `RELEASE_NODE` / `RELEASE_COOKIE` / `RELEASE_DISTRIBUTION` | release | — | Standard Elixir release distribution settings |
| `XDG_CONFIG_HOME` | server | `~/.config` | Base dir for `redbug/config.json` |

\* The server uses an OS-assigned free port when `REDBUG_PORT` is unset.

## Packaging

```sh
mise run package
```

Produces a single self-contained binary at `dist/redbug` — a bun `--compile` executable
with the `server` release (ERTS bundled) embedded as a tarball. On first run it extracts the
release to a per-build cache dir, spawns it as the controller node, waits for its WebSocket
port, then renders the TUI against it. Quitting the TUI tears the controller down. macOS
arm64 only; no system Erlang or Bun needed on the target.

```sh
./dist/redbug
```

## Tracing a remote node

The controller and TUI always run locally. To trace a node on another host, the controller
only needs to reach that node over Erlang distribution (its **epmd** and **distribution**
ports) with a matching cookie — no agent, sidecar, or code is deployed to the target. For
routable hosts, `REDBUG_NODES` env injection, SSH-tunnelled setups, and
[Kamal](https://kamal-deploy.org)/Docker containers, see [**Remote nodes**](docs/remote-nodes.md).

## Security

- **Cookie == RCE.** The distribution cookie is a full remote-code-execution capability on
  the target. The config file is `0600`; keep it local.
- Keep the WebSocket on `127.0.0.1` (the default) — **never expose it on a public interface.**
- Erlang distribution is **unencrypted** unless tunnelled. Reach epmd/distribution ports over
  a VPN or SSH tunnel; never expose them to untrusted networks.

## Documentation

- [Remote nodes](docs/remote-nodes.md) — trace nodes on other hosts (routable, `REDBUG_NODES`, SSH, Kamal)
- [Screen design](docs/screens.md) — TUI screen-by-screen design reference

## License

[MIT](LICENSE) © Phil Chen
