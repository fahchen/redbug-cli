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
