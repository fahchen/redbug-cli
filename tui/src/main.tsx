// Entry point for the single-file build (bun --compile). It boots the embedded
// controller, points the TUI at it, then loads the TUI. The standalone TUI
// build uses index.tsx directly and never touches the embedded server.
import { bootEmbeddedServer } from "./server-bootstrap"
import { configureEmbeddedTreeSitterWorker } from "./ts-worker-bootstrap"

const server = await bootEmbeddedServer()

// Point the tree-sitter client at the extracted worker before the TUI (and its
// ensureTreeSitter warm-up) loads — the runtime-path Worker isn't bundled by
// bun --compile, so the embedded copy must be extracted first.
await configureEmbeddedTreeSitterWorker()

process.env.REDBUG_HOST = "127.0.0.1"
process.env.REDBUG_PORT = String(server.port)

// Tear the controller down whenever the TUI process ends (quit key, Ctrl-C, kill).
process.once("exit", server.stop)
for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () => {
    server.stop()
    process.exit(0)
  })
}

// Dynamic import so musubi.ts reads REDBUG_PORT after we've set it above —
// a static import would evaluate (and build the socket URL) too early.
await import("./index")
