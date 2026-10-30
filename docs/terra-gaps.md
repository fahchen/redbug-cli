# Terra TUI gaps

The Terra TUI (`server/lib/server/tui/`) replaces the Bun TUI (`tui/src/`), which #10 removed with the Phoenix WebSocket layer. [Terra](https://github.com/uminocelo/terra) stays at the pinned commit `30dea5667d7e4ae5777aa3df77acb36c4aac6967` of PBeam, with no change. When Terra cannot do a feature of the Bun TUI, the Terra TUI cuts or simplifies the feature. This file records each such feature. Each PR that cuts or simplifies a feature adds or updates its entry.

Each entry gives the original behavior with its file reference (a removed file has the form `tui/src/App.tsx@8b4cec82:60-69`: the path and lines at the last commit that had the file), the behavior now, the reason (what Terra does not have), what a restore needs, and the status with the PR.

Status values: `cut` (the feature is not in the Terra TUI), `simplified` (a smaller form of the feature is in the Terra TUI), `restored` (a later PR restored the feature).

## Overlays become full-screen pages

- Original: the node form, the delete and quit questions, and the help show as overlays: a centered panel over the screen with a dark scrim (`tui/src/ui.tsx@8b4cec82:156-204`, `tui/src/NodeModal.tsx@8b4cec82:134-212`, `tui/src/ConfirmOverlay.tsx@8b4cec82:18-29`, `tui/src/NodeModal.tsx@8b4cec82:93-132`).
- Now: each one is a full-screen page. The node list is not visible behind it.
- Reason: Terra has no layers, no absolute position, and no alpha blend. A later view replaces the earlier one.
- Restore: Terra needs an overlay primitive (a view placed over another view at a position), or the app must merge two grids.
- Status: simplified, #7.

## Flex layout becomes sizes from the resize event

- Original: the right panel grows to fill the width (`flexGrow=1`), the status bar does not shrink, and the detail chips wrap in a row (`tui/src/App.tsx@8b4cec82:545-584`, `tui/src/Tree.tsx@8b4cec82:91-111`).
- Now: the app keeps the size of the last `{:resize, w, h}`. The node list is 40 columns, and the detail panel takes the other columns. Each detail chip is on its own line.
- Reason: Terra has no flex grow or shrink and no wrap. A Terra box also fills all the rows and columns that it gets: the app puts the panels in a box with no border and one row of bottom padding to keep the status line free, and the detail box starts on the last column of the list box, so the two boxes share one border column with a `┌` (not a `┬`) at the top.
- Restore: Terra needs grow and shrink in stacks, and wrap in an hstack.
- Status: simplified, #7.

## Truecolor becomes 256 colors, and only one theme

- Original: 19 themes with truecolor hex values (`tui/src/theme.ts@8b4cec82:98-446`). The `theme` setting selects one (`tui/src/App.tsx@8b4cec82:98`).
- Now: the TUI uses the tokyo-night roles, each mapped to the nearest color of the 256-color palette (`server/lib/server/tui/theme.ex`). The `theme` setting has no effect on the Terra TUI. The settings screen cycles and saves the `theme` setting and shows `(only tokyo-night colors)` after the value.
- Reason: Terra styles take a named color or a palette index `0..255`, not RGB.
- Restore: Terra needs RGB colors (`38;2;r;g;b`). Without that, map the other 18 themes to 256 colors and read the `theme` setting.
- Status: simplified, #7.

## No background colors on panels and pages

- Original: the screen, the panels, and the overlay panel have a background color (`tui/src/App.tsx@8b4cec82:545`, `tui/src/ui.tsx@8b4cec82:101-131`, `tui/src/ui.tsx@8b4cec82:156-204`).
- Now: the terminal background shows. Only text cells have a background: the selected row and the detail chips.
- Reason: a Terra box has no background fill.
- Restore: Terra needs a background option on a box, or the app must pad each line with background cells.
- Status: simplified, #7.

## One border color for all panels

