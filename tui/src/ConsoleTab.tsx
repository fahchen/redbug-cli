/** @jsxImportSource @opentui/react */
import { useState } from "react"
import { useKeyboard, useRenderer } from "@opentui/react"
import type { StoreProxy } from "@musubi/react"

import { consoleRoot, dispatcher, useMusubiRoot, useMusubiSnapshot } from "./musubi"
import { editInEditor } from "./editor"
import { theme } from "./theme"
import { HelpOverlay, Overlay, PickRow, RootGate, StatusBar } from "./ui"

type ConsoleStore = StoreProxy<"Server.Stores.ConsoleRoot", Musubi.Stores>
type Exec = Server.Schema.ConsoleExec
type Snippet = Server.Schema.Snippet

type ExecStatus = "running" | "ok" | "error" | "stopped" | "timeout"

const STATUS_GLYPH: Record<ExecStatus, string> = {
  running: "⟳",
  ok: "✓",
  error: "✗",
  stopped: "⊘",
  timeout: "⧖"
}

function statusGlyph(status: string): string {
  return STATUS_GLYPH[status as ExecStatus] ?? "·"
}

function statusColor(status: string): string {
  switch (status as ExecStatus) {
    case "ok":
      return theme.on
    case "error":
    case "timeout":
      return theme.off
    case "running":
      return theme.warn
    default:
      return theme.dim
  }
}

export function ConsoleTab({
  nodeId,
  sessionId,
  onSwitchToEvents,
  onBack
}: {
  nodeId: string
  sessionId: string
  onSwitchToEvents: () => void
  onBack: () => void
}) {
  const root = useMusubiRoot(consoleRoot(nodeId, sessionId))
  return (
    <RootGate root={root} loading="Loading console…" errorLabel="Console">
      {(store) => (
        <ConsoleView store={store} onSwitchToEvents={onSwitchToEvents} onBack={onBack} />
      )}
    </RootGate>
  )
}

type Modal =
  | { kind: "none" }
  | { kind: "help" }
  | { kind: "pickSnippet" }
  | { kind: "confirmStop"; id: string }
  | { kind: "confirmClear" }

function ConsoleView({
  store,
  onSwitchToEvents,
  onBack
}: {
  store: ConsoleStore
  onSwitchToEvents: () => void
  onBack: () => void
}) {
  const snap = useMusubiSnapshot(store)
  const history = (snap?.history ?? []) as Exec[]
  const snippets = (snap?.snippets ?? []) as Snippet[]
  const renderer = useRenderer()
  const dispatch = dispatcher(store)

  const [sel, setSel] = useState(0)
  const [pick, setPick] = useState(0)
  const [modal, setModal] = useState<Modal>({ kind: "none" })

  const cur = history[Math.min(sel, history.length - 1)] ?? null

  const composeAndRun = (seed: string, name: string | null) => {
    void (async () => {
      const code = await editInEditor(renderer, {
        file: `redbug-console-compose-${Date.now()}.exs`,
        seed
      })
      if (code !== null && code.trim() !== "") dispatch("run", { code, name })
    })()
  }

  useKeyboard((key) => {
    const n = key.name

    if (modal.kind === "help") {
      setModal({ kind: "none" })
      return
    }

    if (modal.kind === "pickSnippet") {
      const max = snippets.length // 0 = blank, 1..N = snippets
      if (n === "j" || n === "down") setPick((i) => Math.min(i + 1, max))
      else if (n === "k" || n === "up") setPick((i) => Math.max(i - 1, 0))
      else if (n === "escape") setModal({ kind: "none" })
      else if (n === "return") {
        const snip = pick === 0 ? null : snippets[pick - 1]
        setModal({ kind: "none" })
        composeAndRun(snip?.code ?? "", snip?.name ?? null)
      }
      return
    }

    if (modal.kind === "confirmStop") {
      if (n === "y") {
        dispatch("stopExecution", { id: modal.id })
        setModal({ kind: "none" })
      } else if (n === "n" || n === "escape") setModal({ kind: "none" })
      return
    }

    if (modal.kind === "confirmClear") {
      if (n === "y") {
        dispatch("clearHistory")
        setModal({ kind: "none" })
      } else if (n === "n" || n === "escape") setModal({ kind: "none" })
      return
    }

    switch (n) {
      case "[":
        onSwitchToEvents()
        break
      case "escape":
        onBack()
        break
      case "j":
      case "down":
        setSel((i) => Math.min(i + 1, history.length - 1))
        break
      case "k":
      case "up":
        setSel((i) => Math.max(i - 1, 0))
        break
      case "n":
        setPick(0)
        setModal({ kind: "pickSnippet" })
        break
      case "e":
        if (cur) composeAndRun(cur.code, cur.name || null)
        break
      case "v":
        if (cur) void viewExec(renderer, cur)
        break
      case "r":
        if (cur) dispatch("run", { code: cur.code, name: cur.name || null })
        break
      case "s":
        if (cur && cur.status === "running") setModal({ kind: "confirmStop", id: cur.id })
        break
      case "c":
        if (history.length > 0) setModal({ kind: "confirmClear" })
        break
      case "?":
        setModal({ kind: "help" })
        break
    }
  })

  return (
    <box flexDirection="column" flexGrow={1} backgroundColor={theme.bg}>
      <box flexDirection="row" flexGrow={1}>
        <box
          border
          borderColor={theme.title}
          backgroundColor={theme.bg}
          title={`History (${history.length})`}
          titleColor={theme.title}
          width={38}
          flexDirection="column"
          padding={1}
        >
          {history.length === 0 ? (
            <text fg={theme.dim}>No executions yet · n to run</text>
          ) : (
            history.map((e, i) => <HistoryRow key={e.id} exec={e} active={i === sel} />)
          )}
        </box>

        <box
          border
          borderColor={theme.border}
          backgroundColor={theme.bg}
          title={cur ? `${cur.name || "execution"} — ${cur.status}` : "—"}
          titleColor={theme.title}
          flexGrow={1}
          flexBasis={0}
          flexDirection="column"
          padding={1}
        >
          {!cur ? (
            <text fg={theme.dim}>Select an execution</text>
          ) : (
            <ExecDetail exec={cur} />
          )}
        </box>
      </box>

      <StatusBar
        statusText={`${history.length} runs`}
        hints="j/k move · n new · r run · s stop · ? help · esc back"
      />

      {modal.kind === "help" && (
        <HelpOverlay
          title="session · console"
          sections={[
            {
              lines: [
                ["j / k", "move"],
                ["n", "new execution (pick snippet, compose)"],
                ["e", "edit + run selected"],
                ["v", "view full code + output in $EDITOR"],
                ["r", "run selected as-is"],
                ["s", "force-stop running execution"],
                ["c", "clear history"]
              ]
            },
            {
              title: "tabs",
              lines: [
                ["[", "switch to Events"],
                ["esc", "back"]
              ]
            }
          ]}
        />
      )}

      {modal.kind === "pickSnippet" && (
        <Overlay title="New execution — start from">
          <PickRow label="(blank)" active={pick === 0} />
          {snippets.map((s, i) => (
            <PickRow key={s.id} label={s.name} active={pick === i + 1} />
          ))}
          <text fg={theme.dim} marginTop={1}>j/k move · Enter compose in $EDITOR · Esc cancel</text>
        </Overlay>
      )}

      {modal.kind === "confirmStop" && (
        <Overlay>
          <text fg={theme.fg}>Force-stop (kill) this running execution?</text>
          <text fg={theme.dim} marginTop={1}>side effects already run cannot be undone · y = yes · n/Esc = no</text>
        </Overlay>
      )}

      {modal.kind === "confirmClear" && (
        <Overlay>
          <text fg={theme.fg}>Clear the entire execution history?</text>
          <text fg={theme.dim} marginTop={1}>history is server-held, not just this view · y = yes · n/Esc = no</text>
        </Overlay>
      )}
    </box>
  )
}

