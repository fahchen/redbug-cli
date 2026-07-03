# Remote nodes

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

The controller always boots with a connect-only epmd replacement (`Server.Epmd`, installed via
`-start_epmd false -epmd_module`): a name pinned in the endpoint table dials its `{ip, port}`
directly (skipping epmd **and** DNS), and any other name falls back to real epmd. `REDBUG_NODES`
pins a comma-separated set of endpoints up front — so an `ssh -L` tunnel onto plain `127.0.0.1`
works with no loopback-alias/`sudo` dance and no collision with the controller's own epmd. The
[built-in SSH tunnel](#built-in-ssh-tunnel-recommended) pins the same table at runtime instead.

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

> **Launching the server by hand.** `mise run dev` handles this, but if you start the server
> yourself, do **not** pass `--name`: the shim module only loads once the app starts, so
> distribution must come up *after* boot. Set the node name via `CONTROLLER_NODE` instead
> (`CONTROLLER_NODE=redbug_controller@127.0.0.1 CONTROLLER_COOKIE=… REDBUG_NODES=… elixir -S mix phx.server`).

### Kamal (Docker) deployments

The target is a [Kamal](https://kamal-deploy.org)-deployed container on a Linux host you reach
only via SSH; the container publishes no ports. The CLI can tunnel to it for you (below), or you
can wire the tunnel by hand ([Manual `ssh -L`](#manual-ssh--l-scripting--ci)).

**The target node must be a longname, either way.** The controller starts as `:longnames`, and
Erlang refuses to connect a longname node to a shortname one. Elixir releases default to
`RELEASE_DISTRIBUTION=sname`, so override it in `deploy.yml` (the cookie comes from the
`RELEASE_COOKIE` secret):

```yaml
env:
  clear:
    RELEASE_DISTRIBUTION: name
    RELEASE_NODE: app@127.0.0.1        # dotted host ⇒ a valid longname
```

#### Built-in SSH tunnel (recommended)

Give the node its SSH details and connect — the controller opens an SSH connection to the host,
discovers the container's bridge IP and the node's (random) distribution port over that same
connection (`docker inspect` + `epmd -names`), forwards a local port to it, and pins the dial
endpoint so distribution goes straight through. No manual `ssh -L`, no `REDBUG_NODES`, no
dist-port pinning; the port is re-discovered on every connect, so it survives redeploys.

In the node editor (`n` new / `e` edit on the tree), fill the fields under **over SSH**:

| field | value |
|---|---|
| name | the container node's own name, e.g. `app@127.0.0.1` |
| cookie | the node's `RELEASE_COOKIE` |
| ssh host | the server to SSH into, e.g. `prod-1.example.com` |
| ssh user | SSH login user (defaults to `$USER`) |
| container | the Kamal `service` name (or a bare container name / id) |

Leave the three SSH fields blank for a directly-dialed node. Press `c` to connect; on disconnect
(or a dropped SSH connection) the tunnel is torn down and the endpoint unpinned.

Requirements:

- **SSH key auth** — publickey only: ssh-agent first (when `SSH_AUTH_SOCK` is set), then a key in
  `~/.ssh`. No passwords. `:ssh` does **not** read `~/.ssh/config`, so there is **no `ProxyJump`/
  bastion** and no `Host` aliases — use the real host.
- **Docker without sudo** — the SSH user runs `docker ps` / `docker inspect` / `docker exec`
  directly (add them to the `docker` group).
- **Container match** — by Kamal's `service` label (+ `role=web`, newest), falling back to a bare
  container name / id. The name is validated before it reaches the shell.

> Verified end to end against an OrbStack machine running dockerized erlang: connect → `:rpc` →
> disconnect, with the dial endpoint pinned to the tunnel and then cleared (OTP 28 → OTP 27).

#### Manual `ssh -L` (scripting / CI)

For env-injected (`REDBUG_NODES`) runs, or when you'd rather own the tunnel, wire it by hand.

**The dist port lives inside the container.** epmd hands out a random high port unless pinned,
and the host's `epmd` can't see it — query it *inside* the container, and grab the container's
bridge IP (the node binds dist on `0.0.0.0`, so it's reachable from the Docker host at that IP):

```sh
ssh user@server
C=$(docker ps --filter label=service=<service> -q | head -1)   # the running app container
docker exec "$C" epmd -names           # → name app at port 44001
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$C"   # → 172.18.0.4
```

**The `ssh -L` target is the container IP, not `127.0.0.1`.** The node lives in the container's
network namespace — the host's loopback has nothing on that port. Forward a local port straight to
`<container-ip>:<dist-port>` (the local port is free to differ; the shim pins the endpoint and
never re-queries, so it doesn't need to match the remote dist port):

```sh
# local 9100 → (server) → container 172.18.0.4:44001
ssh -N -L 9100:172.18.0.4:44001 user@server
```

Then launch the CLI dialing the tunnel's local end, with the node name matching the container
node's own name:

```sh
REDBUG_NODES="app@127.0.0.1|127.0.0.1:9100|$RELEASE_COOKIE" ./dist/redbug
# from source: REDBUG_NODES="app@127.0.0.1|127.0.0.1:9100|$RELEASE_COOKIE" mise run dev
```

Pin the dist port to skip the per-session `epmd -names` lookup and reuse a fixed tunnel — add to
`deploy.yml`:

```yaml
env:
  clear:
    ERL_AFLAGS: "-kernel inet_dist_listen_min 9100 -kernel inet_dist_listen_max 9100"
```

The container IP can still change across deploys; re-check it, or put the app on a Kamal
`network` with a stable alias.

## Security

- **Cookie == RCE.** The cookie is a full remote-code-execution capability on the target.
  The config file is `0600`; keep it local.
- Keep the WebSocket on `127.0.0.1` (the default) — **never expose it on a public interface.**
- Erlang distribution is **unencrypted** unless tunnelled. Don't expose epmd/distribution
  ports to untrusted networks; reach them over a VPN or SSH tunnel.
