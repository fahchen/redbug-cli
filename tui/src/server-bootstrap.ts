import { basename, join } from "node:path"
import { homedir, tmpdir } from "node:os"
import { mkdir, mkdtemp, rename, rm } from "node:fs/promises"
import { connect as netConnect } from "node:net"
import { file, spawn, write } from "bun"

// The `server` mix release (ERTS + app), tar.gz'd at package time. Bun embeds the
// bytes into the compiled binary and rewrites this import to a `$bunfs/...` path
// whose basename carries a content hash — we reuse that hash as the cache key.
import serverTarball from "../embed/server.tar.gz" with { type: "file" }

export type EmbeddedServer = { port: number; stop: () => void }

// Always boot the controller with the connect-only epmd shim (Server.Epmd):
// pinned endpoints (REDBUG_NODES / SSH tunnels) dial direct, unpinned names fall
// back to real epmd. The shim module only loads once the app starts, so
// distribution must not come up at release boot (RELEASE_DISTRIBUTION=none);
// Server.Application then self-distributes after the code is available.
function shimEnv(): Record<string, string> {
  const shim = "-start_epmd false -epmd_module Elixir.Server.Epmd"
  const existing = process.env.ERL_FLAGS
  return {
    ERL_FLAGS: existing ? `${shim} ${existing}` : shim,
    RELEASE_DISTRIBUTION: "none"
  }
}

// Boot the embedded controller: extract the release once, spawn it, wait until its
// WebSocket port is accepting connections, then hand the port back to the TUI.
export async function bootEmbeddedServer(): Promise<EmbeddedServer> {
  const root = await ensureExtracted()
  const bin = join(root, "server", "bin", "server")

  const portDir = await mkdtemp(join(tmpdir(), "redbug-port-"))
  const portFile = join(portDir, "port")

  const proc = spawn([bin, "start"], {
    // Pipe-backed stdio (never the terminal): the TUI owns the real TTY, so any
    // server output here would corrupt its screen.
    stdin: "ignore",
    stdout: "ignore",
    stderr: "ignore",
    // REDBUG_PARENT_PID lets the controller stop itself if this process is killed
    // without its signal handlers running (SIGKILL/crash), instead of orphaning
    // with live traces (see Server.ParentWatch).
    env: {
      ...process.env,
      REDBUG_PORT_FILE: portFile,
      REDBUG_PARENT_PID: String(process.pid),
      ...shimEnv()
    }
  })

  const port = await waitForReady(portFile)
  await rm(portDir, { recursive: true, force: true })

  // SIGTERM lets the release drain gracefully (it traps it); proc.kill() defaults
  // to SIGTERM. Idempotent — safe to call from multiple exit paths.
  return { port, stop: () => proc.kill() }
}

// Extract the release into ~/Library/Application Support/redbug/<hash>/ exactly once.
// The hash in the embedded filename changes every build, so a new binary extracts
// fresh and old payloads stay cached until cleaned.
async function ensureExtracted(): Promise<string> {
  const base = join(homedir(), "Library", "Application Support", "redbug")
  // bun inserts a content hash before the final extension (server.tar-<hash>.gz),
  // so the whole basename is build-unique; sanitize it into a tidy dir name.
  const key = basename(serverTarball).replace(/[^a-zA-Z0-9]+/g, "-")
  const dest = join(base, key)

  if (await file(join(dest, "server", "bin", "server")).exists()) return dest

  await mkdir(dest, { recursive: true })
  const tmp = await mkdtemp(join(base, ".extract-"))
  try {
    const tarPath = join(tmp, "server.tar.gz")
    await write(tarPath, file(serverTarball))
    const tar = spawn(["tar", "-xzf", tarPath, "-C", tmp])
    if ((await tar.exited) !== 0) throw new Error("failed to extract embedded server release")
    // tar archive root is `server/`; promote it into the versioned cache dir.
    await rename(join(tmp, "server"), join(dest, "server"))
    return dest
  } finally {
    await rm(tmp, { recursive: true, force: true })
  }
}

async function waitForReady(portFile: string, timeoutMs = 20_000): Promise<number> {
  const deadline = Date.now() + timeoutMs
  let port = 0
  while (Date.now() < deadline) {
    if (!port) {
      const f = file(portFile)
      if (await f.exists()) {
        const text = (await f.text()).trim()
        if (text) port = Number.parseInt(text, 10)
      }
    }
    if (port && (await tcpUp(port))) return port
    await Bun.sleep(150)
  }
  throw new Error("embedded server did not become ready in time")
}

function tcpUp(port: number, host = "127.0.0.1"): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = netConnect({ port, host })
    socket.once("connect", () => {
      socket.destroy()
      resolve(true)
    })
    socket.once("error", () => resolve(false))
  })
}
