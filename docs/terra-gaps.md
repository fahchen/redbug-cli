# Terra TUI gaps

The Terra TUI (`server/lib/server/tui/`) replaces the Bun TUI (`tui/src/`). [Terra](https://github.com/uminocelo/terra) stays at the pinned commit `30dea5667d7e4ae5777aa3df77acb36c4aac6967` of PBeam, with no change. When Terra cannot do a feature of the Bun TUI, the Terra TUI cuts or simplifies the feature. This file records each such feature. Each PR that cuts or simplifies a feature adds or updates its entry.

Each entry gives the original behavior with its file reference, the behavior now, the reason (what Terra does not have), what a restore needs, and the status with the PR.

Status values: `cut` (the feature is not in the Terra TUI), `simplified` (a smaller form of the feature is in the Terra TUI), `restored` (a later PR restored the feature).

## Overlays become full-screen pages

- Original: the node form, the delete and quit questions, and the help show as overlays: a centered panel over the screen with a dark scrim (`tui/src/ui.tsx:156-204`, `tui/src/NodeModal.tsx:134-212`, `tui/src/ConfirmOverlay.tsx:18-29`, `tui/src/NodeModal.tsx:93-132`).
- Now: each one is a full-screen page. The node list is not visible behind it.
- Reason: Terra has no layers, no absolute position, and no alpha blend. A later view replaces the earlier one.
- Restore: Terra needs an overlay primitive (a view placed over another view at a position), or the app must merge two grids.
- Status: simplified, #7.

## Flex layout becomes sizes from the resize event

- Original: the right panel grows to fill the width (`flexGrow=1`), the status bar does not shrink, and the detail chips wrap in a row (`tui/src/App.tsx:545-584`, `tui/src/Tree.tsx:91-111`).
- Now: the app keeps the size of the last `{:resize, w, h}`. The node list is 40 columns, and the detail panel takes the other columns. Each detail chip is on its own line.
- Reason: Terra has no flex grow or shrink and no wrap. A Terra box also fills all the rows and columns that it gets: the app puts the panels in a box with no border and one row of bottom padding to keep the status line free, and the detail box starts on the last column of the list box, so the two boxes share one border column with a `┌` (not a `┬`) at the top.
- Restore: Terra needs grow and shrink in stacks, and wrap in an hstack.
- Status: simplified, #7.

## Truecolor becomes 256 colors, and only one theme

- Original: 19 themes with truecolor hex values (`tui/src/theme.ts:98-446`). The `theme` setting selects one (`tui/src/App.tsx:98`).
- Now: the TUI uses the tokyo-night roles, each mapped to the nearest color of the 256-color palette (`server/lib/server/tui/theme.ex`). The `theme` setting has no effect on the Terra TUI.
- Reason: Terra styles take a named color or a palette index `0..255`, not RGB.
- Restore: Terra needs RGB colors (`38;2;r;g;b`). Without that, map the other 18 themes to 256 colors and read the `theme` setting.
- Status: simplified, #7.

## No background colors on panels and pages

- Original: the screen, the panels, and the overlay panel have a background color (`tui/src/App.tsx:545`, `tui/src/ui.tsx:101-131`, `tui/src/ui.tsx:156-204`).
- Now: the terminal background shows. Only text cells have a background: the selected row and the detail chips.
- Reason: a Terra box has no background fill.
- Restore: Terra needs a background option on a box, or the app must pad each line with background cells.
- Status: simplified, #7.

## One border color for all panels

- Original: the focused panel has the active border color and title color; the other panel has the subtle colors (`tui/src/ui.tsx:101-131`).
- Now: all borders use the one `:border` color of the Terra theme.
- Reason: Terra reads the border color from the theme, not from each box.
- Restore: Terra needs a border style option on a box. The focus change between the node list and the sessions pane comes with #1424.
- Status: simplified, #7.

## Long values are cut, not wrapped

- Original: a long chip value, such as a node error message, wraps (`tui/src/Tree.tsx:91-111`, `tui/src/ui.tsx:136-152`).
- Now: Terra cuts the line at the panel edge. The full error message is not visible on a narrow screen.
- Reason: Terra clips text and has no wrap.
- Restore: Terra needs text wrap, or the app must split the text into lines of the panel width.
- Status: simplified, #7.

## The node form is compact

- Original: each field has its label line and an input line, with a margin between fields and sections (about 40 rows, `tui/src/NodeModal.tsx:275-314`). Each empty field shows its placeholder.
- Now: each field is one line (label, then input), and each section is one line. The form fits in 24 rows. Only the focused empty field shows its placeholder.
- Reason: the full-screen page has no scroll, and `Terra.Widget.input/2` shows the placeholder only when the input has focus.
- Restore: a scroll for the page, and a placeholder option for an input without focus.
- Status: simplified, #7.

## Form inputs have no Home, End, or Delete

- Original: the form inputs are opentui `<input>` fields, which move the cursor with Home and End and delete forward with Delete (`tui/src/NodeModal.tsx:286-314`).
- Now: the inputs take characters, Backspace, and the left and right arrows.
- Reason: the Terra input parser has no Home, End, or Delete events, and `Terra.Widget.input_event/4` has no forward delete.
- Restore: Terra needs these keys in its parser and its input widget.
- Status: simplified, #7.

## Node delete does not sweep `$EDITOR` buffers

- Original: a node delete also removes the `$EDITOR` buffer files of its sessions under `.redbug/` (`tui/src/App.tsx:364-369`, `reconcileEditFiles`).
- Now: the Terra TUI deletes the node and stops its traces and consoles, and leaves files that the Bun TUI wrote.
- Reason: the Terra TUI has no `$EDITOR` (Terra has no suspend and resume of the terminal), so it writes no buffer files.
- Restore: not needed while the TUI has no `$EDITOR`. #1426 removes the Bun TUI, which writes the files.
- Status: cut, #7.

## No connection notices

- Original: `Connecting to BEAM…` while the WebSocket stores load, and `Lost connection to BEAM — retrying…` on a store error (`tui/src/App.tsx:60-69`).
- Now: no notice. The TUI runs in the controller BEAM and reads `Server.Config` directly, so there is no connection to lose.
- Reason: architecture change, not a Terra limit.
- Restore: not needed.
- Status: cut, #7.

## Known PBeam limit

On PBeam (`pbeam erl` of the release, `REDBUG_DIST=off`), the node screen works, but `q` then `y` ends the VM with exit status 1 and the error `pbeam: unsupported erlang:process_info/2 arguments ... [current_stacktrace, registered_name]`. `gen_server:client_stacktrace/1` makes that call when a `gen_server` stops abnormally during the shutdown (OTP 29.1.1 `lib/stdlib/src/gen_server.erl:2804`). On ERTS the same steps give exit status 0. This is a PBeam gap, not a Terra gap.
