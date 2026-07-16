/** @jsxImportSource @opentui/react */
import { createCliRenderer } from "@opentui/core"
import { createRoot } from "@opentui/react"

import { App } from "./App"
import { connect, MusubiProvider, socket } from "./musubi"
import { ensureTreeSitter } from "./treesitter"

const renderer = await createCliRenderer({ exitOnCtrlC: true })
const connection = await connect(socket)

// warm the Elixir tree-sitter parser so <code> highlights on first paint
void ensureTreeSitter()

createRoot(renderer).render(
  // MusubiProvider is a React context provider typed for the React DOM JSX
  // runtime; under OpenTUI's JSX its ReactNode return type isn't a valid
  // OpenTUI element. Runtime is fine — the reconciler renders context fine.
  // @ts-expect-error cross-runtime JSX element type mismatch
  <MusubiProvider connection={connection}>
    <App />
  </MusubiProvider>
)
