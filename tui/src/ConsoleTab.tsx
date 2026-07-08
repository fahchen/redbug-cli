/** @jsxImportSource @opentui/react */
import { useState } from "react"
import { useKeyboard, useRenderer } from "@opentui/react"
import type { StoreProxy } from "@musubi/react"

import { consoleRoot, dispatcher, useMusubiRoot, useMusubiSnapshot } from "./musubi"
import { editInEditor } from "./editor"
import { theme, PANEL_BORDER } from "./theme"
import { elixirStyle, tsClient } from "./treesitter"
import { Chip, HelpOverlay, Overlay, RootGate, StatusBar, TextField, useSpinner } from "./ui"
import { ConfirmOverlay } from "./ConfirmOverlay"
import { DialogSelect } from "./DialogSelect"

type ConsoleStore = StoreProxy<"Server.Stores.ConsoleRoot", Musubi.Stores>
type Exec = Server.Schema.ConsoleExec
type Snippet = Server.Schema.Snippet

type ExecStatus = "running" | "ok" | "error" | "stopped" | "timeout"

const STATUS_GLYPH: Record<ExecStatus, string> = {
  running: "⟳",
  ok: "✓",
  error: "✖",
  stopped: "⊘",
  timeout: "⧖"
}

function statusGlyph(status: string): string {
  return STATUS_GLYPH[status as ExecStatus] ?? "·"
}

function statusColor(status: string): string {
  switch (status as ExecStatus) {
    case "ok":
      return theme.success
    case "error":
    case "timeout":
      return theme.error
    case "running":
      return theme.warning
    default:
      return theme.textMuted
  }
}

export function ConsoleTab({
  nodeId,
  sessionId,
  nodeStatus,
  onSwitchToEvents,
  onBack
}: {
  nodeId: string
  sessionId: string
  nodeStatus: string
  onSwitchToEvents: () => void
  onBack: () => void
}) {
  const root = useMusubiRoot(consoleRoot(nodeId, sessionId))
  return (
    <RootGate root={root} loading="Loading console…" errorLabel="Console">
      {(store) => <ConsoleView store={store} nodeStatus={nodeStatus} onSwitchToEvents={onSwitchToEvents} onBack={onBack} />}
    </RootGate>
  )
}

type Modal =
  | { kind: "none" }
  | { kind: "help" }
  | { kind: "pickSnippet" }
  | { kind: "saveSnippet"; id: string }
  | { kind: "confirmStop"; id: string }
  | { kind: "confirmClear" }
  | { kind: "confirmDelete"; id: string }

function ConsoleView({
  store,
  nodeStatus,
  onSwitchToEvents,
  onBack
}: {
  store: ConsoleStore
  nodeStatus: string
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
  const runningCount = history.filter((e) => e.status === "running").length
  const nodeSpin = useSpinner(nodeStatus === "connecting", "braille")
  const leftBorderColor =
    nodeStatus === "error" ? theme.error
    : nodeStatus === "connecting" ? theme.warning
    : theme.borderActive

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
      // DialogSelect owns all keys
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

    if (modal.kind === "saveSnippet") {
      if (n === "escape") setModal({ kind: "none" })
      return
    }

    if (modal.kind === "confirmDelete") {
      if (n === "y") {
        dispatch("deleteExec", { id: modal.id })
        setModal({ kind: "none" })
      } else if (n === "n" || n === "escape") setModal({ kind: "none" })
      return
    }

    // [ / ] toggle between Events ⇄ Console tabs
    if (n === "[" || n === "]") {
      onSwitchToEvents()
      return
    }

    // ⌃L clears history (matches Events' ⌃L; keeps destructive clear off a bare key)
    if (key.ctrl && n === "l") {
      if (history.length > 0) setModal({ kind: "confirmClear" })
      return
    }

    if (key.ctrl && n === "d") {
      if (cur) dispatch("deleteExec", { id: cur.id })
      return
    }

    switch (n) {
      case "escape":
        onBack()
        break
      case "j":
      case "down":
        setSel((i) => (i + 1 >= history.length ? 0 : i + 1))
        break
      case "k":
      case "up":
        setSel((i) => (i <= 0 ? Math.max(0, history.length - 1) : i - 1))
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
      case "d":
        if (cur) setModal({ kind: "confirmDelete", id: cur.id })
        break
      case "s":
        if (cur) setModal({ kind: "saveSnippet", id: cur.id })
        break
      case "x":
        if (cur && cur.status === "running") setModal({ kind: "confirmStop", id: cur.id })
        break
      case "?":
        setModal({ kind: "help" })
        break
    }
  })

  return (
    <box flexDirection="column" flexGrow={1} backgroundColor={theme.background}>
      <box flexDirection="row" flexGrow={1} paddingTop={1}>
        <box
          border
          borderStyle={PANEL_BORDER}
          borderColor={leftBorderColor}
          title=" Console "
          titleColor={theme.primary}
          backgroundColor={theme.background}
          width={38}
          flexDirection="column"
          padding={1}
        >
          {history.length === 0 ? (
            <text fg={theme.textMuted}>No executions yet · n to run</text>
          ) : (
            <scrollbox scrollY stickyStart="top" flexGrow={1}>
              {history.map((e, i) => (
                <HistoryRow key={e.id} exec={e} active={i === sel} />
              ))}
            </scrollbox>
          )}
        </box>

        <ExecDetail exec={cur} />
      </box>

      <StatusBar
        statusText={
          nodeStatus === "connecting" ? `${nodeSpin} connecting…`
          : nodeStatus === "error" ? "✖ can't reach node"
          : `${history.length} runs${runningCount > 0 ? ` · ${runningCount} running` : ""}`
        }
        hints="j/k move · n compose · e edit+run · r run · v view · s save · d del · x stop · ⌃L clear · [/] tabs · ? help · esc back"
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
                ["s", "save as snippet"],
                ["d / ⌃D", "delete / delete (no confirm)"],
                ["x", "force-stop running execution"],
                ["⌃L", "clear history"]
              ]
            },
            {
              title: "tabs",
              lines: [
                ["[ / ]", "switch Events ⇄ Console"],
                ["esc", "back"]
              ]
            }
          ]}
        />
      )}

      {modal.kind === "pickSnippet" && (
        <DialogSelect
          title="New execution — start from"
          items={[
            { id: "_blank", name: "(blank)", query: "blank" },
            ...snippets.map((s) => ({ id: s.id, name: s.name, query: s.name }))
          ]}
          selectedIndex={pick}
          onSelect={(item) => {
            const i = item.id === "_blank" ? 0 : snippets.findIndex((s) => s.id === item.id) + 1
            const snip = i === 0 ? null : snippets[i - 1]
            setModal({ kind: "none" })
            composeAndRun(snip?.code ?? "", snip?.name ?? null)
          }}
          onClose={() => setModal({ kind: "none" })}
        />
      )}

      {modal.kind === "confirmStop" && (
        <ConfirmOverlay
          question="Force-stop (kill) this running execution?"
          hint="side effects already run cannot be undone · y = stop · n/Esc = no"
        />
      )}

      {modal.kind === "confirmClear" && (
        <ConfirmOverlay
          question="Clear the entire execution history?"
          hint="history is server-held, not just this view · y = yes · n/Esc = no"
        />
      )}

      {modal.kind === "saveSnippet" && (
        <Overlay>
          <TextField
            label="Save as snippet — name:"
            onSubmit={(v) => {
              const name = v.trim()
              if (name !== "") dispatch("saveAsSnippet", { exec_id: modal.id, name })
              setModal({ kind: "none" })
            }}
          />
        </Overlay>
      )}

      {modal.kind === "confirmDelete" && (
        <ConfirmOverlay question="Delete this execution?" />
      )}
    </box>
  )
}

