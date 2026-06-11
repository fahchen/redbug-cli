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

**Tree**
`j/k` move · `enter` open session · `n` node · `s` session · `e` edit node ·
`c` connect/disconnect · `d` delete · `p` presets · `,` settings · `?` help · `q` quit

**Session**
`enter` detail · `o` sort · `/` filter · `g` group · `l` limits · `z` zoom · `E` open event in `$EDITOR` ·
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
  redbug       single-file binary (run this) — bun --compile, embeds the server release
  redbug-tui   standalone TUI binary — only needed to reach a remote sidecar server
```

`dist/redbug` is a bun `--compile` executable with the `server` release (ERTS bundled)
embedded as a tarball. On first run it extracts the release to a per-build cache dir
(`~/Library/Application Support/redbug/<build>/`), spawns it as the controller node, waits
for its WebSocket port, then renders the TUI against it. Quitting the TUI tears the
controller down. macOS arm64 only; no system Erlang or Bun needed on the target.

```sh
./dist/redbug
```

The controller node is `redbug_controller@127.0.0.1` (override with `CONTROLLER_NODE`);
each target node's cookie is entered in the TUI when you add it.

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

Build context is the repo root (swap in your own registry/app values):

```sh
docker build -t ghcr.io/fahchen/redbug-server:latest .
```

Multi-stage: an `hexpm/elixir` build stage produces the release, copied onto a slim
Debian runtime with bundled ERTS. The image binds the WS endpoint to `0.0.0.0:4010`
(`REDBUG_IP=0.0.0.0`, `REDBUG_PORT=4010`); distribution identity comes from the deploy env
(`RELEASE_NODE`, `RELEASE_COOKIE`).

### Run standalone (without kamal)

```sh
docker run -d --name redbug \
  --network my_app \
  -e RELEASE_DISTRIBUTION=name \
  -e RELEASE_NODE=redbug_sidecar@redbug \
  -e RELEASE_COOKIE=my_app_cookie \
  -p 127.0.0.1:4010:4010 \
  ghcr.io/fahchen/redbug-server:latest
```

`--network my_app` joins the app's Docker network; `RELEASE_NODE`'s host part
(`redbug` — the container name) must be resolvable there; `RELEASE_COOKIE` must match the
app's cookie.

Then from your laptop:

```sh
ssh -N -L 4010:127.0.0.1:4010 deploy@example.com   # tunnel only the WS port
REDBUG_HOST=127.0.0.1 REDBUG_PORT=4010 ./dist/redbug-tui   # or: bun run dev
```

In the TUI, add the app node by its in-network name (e.g. `my_app@my_app`) and cookie,
then connect.

## kamal accessory

Add to your app's `deploy.yml`:

```yaml
accessories:
  redbug:
    image: ghcr.io/fahchen/redbug-server:latest
    roles:
      - web                       # same host(s) as the app
    env:
      clear:
        RELEASE_DISTRIBUTION: name
        RELEASE_NODE: redbug_sidecar@redbug
        REDBUG_IP: 0.0.0.0
        REDBUG_PORT: 4010
      secret:
        - RELEASE_COOKIE          # same cookie as the app
    port: "127.0.0.1:4010:4010"   # publish only to host localhost
    options:
      network: my_app             # required for distribution to the app node
```

```sh
kamal accessory boot redbug
ssh -N -L 4010:127.0.0.1:4010 deploy@example.com
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
| `RB_COOKIE` | dev | `rbtest` | Distribution cookie for the controller (`mise run dev`) |
| `CONTROLLER_NODE` | server | `redbug_controller@127.0.0.1` | Controller node name |
| `RELEASE_NODE` / `RELEASE_COOKIE` / `RELEASE_DISTRIBUTION` | release | — | Standard Elixir release distribution settings |
| `XDG_CONFIG_HOME` | server | `~/.config` | Base dir for `redbug/config.json` |

\* The server uses an OS-assigned free port when `REDBUG_PORT` is unset.
