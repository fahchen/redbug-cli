# redbug-cli TUI — Screen Design

Domain model: **Node ▸ Session ▸ Traces → Events**, plus reusable **Presets**.
Built on musubi (server-authoritative, JSON Patch over Phoenix ws) + opentui/React on Bun.

## Screen Inventory

1. **Tree** — full-screen Node▸Session tree. Management + navigation. Root.
2. **Session Events** — left events list / right detail pane (detail shown on `enter`).
3. **Session/Trace Editor** — overlay, edit RTP list + limits, start/stop.
4. **Preset Manager** — overlay, preset CRUD.
5. **Node Editor** — overlay, node add/edit (name, cookie).
6. **Settings** — overlay, column visibility + global prefs.
7. **Help** — overlay (`?`), keybindings + kind legend.

Navigation:
```
S1 Tree ──enter session──> S2 Session Events ──esc──> S1
   │ n/e/p ...                 │ enter event -> right detail pane
   v overlays S3..S7           │ z -> zoom overlay, E -> $EDITOR
```

---

## Screen 1 — Tree [CONFIRMED]

Full-screen Node▸Session tree. Manage nodes/sessions; enter a session to view its events.

```
┌─ Nodes / Sessions ──────────────────────────┐
│ ● app@host1                                  │
│   ├▶ sess-A   ·run    1.2k evt               │
│   └○ sess-B   ·stop                          │
│ ○ app@host2                                  │
│   └○ sess-C   ·draft                         │
│ + add node                                   │
└──────────────────────────────────────────────┘
```

- node row: status dot (● connected / ○ disconnected) + name (`app@host`).
- session child: status (`·run` / `·stop` / `·draft`) + name + event count if any.
- trailing `+ add node`.

### Keys
| key   | action                                   |
|-------|------------------------------------------|
| j/k   | move                                     |
| enter | enter session → S2 (or expand node)      |
| n     | new node (→ S5)                          |
| s     | new session, pick preset to init (→ S3)  |
| e     | edit selected: node row → S5, session row → S3 |
| c     | connect/disconnect current node          |
| p     | preset manager (→ S4)                     |
| ?     | help (→ S7)                              |
| q     | quit                                     |

### New session flow (`s`)
Node context = selected node row, or the parent node of a selected session row.
```
┌─ New session on app@host1 ───────────────────────┐
│ name: |sess-D_              (auto-generated, editable) │
│ ── init from ──                                   │
│ ▸ (blank draft)                                   │
│   lists-trace        2 traces                     │
│   genserver-call     1 trace                      │
│ enter create · esc cancel                         │
└──────────────────────────────────────────────────┘
```
- name auto-generated (sess-A/B/C…), editable.
- pick a preset → deep-clone its traces + limits; pick `(blank draft)` → empty draft.
- when no presets exist, only `(blank draft)` is shown.
- after create → opens S3 (Trace Editor) with the cloned content.

---

## Screen 2 — Session Events [CONFIRMED]

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
  - `E`: export event as **elixir term** to a temp file, open in `$EDITOR` (read-only inspect).
    Available both in detail focus AND in row focus (list).
  - `esc`: close detail, back to full-width list.
- `z` (zoom overlay) and `E` ($EDITOR) coexist: zoom = quick in-TUI fullscreen, E = external deep inspect.

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
| enter    | reveal/focus Detail pane for selected event     |
| ctrl+j/k | prev/next event (detail follows), visible order |
| o        | sort dropdown                                   |
| /        | filter (scope + input)                          |
| g        | group                                           |
| z        | zoom detail (fullscreen overlay)                |
| E        | open event in `$EDITOR` (elixir term)           |
| tab      | switch focus list ↔ detail                      |
| S        | start session                                   |
| X        | stop session                                    |
| e        | edit traces (→ S3)                              |
| Ctrl+L   | clear current session buffer                     |
| esc      | close detail; or return to S1 (tree)            |

### Event lifecycle
- events live in the **controller session's memory** (each session's musubi store holds a
  stream buffer capped at `keep`); not persisted to file (only config — nodes/sessions/presets/
  settings — is persisted).
- **stop does NOT clear events** (retained for offline review; stop ≠ clear).
- **restart keeps events** and inserts a separator marker (`── restarted HH:MM:SS ──`); no history loss.
- **manual clear**: `Ctrl+L` clears the current session's buffer (data loss → Ctrl convention).
- buffer overflow: oldest events evicted per `keep` (PoC: stream `limit -500`).
- controller restart → events lost (in-memory). TUI reconnect → server-authoritative,
  store still alive on controller → reconnect restores current buffer snapshot.

### Notes
- redbug ts is `{h,m,s,us}`; millisecond from `us div 1000` (current `fmt_ts` drops `us`, add on impl).
- group is by pid underlying (unique), display uses name when present.

---

## Global Conventions

### Destructive / heavy ops require Ctrl modifier
Operations that lose data, are irreversible, or are costly use a `Ctrl+` key.
Lightweight reversible ops use bare keys (move, select, toggle, start/stop, filter/sort, connect).

