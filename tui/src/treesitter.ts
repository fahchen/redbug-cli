import { SyntaxStyle, TreeSitterClient } from "@opentui/core"

import { theme } from "./theme"

declare const Bun: { fileURLToPath(url: URL): string }

// Vendored Elixir grammar + highlights query (see tui/assets/elixir). Loaded from
// local file paths so the compiled dist stays offline-capable.
const wasm = Bun.fileURLToPath(new URL("../assets/elixir/tree-sitter-elixir.wasm", import.meta.url))
const highlights = Bun.fileURLToPath(new URL("../assets/elixir/highlights.scm", import.meta.url))

export const tsClient = new TreeSitterClient({ dataPath: "/tmp/redbug-ts-cache" })

// Map Elixir tree-sitter capture groups to theme colors. Unknown groups fall back
// to `default`. Atoms/keys (string.special.symbol) get their own hue since they
// dominate Erlang/Elixir term output.
export const elixirStyle = SyntaxStyle.fromStyles({
  comment: { fg: theme.textMuted, italic: true },
  string: { fg: theme.success },
  "string.special.symbol": { fg: theme.recv },
  number: { fg: theme.send },
  "constant.builtin": { fg: theme.send },
  constant: { fg: theme.send },
  keyword: { fg: theme.primary },
  operator: { fg: theme.textMuted },
  function: { fg: theme.info },
  "function.call": { fg: theme.info },
  module: { fg: theme.warning },
  variable: { fg: theme.text },
  punctuation: { fg: theme.textMuted },
  "punctuation.bracket": { fg: theme.textMuted },
  "punctuation.delimiter": { fg: theme.textMuted },
  default: { fg: theme.text }
})

let initPromise: Promise<void> | null = null

// Idempotent warm-up: initialize the worker + register the Elixir parser once.
// Safe to call early (at app start) so <code> renders highlighted on first paint.
export function ensureTreeSitter(): Promise<void> {
  if (!initPromise) {
    initPromise = (async () => {
      await tsClient.initialize()
      tsClient.addFiletypeParser({
        filetype: "elixir",
        queries: { highlights: [highlights] },
        wasm
      })
    })()
  }
  return initPromise
}
