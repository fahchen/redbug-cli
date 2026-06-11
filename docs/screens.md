# redbug-cli TUI — Screen Design

Domain model: **Node ▸ Session ▸ Traces → Events**, plus reusable **Presets**.
Built on musubi (server-authoritative, JSON Patch over Phoenix ws) + opentui/React on Bun.

## Screen Inventory

1. **Tree** — full-screen Node▸Session tree. Management + navigation. Root.
2. **Session Events** — left events list / right detail pane (detail shown on `enter`).
3. **Trace Editor** — overlay *inside* Session Events (`e`), edit RTP list + save-as-preset.
4. **Preset Manager** — full screen, entered via `p` from Tree. Preset CRUD.
5. **Node Editor** — overlay (Tree `n`/`e`), node add/edit (name, cookie).
6. **Settings** — full screen, entered via `,` from Tree. Column visibility + global prefs.
7. **Help** — overlay (`?` from Tree), keybindings + kind legend.

Entry keys (`p` presets, `,` settings, `?` help) are wired on the **Tree only**;
the other screens return to Tree via `esc` first.

Navigation:
```
S1 Tree ──enter session──> S2 Session Events ──esc──> S1
   │ n/e (node) overlays S5    │ enter event -> right detail pane
   │ p -> S4, , -> S6, ? -> S7 │ e -> S3 trace editor overlay · l -> limits
   │ s -> new-session flow     │ z -> zoom overlay, ⇧E -> $EDITOR
```

---

## Screen 1 — Tree
Full-screen Node▸Session tree. Manage nodes/sessions; enter a session to view its events.

```
┌─ redbug · nodes ▸ sessions ─────────────────┐
│ ● app@host1   (2)                            │
│     • sess-A   [running]                     │
│     • sess-B   [stopped]                     │
│ ○ app@host2   (1)                            │
│     • sess-C   [draft]                       │
└──────────────────────────────────────────────┘
```

- node row: status dot (● connected / ○ disconnected) + name + `(session count)`.
- session child: `• name [status]` (`running` / `stopped` / `draft`).
- empty tree shows `No nodes yet · n to add` (no trailing `+ add` row).

### Keys
| key   | action                                            |
|-------|---------------------------------------------------|
| j/k   | move                                              |
| enter | enter session → S2 (session row only)             |
| n     | new node (→ S5)                                   |
| s     | new session on the current node (name → preset pick) |
| e     | edit the current node → S5 (name + cookie)        |
| c     | connect/disconnect current node                   |
| d     | delete current node (+ its sessions) / session — inline confirm |
| p     | preset manager (→ S4)                             |
| ,     | settings (→ S6)                                   |
| ?     | help (→ S7)                                        |
| q     | quit (inline confirm)                             |