| op                         | key      |
|----------------------------|----------|
| delete RTP                 | `Ctrl+D` |
| delete node/session/preset | `Ctrl+D` |
| save as preset             | `Ctrl+W` |
| apply & restart (running)  | `Ctrl+S` |
| clear session buffer       | `Ctrl+L` |

### Tiered confirmation (by cost)
- **Structural delete** (node / session / preset): Ctrl modifier **+** inline confirm prompt.
- **Item-level delete** (RTP): Ctrl modifier only, no second confirm.

### esc / quit
- `esc` closes the topmost overlay (or detail pane) first; from S1 (tree) `esc` does nothing.
- `q` quits the app, only from S1 (tree). Inside any overlay, `esc` first.

---

## Screen 3 — Session/Trace Editor [CONFIRMED]

Overlay. Entered from S1 (`s` new / `e` edit) or S2 (`e`). Edit RTP list + limits, control start/stop.

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

### States

**1. stopped (default)**
```
┌─ Session: sess-A  @ app@host1 ──────────────────────────────┐
│ Traces:                                                      │
│  [x] lists:seq -> return                                     │
│  [x] M:f/2 -> return;stack                                   │
│  [ ] gen_server:call -> return            <- disabled, dim   │
│  + add RTP                                                   │
│ Limits:  time 24h   msgs 1e6   keep 500                      │
│ Status:  ○ stopped                                           │
│ [S start]                          [Ctrl+W save as preset]   │
└──────────────────────────────────────────────────────────────┘
 j/k move · space toggle · enter edit · a add · Ctrl+D delete · esc back
```

**2a. running, clean**
```
│ Status:  ● running · 1.2k events · 02:13                     │
│ [X stop]                           [Ctrl+W save as preset]   │
```

**2b. running, dirty (staged edits)**
```
│ Traces:  (* = staged, live trace still on old config)        │
│ *[x] lists:seq -> return;stack          <- changed actions   │
│  [x] M:f/2 -> return;stack                                   │
│ *[x] gen_server:call -> return          <- newly enabled     │
│ *+ ets:lookup -> return                 <- newly added       │
│ Status:  ● running · ⚠ unapplied edits · 1.4k events         │  (yellow)
│ [Ctrl+S apply & restart]  [X stop]       [Ctrl+W save as preset] │
```

**3. draft (empty session)**
```
│ Session: sess-C @ app@host2  [draft]                         │
│ Traces:  (empty — no RTP yet)                                │
│  + add RTP                                                   │
│ Status:  · draft                                            │
│ [S start] dim (needs >=1 enabled RTP)   [Ctrl+W] dim         │
```

**4. inline edit RTP (enter)**
```
│  [x] |M:f/2 -> return;stack_              <- editing, cursor  │
│      └ syntax: Mod:Fun/Arity [when …] -> return;stack        │
│ enter / esc commit (auto-saved)                              │
```

**5. add new RTP (a)**
```
│  |_                                        <- new empty line  │
│   └ syntax: Mod:Fun/Arity [when …] -> return;stack           │
│ enter / esc commit (empty discarded)                         │
```

**6. apply/start failed**
```
│ Status:  ✗ apply failed: {badrpc, nodedown} · now stopped    │  (red)
│ [S retry]                          [Ctrl+W save as preset]   │
```

**7. inline edit limits (enter on Limits row)**
```
│ Limits:  time |24h_   msgs 1e6   keep 500   <- time field    │
│ tab next field · enter / esc commit (auto-saved)             │
```

**8. delete RTP (item-level, Ctrl+D, no second confirm)**
Deletes immediately (Ctrl modifier is the safeguard).

**8b. save as preset (Ctrl+W) — overwrite or new**
```
┌─ Save as preset ─────────────────────────────────┐
│ name: |_                                          │
│ ── existing (select to overwrite) ──              │
│   lists-trace        2 traces                     │
│   genserver-call     1 trace                      │
│ type new name = create · select existing = overwrite │
│ enter save · esc cancel                           │
└────────────────────────────────────────────────────┘
```
- typing a new name → create new preset.
- selecting (or typing a name matching) an existing preset → overwrite.
- overwrite is a data change → second confirm:
```
┌─ Overwrite preset? ──────────────────────────────┐
│ "lists-trace" will be replaced by this session's traces. │
│  [y] overwrite   [n/esc] cancel                   │
└────────────────────────────────────────────────────┘
```

**9. exit while running with unapplied-to-live edits → prompt**
```
┌─ Unapplied to live trace ─────────────────────┐
│ sess-A has 3 config changes not yet applied.  │
│  [Ctrl+S]  Apply & restart now                │
│  [enter]   Leave running (apply later)        │
│  [esc]     Cancel (stay on editor)            │
└────────────────────────────────────────────────┘
```
- edits are already saved to config; this only concerns pushing them to the live trace.
- Apply & restart: restart redbug with the new config.
- Leave running: keep the live trace on the old config; the `*`/`⚠` markers persist until applied.