- Original: the focused panel has the active border color and title color; the other panel has the subtle colors (`tui/src/ui.tsx@8b4cec82:101-131`).
- Now: all borders use the one `:border` color of the Terra theme.
- Reason: Terra reads the border color from the theme, not from each box.
- Restore: Terra needs a border style option on a box. Without it, the focus between the node list and the sessions pane shows only as the selected session row, which has a background only while the sessions pane has the focus (#8). The events panel also does not take the warning or error border color of the node status (`tui/src/SessionScreen.tsx@8b4cec82:405-409`).
- Status: simplified, #7, #8.

## Long values are cut, not wrapped

- Original: a long chip value, such as a node error message, wraps (`tui/src/Tree.tsx@8b4cec82:91-111`, `tui/src/ui.tsx@8b4cec82:136-152`).
- Now: Terra cuts the line at the panel edge. The full error message is not visible on a narrow screen.
- Reason: Terra clips text and has no wrap.
- Restore: Terra needs text wrap, or the app must split the text into lines of the panel width.
- Status: simplified, #7.

## The node form is compact

- Original: each field has its label line and an input line, with a margin between fields and sections (about 40 rows, `tui/src/NodeModal.tsx@8b4cec82:275-314`). Each empty field shows its placeholder.
- Now: each field is one line (label, then input), and each section is one line. The form fits in 24 rows. Only the focused empty field shows its placeholder.
- Reason: the full-screen page has no scroll, and `Terra.Widget.input/2` shows the placeholder only when the input has focus.
- Restore: a scroll for the page, and a placeholder option for an input without focus.
- Status: simplified, #7.

## Form inputs have no Home, End, or Delete

- Original: the form inputs are opentui `<input>` fields, which move the cursor with Home and End and delete forward with Delete (`tui/src/NodeModal.tsx@8b4cec82:286-314`).
- Now: the inputs take characters, Backspace, and the left and right arrows.
- Reason: the Terra input parser has no Home, End, or Delete events, and `Terra.Widget.input_event/4` has no forward delete.
- Restore: Terra needs these keys in its parser and its input widget.
- Status: simplified, #7.

## Node delete does not sweep `$EDITOR` buffers

- Original: a node delete also removes the `$EDITOR` buffer files of its sessions under `.redbug/` (`tui/src/App.tsx@8b4cec82:364-369`, `reconcileEditFiles`).
- Now: the Terra TUI deletes the node and stops its traces and consoles, and leaves files that the Bun TUI wrote.
- Reason: the Terra TUI has no `$EDITOR` (Terra has no suspend and resume of the terminal), so it writes no buffer files.
- Restore: not needed while the TUI has no `$EDITOR`. #10 removed the Bun TUI, so no program writes new files. Delete an old `.redbug/` directory by hand.
- Status: cut, #7.

## No connection notices

- Original: `Connecting to BEAM…` while the WebSocket stores load, and `Lost connection to BEAM — retrying…` on a store error (`tui/src/App.tsx@8b4cec82:60-69`).
- Now: no notice. The TUI runs in the controller BEAM and reads `Server.Config` directly, so there is no connection to lose.
- Reason: architecture change, not a Terra limit.
- Restore: not needed.
- Status: cut, #7.

## Session overlays become full-screen pages

- Original: the sort dialog, the filter, the limits, the trace editor, the help, the error detail, and the questions (stop and leave, delete an event, delete a trace) show as overlays over the session screen (`tui/src/SessionScreen.tsx@8b4cec82:521-600`, `tui/src/SessionOverlays.tsx@8b4cec82:17-198`, `tui/src/SessionEditor.tsx@8b4cec82`, `tui/src/DialogSelect.tsx@8b4cec82`).
- Now: each one is a full-screen page (`server/lib/server/tui/session.ex`). The sort page is a list without the type-to-search of the dialog.
- Reason: Terra has no layers (see "Overlays become full-screen pages").
- Restore: the same as for the node screen overlays.
- Status: simplified, #8.

## The detail pane becomes a page, and zoom is cut

- Original: Enter opens the detail pane (46 columns) next to the event list. Tab moves the focus between the list and the pane. `z` zooms the detail to the full screen (`tui/src/SessionScreen.tsx@8b4cec82:230-243`, `tui/src/SessionDetail.tsx@8b4cec82:27-55`).
- Now: Enter opens the detail as a full-screen page. Esc and Tab close it. `z` has no function, because the page is full-screen already.
- Reason: Terra has no flex layout to share the width between a growing list and a fixed pane (see "Flex layout becomes sizes from the resize event").
- Restore: a list and pane split from the resize width, and a focus between them.
- Status: simplified, #8.

## No `$EDITOR` view of an event

- Original: `v` writes the event as an Elixir term to a file and opens it in `$EDITOR` (`tui/src/SessionScreen.tsx@8b4cec82:291`, `tui/src/sessionHelpers.ts@8b4cec82:150-190`).
- Now: `v` has no function. The detail page shows the term.
- Reason: Terra has no suspend and resume of the terminal for a child program.
- Restore: Terra needs a suspend and resume of the terminal.
- Status: cut, #8.

## Ctrl+J and Ctrl+K become Ctrl+N and Ctrl+P in the detail

- Original: in the detail pane, Ctrl+J and Ctrl+K select the next and the previous event (`tui/src/SessionScreen.tsx@8b4cec82:231-232`).
- Now: Ctrl+N and Ctrl+P select the next and the previous event.
- Reason: the Terra input parser reads byte `0x0A` (Ctrl+J) as `:enter`.
- Restore: Terra needs to tell Ctrl+J from Enter (for example with the kitty keyboard protocol).
- Status: simplified, #8.

## Ctrl+S becomes `a`

- Original: Ctrl+S applies the changed patterns and limits, which restarts the trace (`tui/src/SessionScreen.tsx@8b4cec82:250`).
- Now: `a` applies the changes. The hints show `x stop · a apply` while the changes are not applied.
- Reason: Terra takes raw mode from `:shell.start_interactive({:noshell, :raw})`. The raw mode of OTP clears only `ISTRIP` and `ICRNL` (OTP 29.1.1 `erts/emulator/nifs/common/prim_tty_nif.c:1111-1115`) and keeps `IXON`, so the terminal reads Ctrl+S as XOFF and stops the output. A PTY run showed the frozen screen.
- Restore: Terra or OTP needs to clear `IXON` in raw mode.
- Status: simplified, #8.

## The event list has no scroll box

- Original: the event list is a scroll box of up to 300 rows that sticks to the top while new events come (`stickyStart`), and the selection scrolls into view (`tui/src/SessionScreen.tsx@8b4cec82:483-512`). The detail pane scrolls a page with Ctrl+F and Ctrl+B.
- Now: the list shows a window of the rows that fits the screen. The window follows the selection; with no selection it shows the newest rows. The detail page scrolls by line with j and k and by page with Ctrl+F and Ctrl+B.
- Reason: Terra has no scroll box.
- Restore: Terra needs a scroll box with a scroll offset.
- Status: simplified, #8.

## Filter hits have no highlight, and the filter scope is a Tab cycle

- Original: each part of a cell that matches the filter has the warning background (`tui/src/SessionEvents.tsx@8b4cec82:84-104`). The filter overlay has a query field and a scope select, with Tab between them (`tui/src/SessionOverlays.tsx@8b4cec82:17-100`).
- Now: the matching rows show with no highlight. The filter page has the query input; Tab selects the next scope (all, mfa, pid, info).
- Reason: Terra has no select widget, and the page has one input. The row is cut to the width part by part, and this PR does not split the parts at the hits (Terra can show a background on text).
- Restore: split each cell at the hits before the cut; a select needs a Terra widget.
- Status: simplified, #8.

## The events title is on the left

- Original: the sort, filter, group, and fold state is the right-aligned title of the events panel (`tui/src/SessionScreen.tsx@8b4cec82:466-473`).
- Now: the title starts with `Events ·` on the left of the top border.
- Reason: a Terra box title is always on the left.
- Restore: Terra needs a title alignment option on a box.
- Status: simplified, #8.

## tree-sitter becomes makeup_elixir with a cache

- Original: the detail pane highlights the payload, the return, and the stack with the tree-sitter Elixir grammar in a worker (`tui/src/treesitter.ts@8b4cec82`, `tui/src/SessionDetail.tsx@8b4cec82:57-95`), in the colors of the theme.
- Now: `Server.Tui.Highlight` lexes the text with `makeup_elixir` and maps the token types to 256 colors. The lexer runs once for each event, return, and width; the screen state keeps the result. The detail page cuts each line into lines of the page width.
- Reason: the TUI runs in the BEAM with no tree-sitter. `makeup_elixir` takes 36 ms for each 46-line term on PBeam (2026-10-30), so the screen keeps the result.
- Restore: not needed while the colors are close. The other themes need a token color map.
- Status: simplified, #8.

## The session number jump has no timeout

- Original: in the sessions pane, the digits before `g` jump to that session. The digits clear after 2 s (`tui/src/App.tsx@8b4cec82:410-446`).
- Now: the digits clear on any key that is not a digit or `g`, and do not clear after a time.
- Reason: a timeout needs a Terra tick and a timer state for one key buffer; the clear on the next key gives the same result in normal use.
- Restore: a `{:tick, 2000, msg}` that clears the digits.
- Status: simplified, #8.

## No changed-trace marker in the editor

- Original: while the trace runs with changes that are not applied, the trace editor shows `* ` before each pattern that differs from the applied one (`tui/src/SessionEditor.tsx@8b4cec82:173-180`, `tui/src/sessionHelpers.ts@8b4cec82:136-140`).
- Now: no marker on the patterns. The status line shows `⚠ unapplied` and the hint `a apply`.
- Reason: not a Terra limit. The TUI gets only the applied signature from the runner, not the applied patterns.
- Restore: the runner snapshot and status messages need the applied patterns.
- Status: cut, #8.

## Session-screen features of #1425

- Original: `[` and `]` switch to the console tab, `,` opens the settings, `i` in the trace editor imports patterns from a preset, and Ctrl+W saves the patterns as a preset (`tui/src/SessionScreen.tsx@8b4cec82:255-258`, `tui/src/SessionScreen.tsx@8b4cec82:308`, `tui/src/SessionScreen.tsx@8b4cec82:312-375`, `tui/src/SessionScreen.tsx@8b4cec82:399-401`).
- Now: all four work with the same keys. #8 cut them until #9.
- Reason: not a Terra limit. The console, the presets, and the settings screens of the Terra TUI came with fahchen/pbeam#1425.
- Restore: done.
- Status: restored, #9.

## The console composes code in a single-line input

- Original: `n` (after a snippet pick) and `e` open the code in `$EDITOR`, and the run starts when the editor closes. `v` opens the code, the result, and the stdout in `$EDITOR` (`tui/src/ConsoleTab.tsx@8b4cec82:118-130`, `tui/src/ConsoleTab.tsx@8b4cec82:223-228`, `tui/src/ConsoleTab.tsx@8b4cec82:452-473`).
- Now: `n` and `e` open a full-screen page with a single-line input. Each line break of the code shows as `↵`, as in the snippet code input, and Enter runs the code with the line breaks back. `v` has no function; the detail panel shows the code, the result, and the stdout, and Ctrl+F and Ctrl+B scroll it by page.
- Reason: Terra has no suspend and resume of the terminal for a child program, and no multi-line input.
- Restore: Terra needs a suspend and resume of the terminal (for `$EDITOR`) or a multi-line input widget.
- Status: simplified, #9.

## Console overlays become full-screen pages

- Original: the snippet pick, the save as snippet name, the stop, clear, and delete questions, and the help show as overlays over the console (`tui/src/ConsoleTab.tsx@8b4cec82:296-370`).
- Now: each one is a full-screen page. The snippet pick is a list without the type-to-search of the dialog.
- Reason: Terra has no layers (see "Overlays become full-screen pages").
- Restore: the same as for the node screen overlays.
- Status: simplified, #9.

## The console history and detail have no scroll box or spinner

- Original: the history is a scroll box that follows the selection, and a running execution shows a spinner (`tui/src/ConsoleTab.tsx@8b4cec82:267-276`, `tui/src/ConsoleTab.tsx@8b4cec82:376-389`). The border of the history takes the node status color (`tui/src/ConsoleTab.tsx@8b4cec82:111-114`).
- Now: the history shows a window of rows that follows the selection. A running execution shows the fixed glyph `⟳`. All borders use the one border color.
- Reason: Terra has no scroll box and no border color for each box. A spinner needs a tick for each running execution; the app ticks only while a node connects.
- Restore: a scroll box and a border option in Terra; a tick while an execution runs.
- Status: simplified, #9.

## Preset import selects with space, and the overwrite adds a preset

- Original: `i` picks a preset, then space toggles each pattern, `a` toggles all, and Enter imports (`tui/src/SessionScreen.tsx@8b4cec82:319-368`, `tui/src/SessionEditor.tsx@8b4cec82:63-105`). Ctrl+W asks "Overwrite preset?" for a name that exists; the saveAsPreset command then adds a second preset with that name.
- Now: the same keys and the same result, on full-screen pages.
- Reason: Terra has no layers.
- Restore: the same as for the other overlays.
- Status: simplified, #9.

## Preset, snippet, and settings overlays become full-screen pages

- Original: the presets and snippets screens show the help, the name, pattern, and limits inputs, and the delete questions as overlays over the screen (`tui/src/PresetManager.tsx@8b4cec82:229-335`, `tui/src/SnippetManager.tsx@8b4cec82:209-260`). The settings screen is a centered overlay, and its help and inputs are overlays on it (`tui/src/SettingsScreen.tsx@8b4cec82:112-197`).
- Now: each overlay is a full-screen page in the state of the screen. The settings screen is a full-screen page. The list is not visible behind the page.
- Reason: Terra has no layers, no absolute position, and no alpha blend. A later view replaces the earlier one.
- Restore: Terra needs an overlay primitive, or the app must merge two grids.
- Status: simplified, #9.

## The focused panel shows `▸` in its title

- Original: the focused panel of the presets screen has the active border color and the primary title color (`tui/src/ui.tsx@8b4cec82:118-120`, `tui/src/PresetManager.tsx@8b4cec82:183`, `tui/src/PresetManager.tsx@8b4cec82:195`).
- Now: the title of the focused panel starts with `▸ `. All borders have one color.
- Reason: Terra draws all box borders in the one `:border` color of the theme. A box has no border color option.
- Restore: Terra needs a border color option on a box.
- Status: simplified, #9.

## Snippet code edits on one line, not in `$EDITOR`

- Original: `e` opens the code of the snippet in `$EDITOR` and saves it when the editor closes. A new snippet opens in `$EDITOR` after it is made (`tui/src/SnippetManager.tsx@8b4cec82:49-79`).
- Now: `e` opens a single-line input with the code. Each line break of the code shows as `↵`, and each `↵` becomes a line break again on save. The save formats the code with `Server.Code.Format`, so `;` between expressions gives new lines. A new snippet gets the selection, and its code input opens.
- Reason: Terra has no multi-line text input. Terra also cannot give the terminal to a child process and take it back.
- Restore: Terra needs a multi-line text area, or a suspend and resume of the terminal for `$EDITOR`.
- Status: simplified, #9.

## The snippet code has no scroll box

- Original: the code pane is a scroll box. Ctrl+F and Ctrl+B scroll it by a viewport, and a move to another snippet scrolls it to the top (`tui/src/SnippetManager.tsx@8b4cec82:113-114`, `tui/src/SnippetManager.tsx@8b4cec82:123`, `tui/src/SnippetManager.tsx@8b4cec82:128`). The lists follow the selection (`tui/src/PresetManager.tsx@8b4cec82:52-53`, `tui/src/SnippetManager.tsx@8b4cec82:43`).
- Now: the code pane shows one page of lines. Ctrl+F and Ctrl+B move by a page, and a move to another snippet goes back to the first page. The screen key function does not get the screen size, so the page count stops at the last line of the code, and the view stops at the last full page. After extra Ctrl+F presses at the end, Ctrl+B needs the same number of presses before the code moves. The lists show a window that follows the selection.
- Reason: Terra has no scroll box. The extra Ctrl+B presses are not a Terra limit: the screen contract `key(key, state)` of the app has no size.
- Restore: the app must give the size to the screen key function, so that the page count stops at the last page.
- Status: simplified, #9.

## tree-sitter becomes makeup_elixir in the snippet code

- Original: the code pane highlights the code with the tree-sitter Elixir grammar (`tui/src/SnippetManager.tsx@8b4cec82:192-197`).
- Now: `Server.Tui.Highlight` lexes the code with `makeup_elixir` and cuts each line to the pane width. The lexer runs on each draw, with no cache.
- Reason: the TUI runs in the BEAM with no tree-sitter.
- Restore: not needed while the colors are close. Add a cache if long snippets make the draw slow on PBeam.
- Status: simplified, #9.

## The snippet number jump has no timeout

- Original: the digits before `g` jump to that snippet. The digits clear after 2 s (`tui/src/SnippetManager.tsx@8b4cec82:148-167`).
- Now: the digits clear on any key that is not a digit or `g`, and do not clear after a time.
- Reason: a timeout needs a Terra tick and a timer state for one key buffer. The clear on the next key gives the same result in normal use.
- Restore: a `{:tick, 2000, msg}` that clears the digits.
- Status: simplified, #9.

## The settings screen has no `$EDITOR` row

- Original: the settings screen shows the `$EDITOR` command as a read-only row, and the help names it (`tui/src/SettingsScreen.tsx@8b4cec82:38`, `tui/src/SettingsScreen.tsx@8b4cec82:133-134`, `tui/src/SettingsScreen.tsx@8b4cec82:153`).
- Now: the settings screen has no `$EDITOR` row.
- Reason: not a Terra limit. The Terra TUI does not start `$EDITOR`, so the row has no function.
- Restore: add the row again when a Terra TUI screen starts `$EDITOR`.
- Status: cut, #9.

## Limits take whole numbers only

- Original: the preset limits and the default limits inputs read each value with `Number`, so `1.5` and `1e3` are valid (`tui/src/limits.ts@8b4cec82:10-14`).
- Now: each value must be a whole number of 0 or more, as in the session limits input. Other text changes nothing.
- Reason: not a Terra limit. The Terra TUI uses the same parser for all limits inputs, and the trace limits are whole numbers.
- Restore: parse floats and round them, if a user needs that.
- Status: simplified, #9.

## No mouse

- Original: the opentui renderer turns on the mouse (`createCliRenderer` in `tui/src/index.tsx@8b4cec82:9` does not set `useMouse`, and its default is `true`), so the mouse wheel scrolls the scroll boxes, and a click goes to the element under the pointer.
- Now: the TUI reads only keys.
- Reason: Terra has no mouse input.
- Restore: Terra needs mouse events (SGR mouse mode) in its parser and its runtime.
- Status: cut, #10.

## No TUI on a separate controller

- Original: the TUI connects to the controller over a Phoenix WebSocket at `REDBUG_HOST` and `REDBUG_PORT` (`tui/src/musubi.ts@8b4cec82:1-10`). The controller writes its port to `REDBUG_PORT_FILE`. A TUI can attach to a controller that started on its own, and more than one TUI can attach to one controller.
- Now: the TUI and the controller are one BEAM. `REDBUG_HOST`, `REDBUG_PORT`, and `REDBUG_PORT_FILE` have no function, and a second TUI needs a second controller.
- Reason: architecture change, not a Terra limit.
- Restore: not needed.
- Status: cut, #10.

## The controller does not watch a parent process

- Original: the launcher sets `REDBUG_PARENT_PID`, and `Server.ParentWatch` stops the controller when the TUI process stops without its signal handlers (for example on `SIGKILL`), so the traces do not stay on the targets (`server/lib/server/parent_watch.ex@8b4cec82`, `tui/src/server-bootstrap.ts@8b4cec82:39-53`).
- Now: no parent watch. A kill of the BEAM stops the TUI and the controller together.
- Reason: architecture change, not a Terra limit. The TUI is not a second process.
- Restore: not needed.
- Status: cut, #10.

## No single-file executable

- Original: `mise run package` builds `dist/redbug` with `bun build --compile`. The binary holds the release as a tarball, extracts it to `~/Library/Application Support/redbug/<hash>/` on the first run, starts the controller, and stops it when the TUI quits (`tui/src/main.tsx@8b4cec82`, `tui/src/server-bootstrap.ts@8b4cec82`, `mise.toml@8b4cec82`).
- Now: `mise run package` builds the release `server/_build/prod/rel/server`, and `bin/server start` in that directory starts the controller with the TUI. `OUT` has no function.
- Reason: bun is removed, not a Terra limit.
- Restore: `mix pbeam.build` (fahchen/pbeam#1427).
- Status: cut, #10.

## Known PBeam limit

On PBeam (`pbeam erl` of the release, `REDBUG_DIST=off`), the node screen works, but `q` then `y` ends the VM with exit status 1 and the error `pbeam: unsupported erlang:process_info/2 arguments ... [current_stacktrace, registered_name]`. `gen_server:client_stacktrace/1` makes that call when a `gen_server` stops abnormally during the shutdown (OTP 29.1.1 `lib/stdlib/src/gen_server.erl:2804`). On ERTS the same steps give exit status 0. This is a PBeam gap, not a Terra gap: fahchen/pbeam#1436.
