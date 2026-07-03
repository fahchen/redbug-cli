# Nodes page redesign — spec

Status: **All three tracks implemented & screenshot-verified. Optional 8-bit polish (block-glyph/hint styling) remains.**

Implementation notes:
- Retry runs inline in the Config GenServer (do_connect in handle_info), same as
  the old synchronous connect_node — so a slow/unreachable dial blocks Config for
  the dial timeout. Pre-existing behavior, not a regression. If it bites, move
  do_connect into a Task. `ponytail:` left inline.
- SessionRoot reads node status into **assigns** (put_node_conn) rather than
  live in render, because musubi only re-renders when assigns change; a
  status-only config_updated would otherwise be skipped and leave a stale glyph.

Scope: nodes page status/spinner/error rework + whole-TUI 8-bit restyle. Two
tracks below; can ship independently.

---

## Track 1 — Node status: spinner + status enum + error  ✅ DONE (verified)

### Backend (`server/`)

- `Server.Stores.NodeStore` state: replace `connected: boolean` with single
  `status: :idle | :connecting | :connected | :error`.
- `connect` command → async:
  - on dispatch: set `:connecting`, broadcast.
  - after `Config.connect_node/1`: set `:connected`, or `:error` (+ `error`
    field), broadcast.
- `disconnect` → `:idle`.
- Regenerate types into `tui/src/generated/musubi.d.ts`.

### Frontend (`tui/src/App.tsx`)

- `NodeRow` icon by status:
  - `:connected` → `●` (green)
  - `:connecting` → spinner
  - else → `○` (grey)
- Spinner: ora `simpleDotsScrolling` (default), alt `circleHalves` — one
  constant to switch, decide at build time. React state + interval, self-drawn.
  - `simpleDotsScrolling` frames: `.  ` `.. ` `...` ` ..` `  .` `   `, ~200ms
  - `circleHalves` frames: `◐ ◓ ◑ ◒`, ~50ms
- Error placement: **detail-header band** at top of right (sessions) panel
  (`App.tsx:416` box):
  - normal: `name · ssh route (if ssh_host: ssh user@host + container) · env
    badge · N sessions`. Cookie NOT shown.
  - `status == :error`: whole band turns red, shows `✖ <error> · c retry`.
- Remove old `<Flash error>` overlay (`App.tsx:439`).

### Rejected alternatives

- Global full-width top banner under Header — rejected: ugly, low info when
  empty.
- Error in bottom StatusBar — rejected: thin, overflows on long errors.
- Frontend-local "connecting" flag (no backend change) — rejected in favor of
  real backend `status` enum (option B).

---

## Track 2 — Whole-TUI 8-bit game restyle  ✅ DONE (core, verified)

Decided: full restyle + dark arcade base. Done so far: PICO-8 dark theme added +
set as default (theme.ts + server default). In progress: heavy panel borders
(PANEL_BORDER), menu-pointer selection, HUD statusbar, block glyphs, RPG modals.

Register: product. No PRODUCT.md yet (optional: `/impeccable teach`).

Reuses existing multi-theme system (`tui/src/theme.ts`) — add one theme +
swap border/glyph constants, not a rewrite.

### Palette — Committed strategy, PICO-8 (new theme entry)

```
bg      #100f1c   (blue-tinted near-black, not pure)
overlay #1d2b53
fg      #fff1e8
dim     #5f574f
border  #29adff
title   #ffec27
accent  #ff77a8
selBg   #7e2553   selFg #fff1e8
on      #00e436   off #5f574f   err #ff004d   warn #ffa300
call #29adff  retn #00e436  send #ffec27  recv #83769c
```

### Elements

- **Borders** = cartridge frame: double-line `╔═╗╚╝` or block `▛▀▜▙▟`,
  replacing single-line border char.
- **Selection** = menu pointer `►` at row start (optionally blinking) + inverted
  bar, replacing soft `selBg`-only highlight.
- **Bottom bar → HUD**: `X/Y connected` as block gauge `SIGNAL ████░░`; hints as
  button prompts `[N]EW [C]ONNECT [Q]UIT` (key letter in title yellow).
- **Modals → RPG dialog box**: double-line textbox, title as raised tab.
- **Spinner (8-bit skin)**: prefer block spin `▖▘▝▗` or `circleHalves` over
  plain dots.
- **Glyphs**: node status `●` → `█`; session `•` → `▸`. Retro copy, light touch,
  don't hurt readability.

### Font (8-bit pixel look)

TUI runs in a terminal; the app cannot set the font (the terminal owns it). Two
levers:
- ttyd screenshot host: pass `-t fontFamily=...` to render with a pixel font.
- End users: document a recommended terminal font; can't enforce.

Pitfall: most 8-bit pixel fonts (e.g. Press Start 2P) LACK box-drawing glyphs
(`╔═╗ ▛▀`) and will break the cartridge borders. Use a pixel/bitmap monospace
that ships box-drawing: **Terminus** or **Cozette**. Verify borders render
before committing to a font.

### Effort

Core in `theme.ts` (add theme) + `App.tsx` render sites (border/HUD/pointer).
Not a rewrite.

---

---

## Track 3 — Session page: auto-connect + retry + banner redesign  ✅ DONE (verified)

### Auto-connect + retry

