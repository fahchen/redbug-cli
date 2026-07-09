# redbug-cli TUI — Architecture

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
- **Console**: per-session code runner — execute Elixir code on the target node via `$EDITOR`.
- **Preset**: reusable template of traces + limits.
- **Snippet**: reusable Elixir code block for the Console.

All state is server-authoritative (Elixir/Phoenix), synced to the TUI via musubi (JSON Patch over WebSocket).

## Tech Stack

| Layer | Technology |
|---|---|
| Server | Elixir / Phoenix + musubi |
| TUI runtime | Bun + React 19 |
| Renderer | `@opentui/react` (terminal UI) |
| State sync | `@musubi/react` (StoreProxy + snapshot) |
| Code highlight | tree-sitter (Elixir grammar, WASM) |
| Editor | `$EDITOR` (subprocess) |

## Design Principles

1. **Borders as accents, not frames.** Panels read as colored margins; active pane gets
   a brighter border, inactive is subtle.
2. **Color-weight hierarchy over dividers.** `text` vs `textMuted` separates primary
   from secondary. Almost no rule lines.
3. **Keyboard-first.** Every action has a keybinding. Hint bar shows common keys;
   Help overlay (`?`) shows all.
4. **One overlay primitive: `Overlay` (ui.tsx) + `DialogSelect`** — fuzzy-filtered
   list picker used everywhere (sort, filter scope, snippet picker, preset picker).
5. **Semantic theme tokens.** `theme.ts` exports `theme` (light/dark customizable)
   with `primary`, `error`, `warning`, `success`, `text`, `textMuted`, `background*`,
   `border*`, `selectedForeground`.
6. **No hand-written components.** UI uses only OpenTUI built-ins (`<box>`, `<text>`,
   `<input>`, `<select>`, `<scrollbox>`, `<code>`, `<tab-select>`) plus shared
   components from `ui.tsx`.

## Screen Inventory

### 1. Tree (`App.tsx` + `Tree.tsx` + `NodeModal.tsx`)
Node/Session tree. Entry point for connecting, creating sessions, and navigating.

| Key | Action |
|---|---|
| `j` / `k` | Move selection |
| `enter` | Enter session / open |
| `n` | New node |
| `s` | New session |
| `e` | Edit node |
| `c` | Connect / disconnect |
| `d` / `⌃D` | Delete / delete (no confirm) |
| `p` | Preset manager |
| `l` | Snippet manager |
| `,` | Settings |
| `?` | Help |
| `q` | Quit |

### 2. Session Events (`SessionScreen.tsx` + `SessionEvents.tsx` + `SessionDetail.tsx`)
Live trace event stream. Events tab (default) + Console tab.

| Key | Action |
|---|---|
| `j` / `k` | Move selection |
| `enter` | Open detail pane |
| `space` | Start / restart / retry trace |
| `x` | Stop trace |
| `t` | Trace editor (RTP) |
| `o` | Sort overlay |
| `/` | Filter overlay |
| `g` | Cycle grouping |
| `l` | Limits overlay |
| `z` | Zoom detail |
| `v` | View event in `$EDITOR` |
| `⌃S` | Apply RTP edits + restart |
| `⌃L` | Clear events |
| `[` / `]` | Switch Events ⇄ Console |
| `esc` | Back to Tree |
| `?` | Help |

### 3. Session Console (`ConsoleTab.tsx`)
Per-session Elixir code runner. Execute code on the target node.

| Key | Action |
|---|---|
| `j` / `k` | Move selection |
| `n` | New execution (pick snippet, compose in `$EDITOR`) |
| `e` | Edit + run selected |
| `r` | Run selected as-is |
| `v` | View full code + output in `$EDITOR` |
| `s` | Save as snippet |
| `d` / `⌃D` | Delete / delete (no confirm) |
| `x` | Force-stop running execution |
| `⌃L` | Clear history |
| `[` / `]` | Switch to Events |
| `esc` | Back to Tree |
| `?` | Help |