Note: structural delete here is bare `d` + a confirm prompt (the confirm is the
safeguard), not `Ctrl+D`. See [Global Conventions](#global-conventions).

### New session flow (`s`)
Node context = the current node row, or the parent node of the current session row.
First a name prompt, then an "init from" preset picker:
```
┌─ New session ────────────────────────────────────┐
│ name: |sess-D_                                    │
└──────────────────────────────────────────────────┘
┌─ Session "sess-D" — init from ───────────────────┐
│ ▸ (blank)                                         │
│   lists-trace                                     │
│   genserver-call                                  │
│ j/k move · Enter create · Esc cancel              │
└──────────────────────────────────────────────────┘
```
- name is free text (no auto-generation).
- pick a preset → deep-clone its traces + limits; pick `(blank)` → empty draft.
- when no presets exist, only `(blank)` is shown.
- after create the session is added to the tree; open it (`enter`) then `e` to edit traces.

---

## Screen 2 — Session Events
Entered via `enter` on a session. Default: full-width events list (live stream).
`enter` on an event reveals a fixed-width right **Detail** pane.

Default (no detail):
```
┌─ sess-A @ app@host1 [sort:ts↓ filter:- group:-] ──────────────┐
│ ts           k name        pid       mfa            info      │
│ 10:02:01.234 ↓ gen_server  <0.42.0>  lists:seq/2    [1, 5]    │
│ 10:02:01.235 ↑ gen_server  <0.42.0>  lists:seq/2    [1,2,3..] │
│ 10:02:03.102 → -           <0.55.0>  -              <0.61.0>: {tick,42}
│ [running · 1.2k evt · buf 500/500]                            │
└────────────────────────────────────────────────────────────────┘
```

Detail open (after `enter` on a row):
```
┌─ sess-A ... ──────────────────────────┬─ Detail ◂ (z zoom · E editor)─┐
│ ts        k name      pid      mfa     │ kind: ↓ call                  │
│ 02.234 ↓ gen_server <0.42.0> seq/2 ◂   │ ts:   10:02:01.234            │
│ 02.235 ↑ gen_server <0.42.0> seq/2     │ pid:  <0.42.0>                │
│ ...                                    │ name: gen_server              │
│ [running·1.2k·buf500]                  │ init: myapp:init/1            │
│                                        │ mfa:  lists:seq/2             │
│                                        │ args: [1, 5]                  │
│                                        │ stack: ...(scroll)            │
└────────────────────────────────────────┴───────────────────────────────┘
```

### Left pane (events list)
- header shows session + current sort / filter / group state.
- bottom status bar: run state · cumulative event count · buffer usage.
- columns controlled by Settings (S6), NOT responsive auto-hide.

### Event row
Columns: `ts (always) · k (always) · name · pid · mfa · info`.
Last four toggleable in Settings (global). `ts` and `k` cannot be hidden.

| col  | default | width    | content                                |
|------|---------|----------|----------------------------------------|
| ts   | shown   | 12       | `10:02:01.234` (millisecond precision) |
| k    | shown   | 1        | kind symbol + color                    |
| name | shown   | flex     | registered name only, `-` if none      |
| pid  | shown   | 9        | `<0.42.0>`                             |
| mfa  | shown   | flex     | `M:F/arity`; `-` for send/recv         |
| info | shown   | adaptive | args / ret / message; truncated to width |

Kind symbols (set E) + color (dual-encoded):

| sym | kind | color  | meaning  |
|-----|------|--------|----------|
| `↓` | call | cyan   | call in  |
| `↑` | retn | green  | return   |
| `→` | send | yellow | send msg |
| `←` | recv | purple | recv msg |

info content by kind:
- call `↓`: args list, e.g. `[1, 5]`
- retn `↑`: return value, e.g. `[1,2,3,4,5]`
- send `→`: `<target_pid>: <message>`
- recv `←`: `<message>`

### name vs mfa (distinct fields)
- **name** = process identity (who). From trace tuple `{pid, X}`: registered name (atom)
  or, if unregistered, the initial-call mfa. Row shows **registered name only**; unregistered → `-`.
  Full identity (pid + name + initial call) lives in the Detail pane.
- **mfa** = the function the event concerns (what). Only meaningful for call/retn;
  send/recv have no mfa (`-`). redbug is fundamentally a function tracer, so mfa stays in the row.

### Right pane (Detail) — shown on `enter`
- not always present; `enter` on a focused row reveals it (fixed width).
- contents: kind / ts / pid / name (registered) / init (initial call mfa) / mfa / payload / stack.
  pid + name + init are fully shown here (what the list row omits).
- payload by kind: call=args, retn=return value, send=target+message, recv=message.
- stack: only call events (when RTP includes `stack`); else section hidden.
- detail interaction:
  - `j/k` (or ↑/↓): scroll detail content.
  - `ctrl+j/k`: move to prev/next event (detail follows), in current filter/sort visible order.
  - `z`: zoom → full-screen overlay of detail.
  - `⇧E`: export event as **elixir term** to a temp file, open in `$EDITOR` (read-only inspect).
    Available in detail focus, in row focus (list), and in zoom.
  - `esc`: close detail, back to full-width list.
- `z` (zoom overlay) and `⇧E` ($EDITOR) coexist: zoom = quick in-TUI fullscreen, ⇧E = external deep inspect.

### Sort / Filter / Group (events list)
- **sort**: by ts / kind / pid / mfa, asc/desc. `o` opens a floating dropdown
  (opentui `position:absolute` + `zIndex` overlay over the list), not a cycle.
- **filter**: match against mfa / pid / info(args+ret) / all. `/` opens scope picker + input.
  Matched substring highlighted (`<span bg=yellow>`) in the targeted column(s):
  pid scope → pid col, mfa scope → mfa col, info scope → info col, all → all text cols.
- **group**: collapse by pid / mfa / kind; group header shows count, e.g. `▸ <0.42.0> (3)`.
- all client-side on the received buffer; do not affect redbug.

### Keys
| key      | action                                          |
|----------|-------------------------------------------------|
| j/k      | move selection (list) / scroll (when detail focus) |
| enter    | reveal + focus Detail pane for selected event   |
| ctrl+j/k | prev/next event (detail focus, detail follows)  |
| o        | sort dropdown                                   |
| /        | filter (scope + input)                          |
| g        | cycle group (none → pid → mfa → kind)           |
| l        | edit session limits (overlay)                   |
| z        | zoom detail (fullscreen overlay)                |
| ⇧E       | open event in `$EDITOR` (elixir term)           |
| tab      | focus Detail (only when detail open)            |
| e        | open trace editor overlay (→ S3)                |
| ⇧S       | start session                                   |
| ⇧X       | stop session                                    |
| Ctrl+S   | apply & restart (push staged edits to live)     |
| Ctrl+L   | clear current session buffer                     |
| esc      | close detail; or return to S1 (tree)            |

Header shows `[status]`, current `sort/filter/group`, and `⚠ unapplied (Ctrl+S)`
when there are staged edits. Footer mirrors this key list.

### Event lifecycle
- events live in the **controller session's memory** (each session's musubi store holds a
  stream buffer capped at `keep`); not persisted to file (only config — nodes/sessions/presets/
  settings — is persisted).
