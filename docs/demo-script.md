# Demo Script

Goal: show redbug-cli as the fastest way to debug a live Elixir node — no agent, no browser, just a
terminal. Keep it tight at 50-65 seconds.

## Setup

Terminal 1, redbug-cli:

```sh
export EDITOR=vim       # or code, nvim, helix
mise run dev
```

Terminal 2, target node:

```sh
iex --name target@127.0.0.1 --cookie rbtest
```

Paste this module into the target `iex` beforehand (or during the demo as part of the flow):

```elixir
defmodule Demo do
  def add(a, b), do: a + b

  def shifted_today do
    Date.shift(~D[2026-06-04], day: -30)
  end
end
```

## Narrative Arc

1. **Connect** — target any live node in seconds
2. **Trace** — define patterns, stream events
3. **Inspect** — open detail, see stack traces
4. **Extend** — open in `$EDITOR` for deeper work

Transition cuts between redbug-cli and the iex target where needed. Keep both terminals on screen
only during cuts that benefit from context.

## Shot List

### 1. Connect to a Node (8-10s)

> "Connect to any running BEAM node. No agent, no restart."

1. Press `n` to add a node.
2. Fill `Node name: target`, `Host: 127.0.0.1`, `Cookie: rbtest`.
   Press `Tab` to move between fields, `Enter` to save.
3. Press `c` to connect.
4. Node glyph changes to ● connected.

### 2. Create a Session (5-7s)

> "Each trace session has its own patterns, limits, and event buffer."

1. Press `s` for new session.
2. Name it `demo`, pick `(blank)` from presets.
3. Press `enter` to open.

### 3. Add a Trace Pattern (10-12s)

> "Patterns use redbug's RTP syntax — plain Elixir references, no DSL."

1. Press `t` to open the trace editor.
2. Press `n` to add a new RTP.
3. Type `Demo.add/2 -> return`.
4. `Enter` to confirm. The pattern is enabled by default.
5. Press `esc` to close.

### 4. Start Tracing & See Events (10-12s)

> "Space is the universal go key — start, restart, retry."

1. Press `space` (bottom hint bar reads `space start`).
2. Switch to the iex terminal and run:

```elixir
Demo.add(1, 2)
Demo.add(40, 2)
```

3. Call and return events appear in the Events table.
4. Let the sparkline and count tick for a moment — shows it's live.

### 5. Inspect Detail & Stack Trace (12-15s)

> "Every event opens into a detail pane with syntax-highlighted payload."

1. Press `t` to open editor, press `n` to add a second pattern:

```text
Date.shift/2 -> return;stack
```

2. Press `Ctrl+S` to apply and automatically restart.
3. In iex, run `Demo.shifted_today()`.
4. Select the new call event with `j`/`k`, press `enter` to open detail.
5. Stack trace is rendered separately below the return value.
6. Press `z` to zoom the detail full-screen, `esc` to close.

### 6. Open in `$EDITOR` (5-8s)

> "Any event can be opened in your editor as an Elixir term."

1. With the event selected, press `v`.
2. `$EDITOR` opens with the full event — kind, ts, pid, mfa, payload, stack.
3. Close the editor.

### 7. Closing Shot (3-5s)

> "redbug-cli — live Elixir tracing from the terminal."

1. Back in the TUI, the trace is still running.
2. Press `x` to stop.
3. Hold on the idle state for a beat.

## README GIF Cut (shorter, ~20s)

1. Connect node (`n` → fill → `c`)
2. New session (`s` → `demo` → `enter`)
3. Add `Demo.add/2 -> return` (`t` → `n` → type → `enter` → `esc`)
4. `space` to start
5. Run `Demo.add(1, 2)` in iex
6. Select event, `enter` for detail
7. Fade out

## Key Reference

| Key | Action |
|---|---|
| `j` / `k` | Move selection |
| `enter` | Open detail / confirm |
| `space` | Start / restart trace |
| `x` | Stop trace |
| `t` | Trace editor |
| `n` | New (node, session, RTP, snippet) |
| `s` | New session / save as snippet |
| `c` | Connect / disconnect |
| `z` | Zoom detail |
| `v` | Open event in $EDITOR |
| `Ctrl+S` | Apply RTP edits + restart |
| `esc` | Back / close |
| `?` | Help |

## Capture Notes

- Terminal: 100-120 columns, large monospace font (JetBrains Mono 14pt+).
- Keep iex beside/below the TUI; hide it when not needed.
- Crop out terminal chrome, window decorations, and OS dock before publishing.
- Save README asset as `docs/demo.gif`, then uncomment the image block in
  [README.md](../README.md).
