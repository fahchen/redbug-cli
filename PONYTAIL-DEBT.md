# Ponytail Debt Ledger

Deliberate shortcuts marked with `ponytail:` comments. Recorded, not yet actioned.

## tui/src/ui.tsx

- **L274** — Flash notice error-only.
  - ceiling: no `warn` level / ⚠ glyph.
  - upgrade: when a `warn` producer exists.

## server/lib/server/ssh_tunnel.ex

- **L32** — SSH port hardcoded `22`.
  - ceiling: no per-node port; `:ssh` can't read `~/.ssh/config`.
  - upgrade: add `ssh_port` field if a non-standard port arises.

- **L168** — `silently_accept_hosts: true` (security-relevant, MITM surface).
  - ceiling: skips known_hosts verify; scoped to dev tool, local-trusted target.
  - upgrade: honor `~/.ssh/known_hosts`, make silent an opt-out. Revisit before any non-local/prod use.

## server/lib/server/schema/node.ex

- **L30** — `port` / `ssh_host` / `ssh_port` stored + round-tripped but dial path ignores them.
  - ceiling: manual-port dialing not wired (Config/SshTunnel).
  - upgrade: when manual-port dialing is needed.

---

4 markers, 0 with no trigger.