function HistoryRow({ exec, active }: { exec: Exec; active: boolean }) {
  const bg = active ? theme.selBg : theme.bg
  const fg = active ? theme.selFg : theme.fg
  const glyph = statusGlyph(exec.status)
  const label = exec.name?.trim() ? exec.name : firstLine(exec.code)
  return (
    <box backgroundColor={bg} flexDirection="row">
      <text bg={bg} fg={statusColor(exec.status)}>{`${glyph} `}</text>
      <text bg={bg} fg={theme.dim}>{`${exec.ts} `}</text>
      <text bg={bg} fg={fg}>{label}</text>
    </box>
  )
}

function ExecDetail({ exec }: { exec: Exec }) {
  const dur = exec.duration_ms == null ? "—" : `${exec.duration_ms}ms`
  return (
    <box flexDirection="column">
      <text fg={statusColor(exec.status)}>{`${statusGlyph(exec.status)} ${exec.status} · ${exec.ts} · ${dur}`}</text>
      <text fg={theme.dim} marginTop={1}>code</text>
      {wrap(exec.code, 60).slice(0, 12).map((l, i) => (
        <text key={`c${i}`} fg={theme.fg}>{l}</text>
      ))}
      {exec.result?.trim() !== "" && (
        <>
          <text fg={theme.dim} marginTop={1}>result</text>
          {wrap(exec.result, 60).slice(0, 10).map((l, i) => (
            <text key={`r${i}`} fg={theme.fg}>{l}</text>
          ))}
        </>
      )}
      {exec.output?.trim() !== "" && (
        <>
          <text fg={theme.dim} marginTop={1}>stdout</text>
          {wrap(exec.output, 60).slice(0, 10).map((l, i) => (
            <text key={`o${i}`} fg={theme.dim}>{l}</text>
          ))}
        </>
      )}
      <text fg={theme.dim} marginTop={1}>v opens full code + output in $EDITOR</text>
    </box>
  )
}

// --- editor helpers ---

async function viewExec(
  renderer: { suspend: () => void; resume: () => void },
  exec: Exec
): Promise<void> {
  const body = [
    `# ${exec.name || "execution"} · ${exec.status} · ${exec.ts}`,
    "",
    exec.code,
    "",
    "# === result ===",
    exec.result || "(none)",
    "",
    "# === stdout ===",
    exec.output || "(none)",
    ""
  ].join("\n")
  await editInEditor(renderer, {
    file: `redbug-console-view-${exec.id}-${Date.now()}.exs`,
    seed: body,
    readBack: false
  })
}

// --- pure helpers ---

function firstLine(s: string): string {
  const line = s.split("\n").find((l) => l.trim() !== "") ?? ""
  return line.length > 28 ? line.slice(0, 27) + "…" : line
}

function wrap(s: string, width: number): string[] {
  const out: string[] = []
  for (const raw of (s ?? "").split("\n")) {
    if (raw.length <= width) out.push(raw)
    else for (let i = 0; i < raw.length; i += width) out.push(raw.slice(i, i + width))
  }
  return out
}
