declare const process: { env: Record<string, string | undefined>; cwd(): string }
declare const Bun: {
  write(path: string, data: string): Promise<number>
  file(path: string): { text(): Promise<string> }
  spawnSync(
    cmd: string[],
    opts?: { stdin?: string; stdout?: string; stderr?: string }
  ): { stdout: { toString(): string } }
}

type Renderer = { suspend: () => void; resume: () => void }

export function editorName(): string {
  return process.env.EDITOR || process.env.VISUAL || "vi"
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
    Bun.spawnSync([editorName(), path], { stdin: "inherit", stdout: "inherit", stderr: "inherit" })
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
