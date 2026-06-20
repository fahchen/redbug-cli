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
  redbug-tui   standalone TUI binary — only needed to attach to a separately-running server
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

## Remote node

The controller and TUI always run locally (the launcher spawns the server bound to
`127.0.0.1`). To trace a node on another host, the controller only needs to reach that node
over Erlang distribution — its **epmd** port (`4369`) and its **distribution** port — with a
matching cookie. No agent, sidecar, or code is deployed to the target.

```
   local                                    remote host
 ┌─────────────────────────────┐          ┌──────────────────┐
 │ TUI ─ WS(127.0.0.1) ─ controller ──────┼─ epmd  :4369      │
 │                       Erlang dist ─────┼─ app node :<dist> │
 └─────────────────────────────┘          └──────────────────┘
```

Two requirements on the target node:

1. **Pin the distribution port.** epmd otherwise hands out a random high port, which a
   firewall or `ssh -L` can't forward. Pin it with equal min/max:

   ```sh
   erl -name app@<host> -setcookie <cookie> \
       -kernel inet_dist_listen_min 9100 -kernel inet_dist_listen_max 9100
   ```

   For a release, put `-kernel inet_dist_listen_min 9100 -kernel inet_dist_listen_max 9100`
   in `rel/vm.args.eex` (or `RELEASE_VM_ARGS`).

2. **Reachability.** The controller must reach `<host>:4369` and `<host>:9100`. Simplest is a
   **routable address** — VPN/WireGuard, LAN, or (locally) an OrbStack machine IP — so you
   connect directly with no tunnel.

Then in the TUI add the node as `app@<host>` using the **same host/IP the node names itself**
(Erlang matches node names exactly), enter its cookie, and connect.

> Verified end-to-end against an OrbStack Linux machine: remote node
> `app@<machine-ip>` (pinned dist `9100`, cookie) ← local controller
> `redbug_controller@127.0.0.1`; `Node.connect/1` returns `true` and `:rpc` round-trips,
> including across an OTP 28 → OTP 27 version gap.

## REDBUG_NODES — epmd-free connect (SSH-friendly)

Set `REDBUG_NODES` and the controller boots with a connect-only epmd replacement
(`Server.Epmd`, installed via `-start_epmd false -epmd_module`). Distribution then dials each
target's `{ip, port}` straight from the env var, skipping epmd **and** DNS — so an `ssh -L`
tunnel onto plain `127.0.0.1` works with no loopback-alias/`sudo` dance and no collision with
the controller's own epmd. This is the recommended path for tunnelled or non-routable nodes.

`REDBUG_NODES` is a comma-separated list; each entry is `name@host|dial_ip:port|cookie`:

- `name@host` — the node's **own** name (the `-name` it was started with). Distribution verifies
  this on handshake, so it must match exactly. `host` need not resolve — the shim never looks it
  up — but a longname node still requires a **dotted host or an IP** (`app@prod-1.internal` or
  `app@10.0.0.5`, not bare `app@prod-1`); the BEAM rejects an undotted longname.
- `dial_ip:port` — where the controller actually connects: the node's distribution port, or the
  local end of an `ssh -L` tunnel.
- `cookie` — optional; omit (`name@host|ip:port`) to fall back to the controller cookie.

```sh
REDBUG_NODES="app@prod-1.internal|10.0.0.5:9100|s3cret,worker@prod-2.internal|10.0.0.6:9100|s3cret"
```

In this mode the node list is **read-only**: env nodes show an `env` tag, you can only add
sessions under them (no edit/delete/new-node), and the sessions you create persist by node name
— if a node later drops out of `REDBUG_NODES` its sessions auto-hide, and reappear if it comes
back. Manual (config) nodes are hidden while env mode is active.

### Find a node's distribution port

epmd hands out a random high port unless it's pinned. To discover it, ask epmd on the target
host:

```sh
# on the target host
epmd -names
# epmd: up and running on port 4369 with data:
# name app at port 9100
```

or from any `iex`/`erl` shell that can reach the target's epmd:

```elixir
:erl_epmd.names(~c"prod-1.internal")                 # {:ok, [{~c"app", 9100}]}
:erl_epmd.port_please(~c"app", ~c"prod-1.internal")  # {:port, 9100, 5}
```

Pinning the port (`-kernel inet_dist_listen_min 9100 -kernel inet_dist_listen_max 9100`) lets you
skip the lookup and hard-code `9100`.

### Over SSH

Forward the target's distribution port to a local port, then point `REDBUG_NODES` at the local
end. epmd is **not** forwarded — the shim doesn't need it. The `-L` target is the address the
node binds on the remote (here it listens on the remote's loopback as `app@127.0.0.1`, pinned to
`9100`):

```sh
# forward the remote node's dist port to local 9100
ssh -N -L 9100:127.0.0.1:9100 user@prod-1

# controller dials the local tunnel end; node name must match the node's own name
REDBUG_NODES="app@127.0.0.1|127.0.0.1:9100|s3cret" mise run dev
```

This is why the shim matters: connecting to `app@127.0.0.1` normally hits the controller's own
epmd on `127.0.0.1:4369` — the shim resolves the dial endpoint directly, so loopback names work
with no epmd collision, no `lo0` alias, no `sudo`. Each tunnelled node needs a distinct local
port (`9100`, `9101`, …) since they all land on `127.0.0.1`.

> **Launching separately in env mode.** `mise run dev` handles this, but if you start the server
> by hand, do **not** pass `--name`: the shim module only loads once the app starts, so
> distribution must come up *after* boot. Set the node name via `CONTROLLER_NODE` instead
> (`CONTROLLER_NODE=redbug_controller@127.0.0.1 CONTROLLER_COOKIE=… REDBUG_NODES=… elixir -S mix phx.server`).

## Security

- **Cookie == RCE.** The cookie is a full remote-code-execution capability on the target.
  The config file is `0600`; keep it local.
- Keep the WebSocket on `127.0.0.1` (the default) — **never expose it on a public interface.**
- Erlang distribution is **unencrypted** unless tunnelled. Don't expose epmd/distribution
  ports to untrusted networks; reach them over a VPN or SSH tunnel.

## Environment variables

| Variable | Component | Default | Purpose |
|---|---|---|---|
| `REDBUG_HOST` | TUI | `127.0.0.1` | Server host the TUI connects to |
| `REDBUG_PORT` | TUI / server | `4010`* | WS port (server pins it when set, else picks a free one) |
| `REDBUG_NODES` | server | — | Comma-separated env-injected nodes (epmd-free): `name@host\|dial_ip:port\|cookie` |
| `REDBUG_PORT_FILE` | server | — | If set, the chosen port is written here (used by the launcher) |
| `RB_COOKIE` | dev | `rbtest` | Distribution cookie for the controller (`mise run dev`) |
| `CONTROLLER_NODE` | server | `redbug_controller@127.0.0.1` | Controller node name |
| `RELEASE_NODE` / `RELEASE_COOKIE` / `RELEASE_DISTRIBUTION` | release | — | Standard Elixir release distribution settings |
| `XDG_CONFIG_HOME` | server | `~/.config` | Base dir for `redbug/config.json` |

\* The server uses an OS-assigned free port when `REDBUG_PORT` is unset.
