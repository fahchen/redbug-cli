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
8. **Console** — a **tab inside Session Events** (`Events │ Console`), per-session
   **code runner** (not a REPL): a server-persisted execution history; each entry is a whole
   `$EDITOR`-composed block (blank or seeded from S9) run on the node, force-stoppable.
9. **Snippet Manager** — full screen, entered from Tree. CRUD of a **global**, reusable
   code-snippet library (node-agnostic, like Presets). Bodies edited in `$EDITOR`.

Entry keys (`p` presets, `x` snippets, `,` settings, `?` help) are wired on the **Tree only**;
the other screens return to Tree via `esc` first.

Navigation:
```
S1 Tree ──enter session──> S2 Session Events ──esc──> S1
   │ n/e (node) overlays S5    │ enter event -> right detail pane
   │ p -> S4, , -> S6, ? -> S7 │ e -> S3 trace editor overlay · l -> limits
   │ s -> new-session flow     │ z -> zoom overlay, ⇧E -> $EDITOR
                               │ [ / ] -> switch Events ⇄ Console tab (S8)
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
| x     | snippet manager (→ S9)                            |
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
Entered via `enter` on a session. The screen has a **tab strip** —
`‹ Events │ Console ›` — switched with `[` / `]`. **Events** (default) is the live
trace stream below; **Console** is the per-session code runner (see [Screen 8](#screen-8--console-events-tab)).
`enter` on an event reveals a fixed-width right **Detail** pane.

Events tab, default (no detail):
```
┌ ‹ Events │ Console › ─────────────────────────────────────────┐
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
| [ / ]    | switch tab (Events ↔ Console)                    |
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
Two safeguard styles: a **y/n confirm prompt**, or a **`Ctrl+` modifier**. Prefer a bare
key + confirm; reserve `Ctrl+` for ops where a prompt would be too much friction (the
modifier is then the only safeguard). The keymap is **not fully uniform** for historical
reasons — tree/snippet structural deletes and the Console's `s`/`c` use bare keys + confirm,
while the older trace-editor / preset deletes still use `Ctrl+D`.

| op                                  | key      | confirm?        |
|-------------------------------------|----------|-----------------|
| delete node / session (Tree)        | `d`      | y/n prompt      |
| delete preset (Preset Manager list) | `Ctrl+D` | y/n prompt      |
| delete preset trace (Preset detail) | `Ctrl+D` | y/n prompt      |
| delete RTP (Trace editor overlay)   | `Ctrl+D` | none (immediate)|
| save as preset (Trace editor)       | `Ctrl+W` | name prompt     |
| apply & restart (running session)   | `Ctrl+S` | none            |
| clear session buffer                | `Ctrl+L` | none            |
| delete snippet (Snippet Manager)    | `d`      | y/n prompt      |
| stop / kill running execution (Console) | `s`  | y/n prompt      |
| clear console history (Console)     | `c`      | y/n prompt      |
| quit (Tree)                         | `q`      | y/n prompt      |

### Confirmation (by cost)
- **Structural delete** (node / session / preset / snippet) and **preset trace delete**: y/n prompt.
- **Trace-editor RTP delete**: `Ctrl+D` only, no prompt (the Ctrl modifier is the safeguard).
- **Kill a running remote execution** (Console `s`): y/n prompt — irreversible
  (side effects already ran, result lost). The auto-`@timeout` kill is unprompted (it is
  the safety bound, not a user action).
