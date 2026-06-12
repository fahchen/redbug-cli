declare const process: { env: Record<string, string | undefined> }
declare const Bun: {
  write(path: string, data: string): Promise<number>
  file(path: string): { text(): Promise<string> }
  spawnSync(
    cmd: string[],
    opts?: { stdin?: string; stdout?: string; stderr?: string }
  ): unknown
}

type Renderer = { suspend: () => void; resume: () => void }

export function editorName(): string {
  return process.env.EDITOR || process.env.VISUAL || "vi"
}

// Seed a temp file, hand the terminal to $EDITOR, then read it back. With
// readBack: false the file is write-only (caller doesn't need the result).
export async function editInEditor(
  renderer: Renderer,
  opts: { file: string; seed: string; readBack?: boolean }
): Promise<string | null> {
  const dir = (process.env.TMPDIR || "/tmp").replace(/\/$/, "")
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