- **stop does NOT clear events** (retained for offline review; stop ≠ clear).
- **restart keeps events** and inserts a separator marker (`── restarted HH:MM:SS ──`); no history loss.
- **manual clear**: `Ctrl+L` clears the current session's buffer (data loss → Ctrl convention).
- buffer overflow: oldest events evicted per `keep` (via stream `limit -500`).
- controller restart → events lost (in-memory). TUI reconnect → server-authoritative,
  store still alive on controller → reconnect restores current buffer snapshot.

### Notes
- redbug ts is `{h,m,s,us}`; millisecond from `us div 1000` (current `fmt_ts` drops `us`, add on impl).
- group is by pid underlying (unique), display uses name when present.

---

## Global Conventions

### Destructive / heavy ops
Heavy/irreversible ops mostly use a `Ctrl+` key; lightweight reversible ops use bare
keys (move, select, toggle, start/stop, filter/sort, connect). The keymap is **not fully
uniform** — tree-level structural deletes use bare `d` (the confirm prompt is the
safeguard), while editor/preset deletes use `Ctrl+D`.

| op                                  | key      | confirm?        |
|-------------------------------------|----------|-----------------|
| delete node / session (Tree)        | `d`      | y/n prompt      |
| delete preset (Preset Manager list) | `Ctrl+D` | y/n prompt      |
| delete preset trace (Preset detail) | `Ctrl+D` | y/n prompt      |
| delete RTP (Trace editor overlay)   | `Ctrl+D` | none (immediate)|
| save as preset (Trace editor)       | `Ctrl+W` | name prompt     |
| apply & restart (running session)   | `Ctrl+S` | none            |
| clear session buffer                | `Ctrl+L` | none            |
| quit (Tree)                         | `q`      | y/n prompt      |

### Confirmation (by cost)
- **Structural delete** (node / session / preset) and **preset trace delete**: y/n prompt.
- **Trace-editor RTP delete**: `Ctrl+D` only, no prompt (the Ctrl modifier is the safeguard).

### esc / quit
- `esc` closes the topmost overlay (or detail pane) first; from S1 (tree) `esc` does nothing.
- `q` quits the app, only from S1 (tree). Inside any overlay, `esc` first.

---

## Screen 3 — Trace Editor
Overlay rendered **inside** Session Events (S2), opened with `e`. Edits the session's
RTP list and offers save-as-preset. Start/stop and limits are **not** in this overlay —
they live on the S2 screen (`⇧S`/`⇧X` start/stop, `l` limits, `Ctrl+S` apply & restart).

**RTP** = Redbug Trace Pattern, the string passed to `:redbug.start/2`:
`Module:Function/Arity [when Guard] -> Actions` (e.g. `lists:seq -> return`,
`M:f/2 -> return;stack`). A session's traces = a list of RTPs; enabled ones are
passed together as the `Trc` list on start.

