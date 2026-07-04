# redbug TUI redesign — opencode-inspired

Direction (locked): **full pivot from the 8-bit cartridge look to an opencode-style
minimal TUI**, and redesign the UX end to end. opencode's TUI runs on the same
`@opentui` renderer, so its patterns port directly.

Register: product. Scene: an engineer watching live Erlang traces stream past in a
terminal, wants dense signal and quiet chrome, glances at connection health, drives
everything from the keyboard.

## Design principles (from opencode)

1. **Borders as accents, not frames.** No full boxes. Panels read as colored margins:
   a left (or left+right) `┃` vertical, empty corners/horizontals. Active pane gets a
   brighter vertical; inactive is subtle.
2. **Color-weight hierarchy over dividers.** `text` vs `textMuted` separates primary
   from secondary (paths, counts, hints). Almost no rule lines.
3. **Left-gutter indentation for rhythm** (paddingLeft 2/3), not chrome.
4. **One overlay primitive: DialogSelect** — a fuzzy-filtered list (title, description,
   category, per-row footer/keybinding). Command palette, node/preset/sort/filter/
   snippet pickers all become this.
5. **Command palette (ctrl+p)** fed by a keymap registry; each row shows its live key;
   "Suggested" pinned on top when unfiltered.
6. **Leader key + which-key.** A leader (opencode uses `ctrl+x`, 2s timeout); pressing it
   pops a which-key panel of pending completions. Replaces memorized shortcuts.
7. **Semantic theme tokens.** `defs` (named colors) + `theme` (semantic assignments),
   each value flat or `{dark,light}`. Tokens: `primary/accent`, `error/warning/success/
   info`, `text/textMuted`, `background{,Panel,Element,Menu}`, `border{,Active,Subtle}`,
   plus syntax/diff groups. Optional `system` theme reads the terminal palette.
8. **Contrast-aware selected foreground** (avoid the generic inverted white-on-accent bar).
9. **Footer, not header.** One line: left `cwd`/context, right health pills
   (connected count, LSP/trace status). No top breadcrumb.
10. **Feedback:** braille spinner `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` @80ms (degrade to `⋯`); top-right toast with
    a `┃` accent; empty states as quiet nudges.

## Mapping to redbug (node ▸ session ▸ events / console)

- Two-pane master-detail → gutter-separated columns; drop the double frames.
- Long footer hint strings → command palette + which-key; footer shows pills only.
- Node picker / preset picker / sort / filter / snippet / new-session → one DialogSelect.
- Node connection status → color-weight + a health pill, not a framed banner.
- Event stream stays a dense table; use textMuted for repeats (ditto), gutter for rhythm.

## Phased plan

- **P0 — Theme foundation.** Restructure `theme.ts` into semantic tokens (defs + theme),
  remap existing named themes, add `background*/border*/textMuted/*` roles, pick a refined
  default (retire PICO-8 as default; keep as an optional theme). Add contrast helper.
- **P1 — Frameless layout.** Replace `border`/`PANEL_BORDER` boxes with a `Gutter`
  component (left/right `┃`), color-weight hierarchy, gutter indentation. Rework nodes,
  session, console screens.
- **P2 — Footer pills.** Compact status pills (connected N/total, trace running); strip
  the long hint strings.
- **P3 — DialogSelect + command palette.** Build the fuzzy-list primitive; add ctrl+p
  palette from a keymap registry; migrate every existing picker onto it.
- **P4 — Leader + which-key.** Leader key, which-key panel, remap actions through the
  keymap registry.
- **P5 — Polish.** Braille spinner, toast, empty states, selected-fg contrast, motion
  degradation.

## Built-in components (locked): no hand-written components

Use opentui built-ins only, migrate hand-rolled parts:
- event stream / lists → `<scrollbox>` + `<scrollbar>` ✅ DONE (events + console history)
- ALL pickers → `<select>` ✅ DONE: sort, new-session-preset, console snippet,
  filter-scope, trace/RTP editor. Hand-rolled `PickRow`, `RtpRow`, `FilterScopePicker`
  all deleted.
  - toggle lists (RTP editor): `<select>` owns j/k nav; enabled state encoded in the
    option label (`[x]`/`[ ]`); space/n/e/d stay global keys (`<select>` ignores them).
  - compound overlay (filter): scope `<select>` + query `<input>`, Tab toggles focus
    between them (new `filterFocus` state).
  - `<select>` has no intrinsic height → every one needs `height={options.length}` +
    `itemSpacing={0}` or it collapses to a single visible row.
- Events/Console tabs → plain `<text>` toggle (⚠ `<tab-select>` rejected: no controlled
  `selectedIndex`, owns its own state — bad fit for our vim H/L + Ctrl+arrow switching)
- Elixir/Erlang term coloring → `<code>` (tree-sitter) ✅ DONE; hand-written `term.ts`
  colorizer + `TermLine` deleted
- inputs → `<input>`/`<textarea>` (already)

## Elixir highlighting ✅ DONE (verified live)

- Vendored `tui/assets/elixir/tree-sitter-elixir.wasm` + `highlights.scm`.
- `src/treesitter.ts`: shared `TreeSitterClient` (dataPath /tmp cache) +
  `SyntaxStyle.fromStyles` mapping capture groups to theme tokens; `ensureTreeSitter()`
  warms it at startup (index.tsx).
- `<code content filetype="elixir" syntaxStyle treeSitterClient>` in the event
  DetailPane + zoom, replacing the hand-written term.ts colorizer there.
- Verified in a live trace: `%{count: 334, at: …, items: [:a, :b, 334], ok?: true}`
  renders with atoms lavender, numbers gold, punctuation muted.

## Notes / to verify

- `@opentui` support for terminal palette detection (opencode uses
  `renderer.paletteDetectionStatus`) — confirm in this version before committing to a
  `system` theme.
- Fuzzy match: small dependency (fuzzysort) vs a tiny hand-rolled scorer. Prefer no new
  dep if a ~30-line scorer suffices.
- This supersedes the 8-bit work in `nodes-redesign.md` Track 2 (frames/HUD/pixel glyphs);
  the Track 1/3 backend (status enum, auto-connect, retry) stays.
