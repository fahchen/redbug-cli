# redbug-cli — Architecture

## Domain Model

```
Node ──▸ Session ──▸ Traces (RTP) ──▸ Events

  │          │           │
  │          └─ Console (per-session code runner)
  └─ Presets (reusable trace templates)
               Snippets (reusable code library)
```

- **Node**: a BEAM node target (Erlang/Elixir). Connected over Erlang distribution.
- **Session**: a trace session on a node, with its own RTP list, limits, and event buffer.
- **Trace (RTP)**: a redbug trace pattern, e.g. `Demo.add/2 -> return`.
- **Event**: a single call/return/send/recv captured by an active trace.
- **Console**: per-session code runner — execute Elixir or Erlang code on the target node.
- **Preset**: reusable template of traces + limits.
- **Snippet**: reusable code block for the Console.

## One BEAM

The controller and the TUI are one Elixir application (`server/`) in one BEAM. There is no WebSocket and no second process.

```
Server.Supervisor
├── Server.PubSub            local topic broadcasts (a Registry with duplicate keys)
├── Server.Config            config + node status in ETS, persisted to config.json
├── Server.SshTunnel         SSH tunnels to container nodes
├── Server.Trace.*           one redbug runner per session (Registry + DynamicSupervisor)
├── Server.Remote.*          one console runner per session (Registry + DynamicSupervisor)
└── Server.Tui               the Terra TUI (a temporary Task, the last child)
```

- `Server.Tui` runs `Terra.run/2` with `Server.Tui.App`. While the TUI holds the terminal, the logger writes to `REDBUG_SERVER_LOG` (default `/tmp/redbug-server.log`). When the TUI quits, the BEAM stops. `config/test.exs` turns the TUI off (`config :server, :tui, false`), because the tests drive the app headless with `Terra.Test`.
- The screens call `Server.Config`, `Server.Trace`, and `Server.Remote` directly in `update/2`.
- `Server.Tui.Bridge` subscribes to the `Server.PubSub` topics (`"config"`, the trace topic, and the console topic of the open session). It sends each burst of updates to the Terra runtime as one event with `GenServer.cast(pid, {:event, m})`.
- Without distribution (`REDBUG_DIST=off`), the local nodes, sessions, presets, and snippets work, and each connect fails with `:distribution_off` (see `Server.Dist`).

## Tech Stack