- Entering a session page auto-connects its parent node. No manual connect on
  session page.
- On failure: keep retrying. Stop after **3 consecutive failures**. Then human
  can retry manually (manual retry resets the counter).
- One success resets the consecutive-failure counter.
- Nodes page keeps manual `c` connect (auto-connect is session-entry only).
- **Node connection error must show on the session page.** Session page needs
  node connection status/error, which is cross-store: node lives under
  NodesRoot, session under SessionRoot. SessionScreen has `nodeId` — subscribe
  to the node's `status`/`error` at build time.
  - Proposed placement (pending confirm): render the connect error in the
    Events panel body (where `No events yet · ⇧S to start` shows), since a
    down node means no events anyway; plus `✖` glyph (red) in the breadcrumb.
    Retry hint alongside. Alternatives: Flash overlay / StatusBar.

Open (recommended defaults, not confirmed):
- Retry interval: fixed 2s (vs backoff). — pending
- Logic layer: **(A) backend** node reconnect policy (add `retry_count` +
  retry loop to NodeStore, consistent with Track 1 `status` enum, survives
  leaving the session page) vs (B) frontend mount effect. Recommend A. — pending
- Manual retry key on session page (e.g. `c`). — pending

### Banner redesign (locked)

Consistency: home page Header is a breadcrumb (`redbug · nodes ▸ sessions`) with
NO status text; node status shows as a glyph (`●/○`) in rows + `X/Y connected`
in the StatusBar. Session page must match that pattern, not a `name +
connecting…` text banner.

```
redbug · nodes ▸ myapp ▸ ⠙ hi          ← Header breadcrumb; status glyph before session name
▸ Events   Console                       ← tab row
┌ Events (0) ─────────────── sort:ts↓ · group:none ┐   ← sort/group meta on Events border, right-aligned
```

- Row 1 = breadcrumb + connection status as a **glyph** before the session name:
  `⠙` (connecting spinner) / `●` (live) / `✖` (failed, red). Failure detail /
  retry count goes to StatusBar or error flash, NOT row 1.
- Row 2 = tab row: `▸ Events   Console`, pointer `▸` marks active. Remove
  `[/] switch` label.
- sort/filter/group meta moves from row 1 onto the **Events panel top border
  line, right-aligned** (`┌ Events (n) ── … sort:ts↓ · group:none ┐`).
  - RISK: opentui `box` `title` is left-aligned single string. Right-aligned
    border text may need `titleAlignment` / right-title support; if absent,
    draw the border manually. **Verify at build time.**
### StatusBar (bottom bar) slimming (locked)

Current: `◇ idle 254s · 0 evt · buf 0/500 · <sparkline>` + long hints.
Problems: the idle-flat sparkline renders as a long `▁▁▁…` underline;
liveness `idle Ns / live` is noise; string too long.

- Drop trace-liveness entirely (`◇ idle Ns` / `● live`). Connection status is
  single-sourced from the row-1 breadcrumb glyph — do NOT repeat it in the
  StatusBar.
- Sparkline: render only when there's real throughput; hide when idle
  (all-zero buckets) so the long underline is gone. (`SessionScreen:997`
  `sparkline()`, gated by the `running && has-activity` condition.)
- Left text: counts only, drop `evt`/`buf` labels:
  - idle: `0/500`
  - active: `128 · 3/500 ▂▅█▃▂`  (event count · buf/keep · spark)
- Hints: keep as-is for now (not cut).

### Tab-switch keybinding (locked)

Remove `[` / `]` keys and `[/]` label. Two bindings, both switch tabs:

| key | action |
|---|---|
| `L` / `H` (Shift) | next / prev tab (vim-directional) |
| `Ctrl+→` / `Ctrl+←` | next / prev tab |

Note: lowercase `h`/`l` collide (`l` = limits), so vim binding uses Shift `H`/`L`.

---

## Decisions (resolved)

1. ✅ Spinner: `circleHalves` for the 1-wide status glyph (row/breadcrumb);
   `simpleDotsScrolling` available for inline labels. (`useSpinner` in ui.tsx)
2. ✅ Backend status field: single `status` enum.
3. ✅ Track order: 1 → 3 → 2.
4. ✅ 8-bit depth: full restyle + dark arcade base.
5. ✅ Track 3 retry: fixed 2s, backend (A), manual retry key `c`.

## Track 2 progress

- ✅ PICO-8 dark theme added + set default (theme.ts + server default + user config).
- ✅ Heavy borders (`PANEL_BORDER`) on all framed panels: Nodes, sessions,
  Events, Detail, zoom, Console History/detail, Overlay (→ RPG modals).
- ✅ Menu-pointer (►) selection on SessionRow, ConsoleTab HistoryRow, PickRow.
- ✅ HUD statusbar gauge on nodes page (`▮▮▯ 0/3 up` block gauge).
- ✅ Border style set to `double` (clear cartridge frame; `heavy` too subtle in font).
- ✅ Button-prompt hint styling: StatusBar keys pop in title hue, labels dim.
- ✅ Font: Terminus/Cozette recommendation added to docs/testing.md ttyd cmd.
- (Kept event/kind arrow glyphs as-is — clear + column-stable.)
- ⬜ Font: recommend Terminus/Cozette in the ttyd host + docs (box-drawing safe).
