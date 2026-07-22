import { basename, join } from "node:path"
import { homedir } from "node:os"
import { mkdir, mkdtemp, rename, rm } from "node:fs/promises"
import { file, spawn, write } from "bun"

// The opentui tree-sitter worker + its web-tree-sitter wasm, pre-bundled and
// tar.gz'd at package time (see the `package` mise task). bun --compile can't fold
// a Worker that's spawned from a runtime path string into the binary, so the
// packaged CLI otherwise dies with
// `ModuleNotFound resolving "/$bunfs/root/parser.worker.ts"`. We embed the bundle
// and extract it to a real dir at startup, then aim the client at the on-disk
// worker — its wasm sidecar resolves relative to the worker file.
import tsWorkerTarball from "../embed/ts-worker.tar.gz" with { type: "file" }

// Called from main.tsx before the TUI loads (and thus before ensureTreeSitter's
// initialize() spawns the worker), so the override is in place when the worker
// spawns. opentui's TreeSitterClient reads OTUI_TREE_SITTER_WORKER_PATH from the
// environment before its bundle-broken default resolution.
export async function configureEmbeddedTreeSitterWorker(): Promise<void> {
  const dir = await ensureExtracted()
  process.env.OTUI_TREE_SITTER_WORKER_PATH = join(dir, "ts-worker", "parser.worker.js")
}

// Extract into ~/Library/Application Support/redbug/<hash>/ exactly once. bun
// content-hashes the embedded basename, so a new build extracts fresh while old
// payloads stay cached — same scheme as the embedded server release.
async function ensureExtracted(): Promise<string> {
  const base = join(homedir(), "Library", "Application Support", "redbug")
  const key = basename(tsWorkerTarball).replace(/[^a-zA-Z0-9]+/g, "-")
  const dest = join(base, key)

  if (await file(join(dest, "ts-worker", "parser.worker.js")).exists()) return dest

  await mkdir(dest, { recursive: true })
  const tmp = await mkdtemp(join(base, ".tsw-extract-"))
  try {
    const tarPath = join(tmp, "ts-worker.tar.gz")
    await write(tarPath, file(tsWorkerTarball))
    const tar = spawn(["tar", "-xzf", tarPath, "-C", tmp])
    if ((await tar.exited) !== 0) throw new Error("failed to extract embedded tree-sitter worker")
    // archive root is `ts-worker/`; promote it into the versioned cache dir.
    await rename(join(tmp, "ts-worker"), join(dest, "ts-worker"))
    return dest
  } finally {
    await rm(tmp, { recursive: true, force: true })
  }
}
