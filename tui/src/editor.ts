declare const process: { env: Record<string, string | undefined>; cwd(): string }
declare const Bun: {
  write(path: string, data: string): Promise<number>
  file(path: string): { text(): Promise<string> }
  spawnSync(
    cmd: string[],
    opts?: { stdin?: string; stdout?: string; stderr?: string }
  ): { stdout: { toString(): string } }
  spawn(
    cmd: string[],
    opts?: { stdin?: string; stdout?: string; stderr?: string }
  ): { exited: Promise<number> }
}

type Renderer = { suspend: () => void; resume: () => void }

// GUI editors fork and return immediately, so we must pass a "wait" flag or we'd
// read the file back before the user saves. Keyed by the command basename;
// terminal editors (vi/vim/nvim/nano/emacs/helix/micro) block on their own.
const WAIT_FLAG: Record<string, string> = {
  code: "--wait",
  "code-insiders": "--wait",
  codium: "--wait",
  "vscodium": "--wait",
  cursor: "--wait",
  windsurf: "--wait",
  zed: "--wait",
  atom: "--wait",
  subl: "-w",
  mate: "-w"
}

export function editorName(): string {
  return process.env.EDITOR || process.env.VISUAL || "vi"
}

// Split $EDITOR into argv (it may already carry flags, e.g. "code --wait") and
// auto-append the wait flag for known GUI editors when the user hasn't already.
export function editorArgv(): string[] {
  const parts = editorName().trim().split(/\s+/).filter(Boolean)
  if (parts.length === 0) return ["vi"]
  const base = parts[0].split("/").pop() ?? parts[0]
  const flag = WAIT_FLAG[base]
  if (flag && !parts.some((p) => p === "-w" || p === "--wait")) parts.push(flag)
  return parts
}

// Find the git repository root from the current working directory,
// falling back to the CWD itself when not in a repo.
function redbugDir(): string {
  try {
    const result = Bun.spawnSync(["git", "rev-parse", "--show-toplevel"], { stdout: "pipe", stderr: "pipe" })
    const root = result.stdout.toString().trim()
    if (root) return `${root}/.redbug`
  } catch {
    // not in a git repo — fall through to cwd
  }
  return `${process.cwd()}/.redbug`
}

// Seed a temp file under .redbug/ so it lives inside the project tree
// (autocomplete, LSP, go-to-def) instead of a bare /tmp path.
export async function editInEditor(
  renderer: Renderer,
  opts: { file: string; seed: string; readBack?: boolean }
): Promise<string | null> {
  const dir = redbugDir()
  // Ensure the .redbug directory exists
  try { Bun.spawnSync(["mkdir", "-p", dir], { stdout: "pipe", stderr: "pipe" }) } catch { /* ok */ }
  const path = `${dir}/${opts.file}`
  await Bun.write(path, opts.seed)
  renderer.suspend()
  try {
    // Async spawn (not spawnSync): a synchronous spawn blocks Bun's single event
    // loop for the whole editor session, starving the Phoenix heartbeat so the
    // server drops the socket and live stores disconnect. Awaiting `exited` keeps
    // the loop running (heartbeats fire) while the editor owns the terminal.
    const proc = Bun.spawn([...editorArgv(), path], { stdin: "inherit", stdout: "inherit", stderr: "inherit" })
    await proc.exited
  } finally {
    renderer.resume()
  }
  if (opts.readBack === false) return null
  try {
    return await Bun.file(path).text()
  } catch {
    return null
  }
}