- **Clear console history** (Console `c`): y/n prompt — it is **server-persisted**
  data, unlike the volatile trace event buffer (whose `Ctrl+L` is unprompted).

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
│ j/k move · space toggle · n add · e edit · Ctrl+D del · Ctrl+W save preset · esc close
└────────────────────────────────────────────────────────────────┘
```
- `[x]`/`[ ]` = enabled / disabled (dim). Empty list shows `No patterns yet · n to add`.
- `space` toggles the selected RTP; `n` opens an add field; `e` edits the selected RTP;
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
│ j/k move · space toggle · n add · e edit · l limits · Ctrl+D del · tab/esc back │
└──────────────────────────────────────────────────┘
```
- detail-pane (focus right): `space` toggle trace, `n` add RTP, `e` edit RTP,
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
- **cookie stored plaintext** in `~/.config/redbug/config.json` (honors `$XDG_CONFIG_HOME`).
  cookie == RCE, so the config file should be `0600` (owner-only) even though stored in clear.
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
│   p presets · x snippets · , settings · q quit           │
│ Session                                                   │
│   enter detail · o sort · / filter · g group · l limits · z zoom │
│   ⇧E $EDITOR · e traces · ⇧S/⇧X start/stop               │
│   Ctrl+S apply · Ctrl+L clear · Ctrl+W save preset        │
│   [ / ] switch Events ⇄ Console tab                        │
│ Console (tab)                                             │
│   n new · e edit · v view · Enter rerun · s stop · c clear │
│ Presets / Snippets / Settings                             │
│   j/k move · enter/tab edit · space toggle · esc back     │
│ press any key to close                                    │
└────────────────────────────────────────────────────────────┘
```
Help is a single static overlay (no `j/k` scroll); it mirrors the keymaps above.

---

## Screen 8 — Console (events tab)

The **Console** tab of Session Events (S2): a per-session **code runner** against the
session's target node. Switched into with `]` (back to Events with `[`).

**Not a line-by-line REPL.** For ad-hoc interactive eval the user already has a remote
iex (`iex --remsh app@host`); duplicating that adds nothing. The Console's value is a
**server-persisted execution history** bound to this session (survives ws reconnect),
where each entry is a *whole code block run as one piece* — composed in `$EDITOR` from
scratch or seeded from the global snippet library (S9), and **force-stoppable** mid-run.
Running on the live node is real remote code execution, gated only by the cookie the user
already holds (cookie == RCE; redbug already grants equivalent access).

```
┌ ‹ Events │ Console › ──────────────────────────────────────────┐
│ ● app@host1 · ⚠ live node — runs with target privileges        │
├─ history ──────────────────────┬─ detail ──────────────────────┤
│ ▸ 10:02:03 ⟳ sup-tree          │ :supervisor.which_children(..) │
│   10:02:01 ✓ proc-count        │                                │
│   10:01:40 ✗ ets-info          ├─ result ──────────────────────┤
│   10:01:05 ✓ (adhoc)           │ ⟳ running…  (s stop)           │
│                                │                                │
│ n new · e edit · v view        │                                │
└─────────────────────────────────┴───────────────────────────────┘
 n new · e edit · v view · Enter rerun · s stop · c clear · [ Events
```

### Model: execution = one history entry
The run unit is an **execution**: `%{id, name, code, status, result, output, ts,
duration_ms}`, `status ∈ "running" | "ok" | "error" | "stopped" | "timeout"`. History is an
append-only, server-authoritative, capped log; selecting a row shows its code + result in
the detail pane, and `v` opens the full **code + output** in `$EDITOR` (read-only) for
entries too long for the pane. There is **no separate working set** — the only persistent
list is the history; new executions are composed fresh each time.

**Starting an execution** (all `$EDITOR`-composed, run whole on save+exit):
- `n` **new** → a *start-from* picker: `blank` or a snippet from the global library (S9).
  Pick → `$EDITOR` opens (empty, or seeded with the snippet body) → save+exit → run.
- `e` **edit→rerun** a selected history entry → `$EDITOR` seeded with its code →
  save+exit → run as a **new** execution (a fork; the original entry is untouched).
- `v` **view** a selected entry's code + captured output in `$EDITOR`, read-only.
- `Enter` **rerun** a selected history entry verbatim as a new execution.
- a snippet's name (or `(adhoc)` for blank) rides along as the execution `name`.

**Stopping an execution**: `s` on a `running` entry **(y/n confirm)** force-kills the
remote worker (see mechanism) → status `stopped`. The confirm guards against an accidental
kill: the killed worker's side effects already ran and can't be rolled back, and the result
is lost. `@timeout` (~15s) auto-kills (no confirm — it is the bound) → status `timeout`.

### Keys
Bare keys throughout — destructive ones (`s`, `c`) carry a y/n confirm instead of a `Ctrl`
modifier (the prompt is the safeguard, matching the Tree's bare-`d` delete).

| key   | action                                                  |
|-------|---------------------------------------------------------|
| j/k   | move selection in the history log                       |
| n     | new execution → start-from picker (blank / snippet) → `$EDITOR` |
| e     | edit the selected entry's code in `$EDITOR` → run as new |
| v     | view the selected entry's code + output in `$EDITOR` (read-only) |
| Enter | rerun the selected entry verbatim (new execution)       |
| s     | stop the selected `running` execution (force-kill — y/n confirm) |
| c     | clear history (y/n confirm — server-persisted data)     |
| [     | back to Events tab                                      |
| esc   | return to S1 (tree)                                     |

`run` / `Enter rerun` are **not** confirmed: a new run is already deliberate (compose +
save in `$EDITOR`, under the persistent ⚠ live-node banner), and a rerun replays code the
user already vetted on the first run — no more dangerous than that first run, which was
itself unconfirmed. Friction sits on `$EDITOR` compose, not on a per-run prompt.

### Snippets are seeds, not links (clone-only)
The reusable library is **global** and lives in the [Snippet Manager](#screen-9--snippet-manager)
(S9). The console only **consumes** it: the `n` picker copies a snippet body into the
`$EDITOR` buffer (a copy — no back-reference, mirroring preset → session). Edits here never
touch the library; to persist a refinement, edit it in S9.

### Run mechanism (spawn + monitor → killable)
- `Server.Remote.Console` — GenServer, `restart: :transient`, registered
  `{:via, Registry, {Server.Remote.Registry, session_id}}` (twin of `Trace.Runner`). Owns
  the history (capped, server-authoritative) and a map of in-flight runs
  `%{exec_id => %{pid, mon_ref, timer}}`. Lazily started under a `DynamicSupervisor`.
- on `run` the code is first normalized through `Server.Code.Format` (see
  [Formatting](#code-formatting)); the formatted source is what gets stored on the entry and
  sent to the worker (unparseable source runs raw — format never blocks a run).
- `run`: `Config.connect_node` (auto-connect like trace start), then **spawn a remote
  worker** (not a blocking `:rpc.call`, so it stays killable) and `Process.monitor` it:
  ```elixir
  pid = Node.spawn(target, __MODULE__, :worker, [self(), exec_id, code])
  ref = Process.monitor(pid)   # DOWN fires on crash, kill, or net split
  # worker (runs on target): group_leader → StringIO;
  #   Code.eval_string(user_src, [user_src: code], file: "remote") in try/rescue/catch;
  #   send(console, {:done, exec_id, {:ok|:error, inspect|format}, captured_io})
  ```
  the snippet source is a **bound variable** (never string-interpolated → no injection).
- `stopExecution{id}`: `Process.exit(pid, :kill)` — the `exit/2` signal propagates over
  distribution and kills the remote worker; the `DOWN` marks the entry `stopped`.
- `@timeout` (~15s) arms a per-run timer; on fire, same kill path → `timeout`.
- **Erlang fallback**: a pure-Erlang target (no `Code`/`StringIO`) makes the worker fail
  `:undef`; the worker falls back to `:erl_scan` → `:erl_parse` → `:erl_eval` (stdlib).
- each state change (start → running, done, stopped, timeout) updates the entry and
  broadcasts `{:console_run, entry}` on `Server.Remote.topic(session_id)`.

### Stores
`Server.Stores.ConsoleRoot` (root, mounted `node_id`/`session_id`) — mirrors `SessionRoot`:
subscribes `config` + `Remote.topic`, seeds `stream(:history)` from `Remote.snapshot/1`.
Fields: `name, connected`, library `snippets` (read-only, for the start-from picker),
`stream(:history)`. Commands: `run{code, name}`, `stopExecution{id}`, `clearHistory`,
`connect`. Library CRUD stays in S9 / `SnippetsRoot`. In the TUI the Console tab mounts this
root independently of `SessionRoot` (each tab owns its root).

### Constraints / safety
- requires a reachable node; run auto-connects, connect failure → error entry.
- `s` (confirm) and `@timeout` both force-kill the remote worker, so a runaway run is bounded
  (the spawn+monitor design makes the worker killable — unlike a blocking `:rpc.call`).
- result + captured output are truncated (`inspect limit`, byte cap) to keep history light.

---

## Screen 9 — Snippet Manager

Full screen, entered from the Tree (parallel to Preset Manager). CRUD for a **global**,
node-agnostic library of named code snippets — reusable across any node/session, exactly
like Presets are for traces. Persisted in `config.json` (top-level `:snippets`, 0600).

```
┌─ Snippets ──────────────────────────────────────────────────┐
│ ▸ proc-count      Process.list() |> length()                │
│   ets-tables      :ets.all() |> Enum.map(&:ets.info(&1, …))  │
│   sup-tree        :supervisor.which_children(MyApp.Sup)      │
│ + new snippet                                                │
│ j/k · enter edit · n new · r rename · f format · d del · esc │
└──────────────────────────────────────────────────────────────┘
```

### Model
- a **snippet** = `%{id, name, code}`. The body is free-text Elixir (or Erlang) source.
- node-agnostic: a snippet references no node/session; the Console clones a copy to run.
- **clone-only** relationship with the console: editing/running in the console never
  touches the library; library edits never touch any past console execution.
- **auto-formatted on save** (`Server.Code.Format`, see [Formatting](#code-formatting)):
  the body is normalized server-side; unparseable source is stored raw (best-effort).

### Keys
Bare keys throughout (delete carries a y/n confirm, matching the Tree's bare-`d` delete).

| key   | action                                            |
|-------|---------------------------------------------------|
| j/k   | move selection                                    |
| enter | edit selected snippet body in `$EDITOR`           |
| n     | new snippet (name → `$EDITOR` body)               |
| r     | rename selected snippet                           |
| f     | reformat selected snippet body                     |
| d     | delete selected snippet (y/n confirm — structural)|
| esc   | back to Tree                                       |

### Stores
`Server.Stores.SnippetsRoot` (root) + `Server.Stores.SnippetStore` child — mirrors
`PresetsRoot`/`PresetStore`. Root command `createSnippet{name}`; child commands
`updateSnippet{name,code}`, `deleteSnippet`. `Server.Config` gains `:snippets` with
`add_snippet/update_snippet/delete_snippet` and JSON (de)serialization alongside presets.

### Entry key
Reached from the Tree via `x` (see [Screen 1](#screen-1--tree)); the Console's
`n` start-from picker reads the same global list to seed an execution from.

---

## Code formatting

Snippet bodies (S9) and console code (S8) are normalized by a shared `Server.Code.Format`
helper, run **on the controller node** (pure formatting, no eval → safe):
- **Elixir** (default): `Code.format_string!/2`.
- **Erlang** (source parses as Erlang forms): `:erl_scan` → `:erl_parse` →
  `:erl_prettypr` (stdlib).
- **best-effort**: source that parses as neither is left **raw** — formatting never raises
  out and never blocks a save (S9) or a run (S8).

Applied: on snippet save and on the S9 `f` reformat key; on every console `run` before the
code is stored on the execution entry and shipped to the worker.