### 4. Presets (`PresetManager.tsx`)
CRUD for reusable trace templates (traces + limits).

| Key | Action |
|---|---|
| `j` / `k` | Move |
| `enter` / `tab` | Focus traces |
| `n` | New preset / add pattern |
| `e` | Edit pattern |
| `r` | Rename |
| `l` | Limits |
| `d` / `⌃D` | Delete / delete (no confirm) |
| `esc` | Back to Tree |
| `?` | Help |

### 5. Snippets (`SnippetManager.tsx`)
CRUD for reusable Elixir code blocks. Code edited in `$EDITOR`.

| Key | Action |
|---|---|
| `j` / `k` | Move |
| `e` | Edit in `$EDITOR` |
| `n` | New snippet |
| `r` | Rename |
| `f` | Format code |
| `d` / `⌃D` | Delete / delete (no confirm) |
| `#g` | Jump to snippet # |
| `esc` | Back to Tree |
| `?` | Help |

### 6. Settings (`SettingsScreen.tsx`, overlay from `,`)
Global preferences: theme, default sort, column visibility, limits, hints, console timeout.

| Key | Action |
|---|---|
| `j` / `k` | Move |
| `space` / `enter` / `right` / `l` | Toggle or cycle |
| `esc` | Close |
| `?` | Help |

## Source Map

```
tui/src/
├── App.tsx                 Tree page (nodes + sessions)
├── Tree.tsx                NodeRow, SessionRow, NodeDetailBand, EmptyTree
├── NodeModal.tsx           Tree modal layer (help, new/edit node, new session)
│
├── SessionScreen.tsx       Session page orchestrator (events + console tabs)
├── SessionEvents.tsx       Event list rendering (ColumnHeader, EventRow, Cell)
├── SessionDetail.tsx       Detail pane (DetailMeta, EventDetailBody)
├── SessionEditor.tsx       Trace editor overlay (RTP list, add/edit, import)
├── SessionOverlays.tsx     Filter, sort, limits, help, confirm, zoom overlays
├── SessionStatus.tsx       SessionStat status display
├── ConsoleTab.tsx          Console tab (code execution history)
│
├── PresetManager.tsx       Preset CRUD page
├── SnippetManager.tsx      Snippet CRUD page
├── SettingsScreen.tsx      Settings overlay
│
├── ui.tsx                  Shared components (Overlay, Panel, StatusBar, Chip, etc.)
├── ConfirmOverlay.tsx      Shared confirm dialog
├── RtpCheatSheet.tsx       RTP syntax reference
├── DialogSelect.tsx        Fuzzy-filtered list picker
│
├── sessionHelpers.ts       Pure functions (processEvents, sparkline, elixirTerm)
├── sessionTypes.ts         Types + constants (Sort, Filter, COL, RTP_EXAMPLES)
├── useSessionLiveness.ts   Liveness tracking + sparkline hook
├── types.ts                Rtp, TraceEvent type aliases
│
├── theme.ts                Theme tokens (dark/light/PICO-8/catppuccin/...)
├── musubi.ts               musubi store roots + dispatcher
├── limits.ts               Limits parsing + formatting
├── editor.ts               $EDITOR subprocess helper
├── treesitter.ts           Tree-sitter code highlighting
├── fuzzy.ts                Fuzzy matching for DialogSelect
│
├── index.tsx               Entry point
└── main.tsx                Bun compile entry
```

## Global Conventions

- **`space`** is the universal "go" action — start, restart, retry. Never destructive.
- **`x`** is stop. Destructive, so its own key.
- **`?`** opens the contextual Help overlay from every screen.
- **`esc`** goes back: closes overlay → closes detail → exits screen → returns to Tree.
- **`d`** shows a confirm prompt; **`⌃D`** deletes immediately (no confirm).
- **Hints bar** shows the most-used keys for the current focus. Full keymap is in Help (`?`).
- **`$EDITOR`** is used for composing code (Console `n`/`e`), viewing events (`v`), and editing snippets (`e`).