### Constraints
- one running session per node; starting another warns/stops the other.
- RTP not validated client-side; redbug validates, failures shown in Status.
- start requires >=1 enabled RTP.
- limits: `keep` is TUI-side buffer cap (stream limit); `time`/`msgs` are redbug-side.
- **start auto-connects**: if the node is disconnected, `S` first connects
  (`⟳ connecting…`) then starts redbug; connect failure → start fails (state 6).
  `X` stop does NOT disconnect (connection reused); disconnect is manual via `c`.

---

## Screen 4 — Preset Manager [CONFIRMED]

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
│ enter view/edit · n new · Ctrl+D delete · esc back │
└──────────────────────────────────────────────────┘
```

**2. view/edit a preset (enter)**
```
┌─ Preset: lists-trace ────────────────────────────┐
│ name: lists-trace                                 │
│ Traces:                                           │
│  [x] lists:seq -> return                          │
│  [x] lists:map -> return;stack                    │
│  + add RTP                                        │
│ Limits:  time 24h   msgs 1e6   keep 500           │
│ space toggle · enter edit RTP · a add · Ctrl+D del │
│ esc back (edits auto-saved)                        │
└──────────────────────────────────────────────────┘
```
- reuses S3's Traces + Limits editing UI, but **no start/stop** (preset is a template).
- edits auto-persist on commit (no Ctrl+S; no staged/restart concept — preset isn't live).
- **rename inline**: `enter` on the `name:` row → inline rename (`enter`/`esc` commit).

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

## Screen 5 — Node Editor [CONFIRMED]

Overlay, entered from S1 `n` (new) / `e` (edit node). Add/edit a connection target.

```
┌─ Node ───────────────────────────────────────────┐
│ name:    |app@host_                               │
│ cookie:  ••••••                                   │
│ tab next field · enter save · esc cancel          │
└──────────────────────────────────────────────────┘
```

Fields:
- **name**: Erlang node name `app@host` (longname). Show a format hint while typing
  (`name@host`); no hard client-side validation — connection errors are reported on connect.
- **cookie**: distributed cookie. Masked on input (`••••`).

### Decisions
- **cookie stored plaintext** in `~/.redbug/config.json`. cookie == RCE, so the config
  file should be `0600` (owner-only) even though stored in clear.
- **name validation**: none up front; errors surface on connect
  (`✗ nodedown` / bad cookie / etc.). Input shows a `name@host` hint only.
- **delete node cascades to its sessions** (structural → second confirm).

### Connect feedback (on `c` / save)
```
│ Status: ⟳ connecting…  /  ✓ connected  /  ✗ nodedown / bad cookie │
```

### Delete node (Ctrl+D, structural → second confirm)
```
┌─ Delete node? ───────────────────────────────────┐
│ "app@host1" and its 2 sessions will be removed.   │
│  [y] confirm   [n/esc] cancel                     │
└──────────────────────────────────────────────────┘
```

---

## Screen 6 — Settings [CONFIRMED]

Overlay, global entry key `,` (from any screen). Global preferences, persisted to config.

```
┌─ Settings ───────────────────────────────────────┐
│ Columns (event list):                             │
│   ts      [x] (locked)                            │
│   k       [x] (locked)                            │
│   name    [x]                                     │
│   pid     [x]                                     │
│   mfa     [x]                                     │
│   info    [x]                                     │
│ ── Defaults ──                                    │
│   default sort     ts ↓                           │
│   default limits   time 24h  msgs 1e6  keep 500   │
│   editor ($EDITOR) nvim          (env, read-only) │
│   theme            Tokyo Night ▸ (see Themes)     │
│ space toggle · enter edit value · esc back (auto-saves) │
└──────────────────────────────────────────────────┘
```

### Decisions
- entry: **global key `,`** (vim-style), from any screen.
- columns: name/pid/mfa/info toggleable; ts/k locked (cannot hide).
- **global default limits + sort**: stored here, applied to new sessions (editable per session).
- `$EDITOR`: read-only display of the env var (used by S2 `E`).
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

## Screen 7 — Help [CONFIRMED]

Overlay, global key `?`. Keybinding reference (grouped by screen) + kind legend +
conventions. Reference only; `j/k` scrolls if it overflows. `esc` closes.

```
┌─ Help ───────────────────────────────────────────────────┐
│ Event kinds:                                              │
│   ↓ call (cyan)    ↑ retn (green)                         │
│   → send (yellow)  ← recv (purple)                        │
│ ── Global ──                                              │
│   ?  help     ,  settings     q  quit     esc  back/close │
│ ── Tree (S1) ──                                          │
│   j/k move · enter open session · n new node · s new session │
│   e edit · c connect/disconnect · p presets · Ctrl+D delete │
│ ── Session Events (S2) ──                                │
│   j/k move/scroll · enter detail · ctrl+j/k prev/next     │
│   o sort · / filter · g group · tab focus                │
│   z zoom · E $EDITOR · S start · X stop · e edit traces   │
│   Ctrl+L clear buffer                                     │
│ ── Trace Editor (S3) ──                                  │
│   space toggle · enter edit · a add · Ctrl+D del RTP      │
│   S start · X stop · Ctrl+S apply&restart · Ctrl+W preset │
│ ── Conventions ──                                        │
│   Ctrl+ = destructive/heavy op                           │
└────────────────────────────────────────────────────────────┘
```