### Design decisions
- **RTP editing = plain text** (raw redbug RTP string), not a structured wizard.
  redbug's expressiveness (guards, `->return;stack`, wildcards) is hard to wizard;
  users are Elixir/Erlang devs; redbug validates on start, errors echoed to Status.
  Lightweight assists (syntax hint line, copy-from-preset) can come later.
- **limits edited inline** (time / msgs / keep — 3 scalars, no sub-overlay).
- **rename inline**: `enter` on the header session-name → inline rename (no new key).
- **no explicit save**: all edits (RTP / limits / rename / toggle) auto-persist to config on commit.
  inline edit model: `enter` to edit a field, `enter` OR `esc` to commit. No Ctrl+S save.
  `Ctrl+S` is NOT a save — it only means "apply & restart" for a running session (see below).
- **No "clear/reset" op** (useless). **No source-preset pointer**: a session does NOT
  retain a reference to the preset it was created from. Preset → session is a one-time clone
  (traces + limits). The only preset op on a session is Save-as-preset (`Ctrl+W`).
  To "revert", create a new session by cloning the preset again.

### redbug cannot hot-add patterns (verified)
`redbug.start/2` is a singleton session; patterns compiled at start, no add API
(already-running → `redbug_already_started`). Changing patterns = stop + start.
But restart is cheap: event buffer is client-side (musubi stream), so restart only
causes a ~tens-of-ms capture gap + resets redbug's own msgs/time counters; buffer persists.

### Running-session edit model (auto-save config, explicit apply-to-live)
Editing while running auto-saves to config but does NOT auto-restart redbug. The saved
config is **not yet applied to the live trace** (live still runs old config). User applies
on demand, or is prompted on exit.
- changed-vs-applied rows prefixed `*`; Status shows `⚠ unapplied to live` (yellow).
- `Ctrl+S` = apply & restart (stop old + start new config). Counters reset; buffer continuous.
- `apply` = stop old then start new; if start fails, session falls to stopped, error echoed, manual retry.
- `Ctrl+S` only meaningful while running (stopped sessions just use latest config on next start).
- **only live-affecting edits trigger the unapplied marker / restart prompt**:
  - affect live (mark `*`/`⚠`, need restart): RTP add/edit/remove/toggle, redbug-side limits (time/msgs).
  - do NOT affect live (take effect immediately, no marker/restart): rename, `keep` (TUI buffer cap),
    column visibility, theme, etc.

### Overlay (as built)
```
┌─ Traces — sess-A ────────────────────────────────────────────┐
│  [x] lists:seq/2 -> return                                    │
│  [x] M:f/2 -> return;stack                                    │
│  [ ] gen_server:call -> return            <- disabled, dim    │
│ j/k move · space toggle · a add · e edit · Ctrl+D del · Ctrl+W save preset · esc close
└────────────────────────────────────────────────────────────────┘
```
- `[x]`/`[ ]` = enabled / disabled (dim). Empty list shows `No patterns yet · a to add`.
- `space` toggles the selected RTP; `a` opens an add field; `e` edits the selected RTP;
  both are single-line TextField inputs (`enter` submits, `esc` cancels, empty discarded).
- `Ctrl+D` deletes the selected RTP immediately (no confirm; the modifier is the safeguard).
- `Ctrl+W` opens save-as-preset: a name field that always **creates a new** preset
  (no overwrite picker).
- `esc` closes the overlay back to the S2 list.

All edits auto-persist to config on commit. Editing while a session is **running** does
not restart redbug — the change is staged; the S2 header shows `⚠ unapplied (Ctrl+S)`,
and `Ctrl+S` (on the S2 screen) applies + restarts.

### Design decisions
- **RTP editing = plain text** (raw redbug RTP string), not a structured wizard.
  redbug's expressiveness (guards, `->return;stack`, wildcards) is hard to wizard;
  users are Elixir/Erlang devs; redbug validates on start, errors echoed to Status.
- **no explicit save**: all edits (add / edit / toggle / delete) auto-persist on commit.
  `Ctrl+S` is NOT a save — it only means "apply & restart" for a running session.
- **No source-preset pointer**: a session does NOT retain a reference to the preset it
  was created from. Preset → session is a one-time clone (traces + limits). The only
  preset op on a session is save-as-preset (`Ctrl+W`). To "revert", clone the preset again.

