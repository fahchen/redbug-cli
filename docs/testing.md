# Testing & screenshots

## Automated tests

```sh
cd server && mix test
```

The e2e test (`test/session_root_test.exs`) drives the full store layer against a real target
node, so start a throwaway target first (see the README quick start).

The TUI has no headless test harness. Verify layout/visual changes by screenshotting the running
app (below).

## Screenshotting the TUI

opentui renders to a terminal, so there is no native web view. To capture screens, host the TUI
inside a browser terminal ([ttyd](https://github.com/tsl0922/ttyd)) and screenshot the page.

```
 mise run dev  ──►  ttyd (:7681)  ──►  browser  ──►  screenshot
  (server+TUI)      web terminal       xterm.js
```

### 1. Host the TUI as a web page

```sh
brew install ttyd   # once

# from the repo root
ttyd --writable -p 7681 -t fontSize=15 bash -lc 'exec mise run dev'
```

For the 8-bit look, render with a pixel/bitmap monospace that ships box-drawing
glyphs (so the `double` cartridge borders stay intact) — Terminus or Cozette
work; avoid Press Start 2P (no box-drawing):

```sh
ttyd --writable -p 7681 -t fontSize=15 -t 'fontFamily=Terminus (TTF)' \
  bash -lc 'exec mise run dev'
```

ttyd spawns the child **only when a browser connects**, so nothing boots until step 2. `mise run
dev` starts the controller on a random port, then the TUI; the server log goes to
`/tmp/redbug-server.log`.

### 2. Open, drive, capture

Open <http://localhost:7681> and resize the window to the terminal size you want (xterm reflows via
SIGWINCH). Click the terminal to focus it, then drive it with the keybindings.

On macOS, capture the window with `screencapture` (interactive selection or `-w` window mode):

```sh
screencapture -i ~/shot.png
```

Most screens render with the **local controller only** (no target node): the tree, settings,
presets, snippets, and every modal (`?` help, `n` node editor, `t` trace editor). Only the Session
Events stream needs a connected target with a live trace.

### 3. (optional) Submit screenshots for review

Screenshots can go straight into a Suikou file-selection review:

```sh
suikou project create --name redbug-cli --path "$(pwd)"   # first time only
suikou review create --project <id> --name "…" --files shot1.png,shot2.png
suikou review url <review-id>
```

### Teardown

Quitting the TUI (`q`) tears the controller down. Stop ttyd with `Ctrl-C` (or `pkill ttyd`).

### Agent note

An agent can automate step 2 end to end with the browser automation MCP/CLI:
open `http://localhost:7681`, resize the page, send keys/text to drive the TUI,
then capture a screenshot. ttyd's xterm.js forwards browser key events to the
pty, so browser key input reaches the TUI directly.
