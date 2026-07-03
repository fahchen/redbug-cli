# Remote nodes

The controller and TUI always run locally (the launcher binds the server to `127.0.0.1`). To
trace a node on another host, the controller only has to reach it over Erlang **distribution**
with a **matching cookie** — nothing is deployed to the target (no agent, sidecar, or code).

```
   local                                    remote host
 ┌─────────────────────────────┐          ┌──────────────────┐
 │ TUI ─ WS(127.0.0.1) ─ controller ──────┼─ epmd  :4369      │
 │                       Erlang dist ─────┼─ app node :<dist> │
 └─────────────────────────────┘          └──────────────────┘
```

## Pick a path

| Your target… | Use | Server change? |
|---|---|---|
| runs in a container on an **SSH-only** host (Kamal, plain Docker) | **[SSH tunnel](#ssh-tunnel-recommended)** — built in | none |
| is on a **routable** network (VPN/WireGuard, LAN, OrbStack machine) | **[Direct](#direct-routable-node)** | none |
| is pre-pinned for **CI / scripting**, or you want to own the tunnel | **[`REDBUG_NODES`](#redbug_nodes--manual-tunnel)** | none |

Every path shares two rules, called out where they bite:

- **Cookie must match.** The distribution cookie is the target's; it is [RCE](#security).
- **Name type must match.** A node is longname *or* shortname for life and Erlang won't bridge
  the two, so the controller must run the same kind — see [distribution mode](#match-the-distribution-mode).

---

## SSH tunnel (recommended)

For a node inside a container on a host you reach only over SSH (Kamal, plain Docker); the
container publishes no ports. Fill the node's SSH details and connect — the controller does the
rest.

On connect it opens one SSH connection to the host and, over it, discovers the container's bridge
IP, the node's (random) distribution port, its **name**, and the release **cookie** (`docker
inspect` / `epmd -names` / `releases/COOKIE`), forwards a local port to the node, and pins that
dial endpoint so distribution goes straight through. No manual `ssh -L`, no `REDBUG_NODES`, no
port pinning; everything is re-discovered on each connect, so it survives redeploys. On
disconnect (or a dropped SSH connection) the tunnel is torn down and the endpoint unpinned.

### Add the node

In the node editor (`n` new / `e` edit on the tree), fill the **over SSH** fields and leave name +
cookie blank — they're discovered on connect (a shortname release's node is `app@<short-host>`,
which you can't guess anyway):

| field | value |
|---|---|
| ssh host | the server to SSH into, e.g. `prod-1.example.com` |
| ssh user | SSH login user (defaults to `$USER`) |
| container | the Kamal `service` name (or a bare container name / id) |
| name / cookie | leave blank — auto-discovered (set them only to override) |

Then press `c`. (Leaving all three SSH fields blank makes it a [direct](#direct-routable-node)
node instead — name + cookie then required.)

### Match the distribution mode

Elixir releases **default to shortnames** (`RELEASE_DISTRIBUTION=sname`, so a Kamal app comes up
as `app@<container-host>`). The controller defaults to longnames, so for a shortname target launch
redbug as shortnames too — **no server change needed**:

```sh
CONTROLLER_DISTRIBUTION=sname ./dist/redbug      # or: … mise run dev
```

Leave it unset for a longname target — e.g. one pinned in `deploy.yml` with
`RELEASE_DISTRIBUTION: name` + `RELEASE_NODE: app@127.0.0.1`.

### Requirements

- **SSH key auth** — publickey only: ssh-agent first (when `SSH_AUTH_SOCK` is set), then a key in
  `~/.ssh`. No passwords. `:ssh` does **not** read `~/.ssh/config`, so there is **no
  `ProxyJump`/bastion** and no `Host` aliases — use the real host.
- **Docker without sudo** — the SSH user runs `docker ps` / `docker inspect` / `docker exec`
  directly (be in the `docker` group).
- **Container match** — Kamal's `service` label (+ `role=web`, newest), falling back to a bare
  container name / id. The name is validated before it reaches the shell.

> **Verified** against a live Kamal shortname app (`CONTROLLER_DISTRIBUTION=sname`, node + cookie
> auto-discovered as `muku@178`): connect → inject redbug → trace `MukuWeb.Endpoint.url/0` →
> capture call/return → disconnect, no server changes. Also against an OrbStack machine (longname,
> OTP 28 → OTP 27).

---

## Direct (routable node)

When the controller can already reach the target's IP — VPN/WireGuard, LAN, or (locally) an
OrbStack machine — dial it with no tunnel. Add the node in the TUI as `app@<host>`, using the
**exact name the node calls itself** (Erlang matches names verbatim), enter the cookie, connect.

Two things the target needs:

1. **Reachability** — the controller must reach `<host>:4369` (epmd) and the node's distribution
   port.
2. **A findable distribution port.** epmd hands out a random high port unless pinned. Either pin
   it (below), or just let the controller discover it. To pin, give the node equal min/max:

   ```sh
   erl -name app@<host> -setcookie <cookie> \
       -kernel inet_dist_listen_min 9100 -kernel inet_dist_listen_max 9100
   ```

   For a release, put those `-kernel` flags in `rel/vm.args.eex` (or `RELEASE_VM_ARGS`).

> **Verified** against an OrbStack Linux machine: `app@<machine-ip>` (pinned dist `9100`, cookie)
> ← controller `redbug_controller@127.0.0.1`; `Node.connect/1` returns `true`, `:rpc` round-trips.

### Finding the distribution port

```sh
# on the target host
epmd -names
# epmd: up and running on port 4369 with data:
# name app at port 9100
```

Or from any `iex`/`erl` that can reach the target's epmd:

```elixir
:erl_epmd.names(~c"prod-1.internal")                 # {:ok, [{~c"app", 9100}]}
:erl_epmd.port_please(~c"app", ~c"prod-1.internal")  # {:port, 9100, 5}
```

---

## `REDBUG_NODES` — manual tunnel

Pin a set of dial endpoints up front via an env var, instead of the interactive
[SSH tunnel](#ssh-tunnel-recommended). Use it for CI / scripting, or when you'd rather own the
`ssh -L` yourself. Each entry is `name@host|dial_ip:port|cookie`, comma-separated:

```sh
REDBUG_NODES="app@prod-1.internal|10.0.0.5:9100|s3cret,worker@prod-2|10.0.0.6:9100|s3cret"
```

- `name@host` — the node's **own** name (its `-name`/`-sname`); distribution verifies it on
  handshake, so it must match exactly. `host` need not resolve (the shim never looks it up), but a
  **longname** node still needs a dotted host or IP (`app@10.0.0.5`, not `app@prod-1`).
- `dial_ip:port` — where the controller actually connects: the node's dist port, or the local end
  of an `ssh -L` tunnel.
- `cookie` — optional; omit (`name@host|ip:port`) to fall back to the controller cookie.

In this mode the node list is **read-only**: env nodes carry an `env` tag, you can only add
sessions under them, and those sessions persist by node name (a node dropping out of
`REDBUG_NODES` hides its sessions until it returns). Manual (config) nodes are hidden while env
mode is active.

### Over an `ssh -L` tunnel

Forward the node's dist port to a local port and point `REDBUG_NODES` at the local end. epmd is
**not** forwarded (the shim doesn't need it). For a **container**, the `-L` target is the
container's bridge IP (the node lives in the container's netns, not the host's loopback):

```sh
# on the server: find the container's IP + dist port
C=$(docker ps --filter label=service=<service> -q | head -1)
docker exec "$C" epmd -names   # → name app at port 44001
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$C"   # → 172.18.0.4

# local 9100 → (server) → container 172.18.0.4:44001
ssh -N -L 9100:172.18.0.4:44001 user@server

# dial the local end; node name must match the container node's own name
REDBUG_NODES="app@127.0.0.1|127.0.0.1:9100|$RELEASE_COOKIE" ./dist/redbug
```

The local port is free to differ from the remote dist port (the shim pins the endpoint, no
re-query), but each tunnelled node needs a **distinct** local port since they all land on
`127.0.0.1`. Pin the container's dist port to reuse a fixed tunnel across redeploys — add to
`deploy.yml`:

```yaml
env:
  clear:
    ERL_AFLAGS: "-kernel inet_dist_listen_min 9100 -kernel inet_dist_listen_max 9100"
```

> **Launching the server by hand.** `mise run dev` handles it, but if you start the server
> yourself, do **not** pass `--name`: the shim loads only once the app starts, so distribution
> must come up *after* boot. Set the name via `CONTROLLER_NODE`
> (`CONTROLLER_NODE=… CONTROLLER_COOKIE=… REDBUG_NODES=… elixir -S mix phx.server`).

---

## How the dial works (the epmd shim)

The controller always boots with a connect-only epmd replacement (`Server.Epmd`, via
`-start_epmd false -epmd_module`):

- a name **pinned** in the endpoint table (by `REDBUG_NODES` or the SSH tunnel) dials its
  `{ip, port}` directly, skipping epmd **and** DNS;
- any **other** name falls back to real epmd.

That's what lets a loopback name like `app@127.0.0.1` over an `ssh -L` tunnel work with no
`lo0`-alias/`sudo` dance and no collision with the controller's own epmd, while ordinary routable
nodes still resolve normally.

## Security

- **Cookie == RCE.** The cookie is full remote-code-execution on the target. The config file is
  `0600`; keep it local.
- Keep the WebSocket on `127.0.0.1` (the default) — **never expose it publicly.**
- Erlang distribution is **unencrypted** unless tunnelled. Don't expose epmd/dist ports to
  untrusted networks; reach them over a VPN or SSH tunnel.