function HistoryRow({ exec, active }: { exec: Exec; active: boolean }) {
  const bg = active ? theme.backgroundElement : theme.background
  const fg = active ? theme.text : theme.textMuted
  const glyph = statusGlyph(exec.status)
  const label = exec.name?.trim() ? exec.name : firstLine(exec.code)
  return (
    <box backgroundColor={bg} flexDirection="row" paddingLeft={1} paddingRight={1}>
      <text bg={bg} fg={statusColor(exec.status)}>{`${glyph} `}</text>
      <text bg={bg} fg={theme.textMuted}>{`${exec.ts} `}</text>
      <text bg={bg} fg={fg}>{label}</text>
    </box>
  )
}

function ExecDetail({ exec }: { exec: Exec | null }) {
  return (
    <box
      border
      borderStyle={PANEL_BORDER}
      borderColor={theme.borderSubtle}
      title=" Detail "
      titleColor={theme.textMuted}
      backgroundColor={theme.background}
      flexGrow={1}
      flexBasis={0}
      flexDirection="column"
      padding={1}
    >
      {exec === null ? (
        <text fg={theme.textMuted}>No execution selected · n to run</text>
      ) : (
        <ExecDetailBody exec={exec} />
      )}
    </box>
  )
}

function ExecDetailBody({ exec }: { exec: Exec }) {
  const dur = exec.duration_ms == null ? "—" : `${exec.duration_ms}ms`
  const code = exec.code.split("\n").slice(0, 12).join("\n")
  const errTone = exec.status === "error" || exec.status === "timeout"
  return (
    <>
      <box flexDirection="row" flexWrap="wrap">
        <Chip label="Status" value={`${statusGlyph(exec.status)} ${exec.status}`} tone={errTone ? "error" : "default"} />
        <Chip label="Duration" value={dur} />
        {exec.name?.trim() ? <Chip label="Name" value={exec.name} /> : null}
        <Chip label="Ts" value={exec.ts} />
      </box>
      <text fg={theme.textMuted} marginTop={1}>Code</text>
      <code content={code} filetype="elixir" syntaxStyle={elixirStyle} treeSitterClient={tsClient} />
      {exec.result?.trim() !== "" && (
        <>
          <text fg={theme.textMuted} marginTop={1}>Result</text>
          <code
            content={exec.result.split("\n").slice(0, 10).join("\n")}
            filetype="elixir"
            syntaxStyle={elixirStyle}
            treeSitterClient={tsClient}
          />
        </>
      )}
      {exec.output?.trim() !== "" && (
        <>
          <text fg={theme.textMuted} marginTop={1}>Stdout</text>
          {wrap(exec.output, 60).slice(0, 10).map((l, i) => (
            <text key={`o${i}`} fg={theme.textMuted}>{l}</text>
          ))}
        </>
      )}
      <text fg={theme.textMuted} marginTop={1}>v opens full code + output in $EDITOR</text>
    </>
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
