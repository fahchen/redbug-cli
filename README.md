# redbug-cli

A terminal UI for [redbug](https://hex.pm/packages/redbug)-style tracing of remote
Erlang/Elixir nodes.

- **Server** — an Elixir [musubi](https://hex.pm/packages/musubi) app (server-authoritative
  state over a Phoenix WebSocket). It owns the config, talks Erlang distribution to the
  target node, and runs the redbug tracer.
- **TUI** — an [opentui](https://opentui.com)/React client on Bun that renders the trace
  screens and drives the server over the WebSocket.

The redbug tracer is injected into the **target** node over distribution, so the target
needs no code changes and nothing installed on it — just a reachable node name and a
matching cookie.

## Requirements

Tooling is pinned in `mise.toml`:

```
erlang 28.3 · elixir 1.19.5-otp-28 · bun 1.3
```

```sh
mise install
```

## Local testing

### One command

```sh
mise run dev
```

This starts the server on a **random free port** (announced via a port file), waits for
it, then launches the TUI pointed at that port. The controller node is
`redbug_controller@127.0.0.1`; the distribution cookie comes from `RB_COOKIE`
(default `rbtest`).

### A throwaway target to trace

In another terminal, start a node that does some work, using the **same cookie**:

```sh
elixir --name target@127.0.0.1 --cookie rbtest -e \
  'defmodule L do def go do :lists.seq(1, 5); Process.sleep(150); go() end end; spawn(&L.go/0); Process.sleep(:infinity)'
```

Then in the TUI:

1. `n` — add a node, name `target@127.0.0.1`, cookie `rbtest`.
2. `c` — connect.
3. `s` — add a session, give it a trace pattern (e.g. `lists:seq/2 -> return`).
4. `Shift+S` — start tracing; events stream in live.

### Running the pieces separately

```sh
# server (controller must be a distributed longname node)
cd server
elixir --name redbug_controller@127.0.0.1 --cookie rbtest -S mix phx.server

# TUI (point it at the server)
cd tui
REDBUG_HOST=127.0.0.1 REDBUG_PORT=<port> bun run dev
```

### Tests

```sh
cd server && mix test
```

The e2e test (`test/session_root_test.exs`) drives the full store layer against a real
target node, so start a target like the one above first.

## Keybindings

**Tree**
`j/k` move · `enter` open session · `n` node · `s` session · `e` edit node ·
`c` connect/disconnect · `d` delete · `p` presets · `,` settings · `?` help · `q` quit

**Session**
`enter` detail · `o` sort · `/` filter · `g` group · `z` zoom · `E` open event in `$EDITOR` ·
`e` edit traces · `Shift+S`/`Shift+X` start/stop · `Ctrl+S` apply & restart ·
`Ctrl+L` clear events · `Ctrl+W` save as preset

**Presets / Settings**
`j/k` move · `enter`/`tab` edit · `space` toggle · `esc` back

**Event kinds**
`↓` call · `↑` return · `→` send · `←` receive

## Config

Persisted to `~/.config/redbug/config.json` (file mode `0600`, dir `0700`). Honors
`$XDG_CONFIG_HOME`. Stores nodes, sessions, presets, and settings. The cookie is stored
in plaintext, so keep the file local and the WebSocket channel trusted.

## Packaging

```sh
mise run package
```

Produces a self-contained `dist/`:

```
dist/
  redbug       launcher (run this)
  redbug-tui   compiled TUI binary (bun --compile)
  server/      Elixir release with bundled ERTS — no system Erlang/Bun needed
```

Run it:

```sh
./dist/redbug
```

The launcher picks a free port, starts the release as a daemon, waits for it, runs the
TUI, and stops the server on exit. Override the cookie with `RB_COOKIE`, the controller
node name with `REDBUG_NODE`.

## Sidecar deployment

Recommended topology for tracing a containerized app: run the **server as a sidecar in
the app's Docker network**. Erlang distribution stays inside the network (no epmd tunnel,
no exposed distribution ports), and only one WebSocket port is exposed to your local TUI.

```
┌ app's docker network ──────────────┐
│  app node  ◄── Erlang dist ──  redbug-server (sidecar)
└───────────────────────────────────┼── WS :4010 ─┘
                                     │
              ssh -L 4010 ───────────┘──►  local TUI
```

### Build the image

Build context is the repo root:

```sh
docker build -t <registry>/redbug-server:latest .
```

Multi-stage: an `hexpm/elixir` build stage produces the release, copied onto a slim
Debian runtime with bundled ERTS. The image binds the WS endpoint to `0.0.0.0:4010`
(`REDBUG_IP=0.0.0.0`, `REDBUG_PORT=4010`); distribution identity comes from the deploy env
(`RELEASE_NODE`, `RELEASE_COOKIE`).

### Run standalone (without kamal)

```sh
docker run -d --name redbug \
  --network <app docker network> \
  -e RELEASE_DISTRIBUTION=name \
  -e RELEASE_NODE=redbug_sidecar@<addr-resolvable-in-network> \
  -e RELEASE_COOKIE=<app cookie> \
  -p 127.0.0.1:4010:4010 \
  <registry>/redbug-server:latest
```

Then from your laptop:

```sh
ssh -N -L 4010:127.0.0.1:4010 user@host          # tunnel only the WS port
REDBUG_HOST=127.0.0.1 REDBUG_PORT=4010 ./dist/redbug-tui   # or: bun run dev
```

In the TUI, add the app node by its in-network name (e.g. `app@...`) and cookie, then
connect.

## kamal accessory

Add to your app's `deploy.yml`:

```yaml
accessories:
  redbug:
    image: <registry>/redbug-server:latest
    roles:
      - web                       # same host(s) as the app
    env:
      clear:
        RELEASE_DISTRIBUTION: name
        RELEASE_NODE: redbug_sidecar@<addr-resolvable-in-network>
        REDBUG_IP: 0.0.0.0
        REDBUG_PORT: 4010
      secret:
        - RELEASE_COOKIE          # same cookie as the app
    port: "127.0.0.1:4010:4010"   # publish only to host localhost
    options:
      network: <app docker network>  # required for distribution to the app node
```

```sh
kamal accessory boot redbug
ssh -N -L 4010:127.0.0.1:4010 user@host
REDBUG_HOST=127.0.0.1 REDBUG_PORT=4010 ./dist/redbug-tui
```

> kamal's own SSH (`kamal app exec`, etc.) is host→container `docker exec`; it is not an
> Erlang-distribution bridge. The accessory approach reuses the Docker network for
> distribution and only borrows SSH to forward the single WS port.

## Security

- **Cookie == RCE.** The cookie is a full remote-code-execution capability on the target.
  The config file is `0600`; keep it local.
- The WebSocket can drive tracing, which is powerful. Bind it to `127.0.0.1` (the sidecar
  publishes to host localhost) and reach it over an SSH tunnel — **never expose it on a
  public interface.** Add authentication before any non-local exposure.
- Erlang distribution is kept inside the Docker network in the sidecar topology; avoid
  exposing distribution/epmd ports publicly.

## Environment variables

| Variable | Component | Default | Purpose |
|---|---|---|---|
| `REDBUG_HOST` | TUI | `127.0.0.1` | Server host the TUI connects to |
| `REDBUG_PORT` | TUI / server | `4010`* | WS port (server pins it when set, else picks a free one) |
| `REDBUG_IP` | server | `127.0.0.1` | WS bind address (`0.0.0.0` in container) |
| `REDBUG_PORT_FILE` | server | — | If set, the chosen port is written here (used by the launcher) |
| `RB_COOKIE` | launcher / dev | `rbtest` | Distribution cookie for the controller |
| `REDBUG_NODE` | launcher | `redbug_controller@127.0.0.1` | Controller node name |
| `RELEASE_NODE` / `RELEASE_COOKIE` / `RELEASE_DISTRIBUTION` | release | — | Standard Elixir release distribution settings |
| `XDG_CONFIG_HOME` | server | `~/.config` | Base dir for `redbug/config.json` |

\* The server uses an OS-assigned free port when `REDBUG_PORT` is unset.