| Layer | Technology |
|---|---|
| Controller | Elixir, redbug |
| TUI | [Terra](https://github.com/uminocelo/terra) at the pinned commit of PBeam, with no change |
| Colors | 256-color palette, tokyo-night roles (`Server.Tui.Theme`) |
| Code highlight | `makeup_elixir` (`Server.Tui.Highlight`) |
| Persistence | Elixir `JSON` |

[terra-gaps.md](terra-gaps.md) records each feature of the old Bun TUI that the Terra TUI cuts or simplifies.

## Screen Inventory

Each overlay of the old Bun TUI is a full-screen page. Press `?` on a screen for its keys.

### 1. Nodes (`server/lib/server/tui/app.ex`)

The node list, the node detail, and the sessions pane of the selected node.

| Key | Action |
|---|---|
| `j` / `k`, `↓` / `↑` | Move selection |
| `enter` / `tab` / `→` | Go to the sessions pane |
| `n` | New node (in the pane: new session) |
| `e` | Edit node |
| `r` | Rename session (in the pane) |
| `c` | Connect / disconnect |
| `d` / `⌃D` | Delete (asks) / delete (does not ask) |
| `<number>g` | Go to the session of that number (in the pane) |
| `p` | Presets |
| `l` | Snippets |
| `,` | Settings |
| `?` | Help |
| `q` | Quit (asks) |

### 2. Session events (`server/lib/server/tui/session.ex`)

Live trace event stream. Events tab (default) + Console tab.

| Key | Action |
|---|---|
| `j` / `k` | Move selection |
| `enter` | Open the detail page (`⌃N` / `⌃P` next / previous event) |
| `space` | Start / restart / reconnect |
| `x` | Stop trace |
| `a` | Apply RTP edits + restart |
| `t` | Trace editor (`⌃W` save as preset, `i` import from a preset) |
| `o` | Sort |
| `/` | Filter (Tab changes the scope) |
| `g` | Cycle grouping |
| `f` | Fold call + return into one row |
| `l` | Limits |
| `e` | Error detail |
| `d` / `⌃D` | Delete event (asks) / delete (does not ask) |
| `⌃L` | Clear events |
| `[` / `]` | Switch Events ⇄ Console |
| `,` | Settings |
| `esc` | Back to the nodes (asks while the trace runs) |
| `?` | Help |

### 3. Session console (`server/lib/server/tui/console.ex`)

Per-session code runner. The code is a single-line input; a line break shows as `↵`.

| Key | Action |
|---|---|
| `j` / `k` | Move selection |
| `n` | New execution (pick snippet, compose) |
| `e` | Edit + run selected |
| `r` | Run selected as-is |
| `s` | Save as snippet |
| `d` / `⌃D` | Delete (asks) / delete (does not ask) |
| `x` | Force-stop running execution |
| `⌃L` | Clear history |
| `⌃F` / `⌃B` | Scroll the detail by a page |
| `[` / `]` | Switch to Events |
| `esc` | Back |
| `?` | Help |

### 4. Presets (`server/lib/server/tui/presets.ex`)

CRUD for reusable trace templates (traces + limits).

| Key | Action |
|---|---|
| `j` / `k` | Move |
| `enter` / `tab` | Focus traces |
| `n` | New preset / add pattern |
| `e` | Edit pattern |
| `r` | Rename |
| `l` | Limits |
| `d` / `⌃D` | Delete (asks) / delete (does not ask) |
| `,` | Settings |
| `esc` | Back |
| `?` | Help |

### 5. Snippets (`server/lib/server/tui/snippets.ex`)

CRUD for reusable code blocks. The code is a single-line input; a line break shows as `↵`.

| Key | Action |
|---|---|
| `j` / `k` | Move |
| `e` | Edit code |
| `n` | New snippet |
| `r` | Rename |
| `f` | Format code |
| `d` / `⌃D` | Delete (asks) / delete (does not ask) |
| `⌃F` / `⌃B` | Scroll the code by a page |
| `#g` | Jump to snippet # |
| `,` | Settings |
| `esc` | Back |
| `?` | Help |

### 6. Settings (`server/lib/server/tui/settings.ex`, from `,`)

Global preferences: theme, default sort, column visibility, limits, hints, console timeout.

| Key | Action |
|---|---|
| `j` / `k` | Move |
| `space` / `enter` / `right` / `l` | Toggle or cycle |
| `esc` | Close |
| `?` | Help |

## Source Map

```
server/lib/server/
├── application.ex          Supervision tree; starts distribution unless REDBUG_DIST=off
├── pub_sub.ex              Local topic broadcasts (Registry)
├── config.ex               Config + node status (ETS), persistence, connect
├── trace.ex, trace/        redbug runners, patterns, signature
├── remote.ex, remote/      Console runners, the worker injected into the target
├── tui.ex                  Starts the Terra TUI and the log file
└── tui/
    ├── app.ex              Terra app: nodes screen, node form, sessions pane, screen routing
    ├── bridge.ex           PubSub subscriptions to batched Terra events
    ├── session.ex          Session screen (events, editor, detail, overlays as pages)
    ├── console.ex          Console tab
    ├── presets.ex          Presets screen
    ├── snippets.ex         Snippets screen
    ├── settings.ex         Settings screen
    ├── highlight.ex        makeup_elixir to 256-color segments
    ├── theme.ex            tokyo-night roles to 256 colors
    └── ui.ex               Shared view parts (fit, chip, hints, page, confirm, help)
```

## Global Conventions

- **`space`** is the universal "go" action — start, restart, retry. Never destructive.
- **`x`** is stop. Destructive, so its own key.
- **`?`** opens the contextual Help page from every screen.
- **`esc`** goes back: closes page → exits screen → returns to the nodes.
- **`d`** shows a confirm page; **`⌃D`** deletes immediately (no confirm).
- **Hints bar** shows the most-used keys for the current focus (the `show_hints` setting). Full keymap is in Help (`?`).
- **Ctrl+S** is not a key: the terminal reads it as XOFF in the raw mode of OTP, so `a` applies the edits.