### redbug cannot hot-add patterns (verified)
`redbug.start/2` is a singleton session; patterns compiled at start, no add API
(already-running → `redbug_already_started`). Changing patterns = stop + start.
But restart is cheap: event buffer is client-side (musubi stream), so restart only
causes a ~tens-of-ms capture gap + resets redbug's own msgs/time counters; buffer persists.

### Constraints
- one running session per node; starting another warns/stops the other.
- RTP not validated client-side; redbug validates, failures shown in Status.
- start requires >=1 enabled RTP.
- limits: `keep` is TUI-side buffer cap (stream limit); `time`/`msgs` are redbug-side.
- **start auto-connects**: if the node is disconnected, `⇧S` first connects then starts
  redbug; connect failure → start fails. `⇧X` stop does NOT disconnect (connection reused);
  disconnect is manual via `c` on the Tree.

### Deferred (designed, not yet implemented)
Per-row staged `*` markers, inline limits-in-editor, inline session rename, apply-failed
state, save-as-preset overwrite + confirm, and the exit-while-unapplied prompt are in the
original design but not implemented. The dirty signal is the single S2 header marker.

---

## Screen 4 — Preset Manager
Overlay, entered via `p` from any screen. A preset is a reusable, node-agnostic
trace template storing **traces (RTP list) + limits** (time/msgs/keep).

### Preset ↔ session relationship (clone-only, no pointer)
- preset → session: on S1 `s` (new session), pick a preset; its traces + limits are
  **deep-cloned** into the new session. No back-reference is kept.
