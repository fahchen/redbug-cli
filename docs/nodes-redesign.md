# Nodes page redesign — spec

Status: **spec locked, not started**. Awaiting go + ordering decision.

Scope: nodes page status/spinner/error rework + whole-TUI 8-bit restyle. Two
tracks below; can ship independently.

---

## Track 1 — Node status: spinner + status enum + error

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

## Track 2 — Whole-TUI 8-bit game restyle

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

### Effort

Core in `theme.ts` (add theme) + `App.tsx` render sites (border/HUD/pointer).
Not a rewrite.

---

---

## Track 3 — Session page: auto-connect + retry + banner redesign

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

## Open decisions before build

1. Spinner choice: `simpleDotsScrolling` vs `circleHalves` vs 8-bit block spin.
2. Backend status field shape confirmed: single `status` enum (locked).
3. Track ordering: status/error first, 8-bit restyle, or session track first?
4. 8-bit depth: full restyle (borders/HUD/modals) or just add PICO-8 theme first
   to preview color?
5. Track 3 retry: interval (fixed 2s?), logic layer (A backend recommended),
   manual retry key.
