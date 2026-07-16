/** @jsxImportSource @opentui/react */
import { createCliRenderer } from "@opentui/core"
import { createRoot } from "@opentui/react"

import { App } from "./App"
import { connect, MusubiProvider, socket } from "./musubi"
import { warmHighlighter } from "./CodeBlock"

const renderer = await createCliRenderer({ exitOnCtrlC: true })
const connection = await connect(socket)

// warm the lumis Elixir highlighter so code blocks paint highlighted on mount
void warmHighlighter()

createRoot(renderer).render(
  // MusubiProvider is a React context provider typed for the React DOM JSX
  // runtime; under OpenTUI's JSX its ReactNode return type isn't a valid
  // OpenTUI element. Runtime is fine — the reconciler renders context fine.
  // @ts-expect-error cross-runtime JSX element type mismatch
  <MusubiProvider connection={connection}>
    <App />
  </MusubiProvider>
)