- session edits never affect any preset (fully decoupled).
- session → preset: S3 `Ctrl+W` saves the session's current traces as a **new** preset.
- "using a preset" = clone it and continue editing/using; to reset, clone again into a new session.
- preset has no "running" concept (it doesn't trace) → no staged/restart; edits auto-save on commit.

### States

**1. list**
```
┌─ Presets ───────────────────────────────────────┐
│ ▸ lists-trace        2 traces                    │
│   genserver-call     1 trace                     │
│   ets-ops            3 traces                     │
│   message-flow       send + recv                 │
│ + new preset                                     │
│ j/k move · enter edit · n new · r rename · Ctrl+D delete · esc back │
└──────────────────────────────────────────────────┘
```
- `enter`/`tab` opens the detail pane (focus right); `r` renames inline; `Ctrl+D`
  deletes the preset (y/n confirm). The list is a two-pane layout (presets left, traces right).

**2. view/edit a preset (enter)**
```
┌─ Preset: lists-trace ────────────────────────────┐
│ name: lists-trace                                 │
│ Traces:                                           │
│  [x] lists:seq -> return                          │
│  [x] lists:map -> return;stack                    │
│  + add RTP                                        │
│ Limits:  time 24h   msgs 1e6   keep 500           │
│ j/k move · space toggle · a add · e edit · l limits · Ctrl+D del · tab/esc back │
└──────────────────────────────────────────────────┘
```
- detail-pane (focus right): `space` toggle trace, `a` add RTP, `e` edit RTP,
  `l` edit limits (modal), `Ctrl+D` delete trace (**y/n confirm** — unlike the session
  trace editor, which deletes immediately), `tab`/`esc` back to list.
- **no start/stop** (preset is a template); edits auto-persist on commit (no staged/restart).
- **rename**: `r` on the list (focus left) → inline rename modal (`enter`/`esc` commit).

**3. new preset (n)**
```
┌─ New Preset ─────────────────────────────────────┐
│ name: |_                                          │
│ (after create, enters edit to add RTPs)           │
│ enter confirm name · esc cancel                   │
└──────────────────────────────────────────────────┘
```

**4. delete preset (Ctrl+D, structural → second confirm)**
```
┌─ Delete preset? ─────────────────────────────────┐
│ "ets-ops" (3 traces)                              │
│ Sessions cloned from it are unaffected (copied).  │
│  [y] confirm   [n/esc] cancel                     │
└──────────────────────────────────────────────────┘
```

---

## Screen 5 — Node Editor
Overlay, entered from S1 `n` (new) / `e` (edit node). Add/edit a connection target.

```
┌─ New node ────────────────────────────────────────┐
│ › name    name@host (longname), e.g. myapp@…      │
│   |myapp@127.0.0.1_                               │
│   cookie  Erlang distribution cookie; must match  │
│   |______                                         │
│ Tab switch field · Enter save · Esc cancel        │
└──────────────────────────────────────────────────┘
```
Both `name` and `cookie` are required (Enter is a no-op until both are non-empty).

Fields:
- **name**: Erlang node name `app@host` (longname). A format hint is shown beneath the
  field; no hard client-side validation — connection errors are reported on connect.
- **cookie**: distributed cookie. Shown in plain text (not masked).

### Decisions
- **cookie stored plaintext** in `~/.redbug/config.json`. cookie == RCE, so the config
  file should be `0600` (owner-only) even though stored in clear.
- **name validation**: none up front; errors surface on connect
  (`✗ nodedown` / bad cookie / etc.). Input shows a `name@host` hint only.
- **delete node cascades to its sessions** (Tree `d` → y/n confirm).

### Connect feedback (on `c` / save)
```
│ Status: ⟳ connecting…  /  ✓ connected  /  ✗ nodedown / bad cookie │
```

### Delete node (Tree `d`, structural → y/n confirm)
```
┌─ Confirm ─────────────────────────────────────────┐
│ Delete node "app@host1" and all its sessions?     │
│  [y] yes   [n/esc] no                             │
└──────────────────────────────────────────────────┘
```

---

## Screen 6 — Settings
Full-screen, entered with `,` from the **Tree only**. Global preferences, persisted to config.

```
┌─ Settings ───────────────────────────────────────┐
│ theme            dark                             │
│ default sort     ts_desc                          │
│ col · name       [x]                              │
│ col · pid        [x]                              │
│ col · mfa        [x]                              │
│ col · info       [x]                              │
│ default limits   keep 500 · time 30s · msgs 1000  │
│ $EDITOR          nvim (read-only · set via env)   │
│ ts and k columns are always shown.                │
│ j/k move · space/enter/right/l toggle or cycle · esc back │
└──────────────────────────────────────────────────┘
```
Rows in order: theme, default sort, the four toggleable columns, default limits, and a
read-only `$EDITOR` line. The selected row is acted on by `space` / `enter` / `→` / `l`:
theme and sort **cycle** through their option lists, columns **toggle**, default limits
opens a text field. Edits auto-save.

### Decisions
- entry: `,` from the **Tree** (not a global-from-any-screen key).
- columns: name/pid/mfa/info toggleable; ts/k locked (cannot hide).
- **global default limits + sort**: stored here, applied to new sessions (editable per session).
- `$EDITOR`: read-only display of the env var (used by S2 `⇧E`).
- **theme** selectable (see Themes below).

### Themes

A theme = a map of semantic color tokens (hex, applied via opentui):
`bg · fg · border · accent · dim · selected_bg · selected_fg`
+ kind colors `call · retn · send · recv`
+ status colors `ok · warn · err`.
Each theme provides one such map; the kind dual-encoding (symbol + color) reads from these tokens.

First batch:
- **base**: light, dark
- **Tokyo Night (all)**: Night, Storm, Moon, Day
- **high-frequency**: Catppuccin Mocha, Dracula, Nord, Gruvbox Dark

More (Catppuccin Latte/Frappé/Macchiato, Rosé Pine, Solarized, Ayu, One Dark, Everforest,
Kanagawa, Monokai, …) can be added later by dropping in more token maps.

---

## Screen 7 — Help
Overlay opened with `?` from the **Tree**. Keybinding reference + kind legend.
Reference only; **press any key to close** (it dismisses on the next keypress).

```
┌─ redbug · help ──────────────────────────────────────────┐
│ kinds: ↓ call (cyan) · ↑ retn (green) · → send (yellow) · ← recv (purple) │
│ Tree                                                      │
│   j/k move · enter open session · n node · s session     │
│   e edit node · c connect/disconnect · d delete          │
│   p presets · , settings · q quit                        │
│ Session                                                   │
│   enter detail · o sort · / filter · g group · l limits · z zoom │
│   ⇧E $EDITOR · e traces · ⇧S/⇧X start/stop               │
│   Ctrl+S apply · Ctrl+L clear · Ctrl+W save preset        │
│ Presets / Settings                                        │
│   j/k move · enter/tab edit · space toggle · esc back     │
│ press any key to close                                    │
└────────────────────────────────────────────────────────────┘
```
Help is a single static overlay (no `j/k` scroll); it mirrors the keymaps above.
