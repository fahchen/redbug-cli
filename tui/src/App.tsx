/** @jsxImportSource @opentui/react */
import { useState } from "react"
import type { ReactNode } from "react"
import { useKeyboard } from "@opentui/react"
import type { StoreProxy } from "@musubi/react"

import {
  NODES_ROOT,
  PRESETS_ROOT,
  SETTINGS_ROOT,
  useMusubiRoot,
  useMusubiSnapshot
} from "./musubi"
import { theme, setTheme } from "./theme"
import { SessionScreen } from "./SessionScreen"
import { PresetManager } from "./PresetManager"
import { SettingsScreen } from "./SettingsScreen"

declare const process: { exit(code?: number): never }

type NodesStore = StoreProxy<"Server.Stores.NodesRoot", Musubi.Stores>
type PresetsStore = StoreProxy<"Server.Stores.PresetsRoot", Musubi.Stores>
type SettingsStore = StoreProxy<"Server.Stores.SettingsRoot", Musubi.Stores>

type Node = Server.Schema.Node
type Session = Server.Schema.Session

type Screen =
  | { name: "tree" }
  | { name: "session"; nodeId: string; sessionId: string }
  | { name: "presets" }
  | { name: "settings" }

type Row =
  | { kind: "node"; node: Node }
  | { kind: "session"; node: Node; session: Session }

type Modal =
  | { kind: "none" }
  | { kind: "help" }
  | { kind: "newNodeName" }
  | { kind: "newNodeCookie"; name: string }
  | { kind: "editNodeName"; id: string; cookie: string; name: string }
  | { kind: "editNodeCookie"; id: string; name: string; cookie: string }
  | { kind: "newSessionName"; nodeId: string }
  | { kind: "newSessionPreset"; nodeId: string; name: string }
  | { kind: "confirm"; label: string; run: () => void }

export function App() {
  const nodes = useMusubiRoot(NODES_ROOT)
  const presets = useMusubiRoot(PRESETS_ROOT)
  const settings = useMusubiRoot(SETTINGS_ROOT)
  const [screen, setScreen] = useState<Screen>({ name: "tree" })

  if (nodes.status === "loading" || presets.status === "loading" || settings.status === "loading")
    return (
      <box backgroundColor={theme.bg} flexGrow={1} padding={1}>
        <text fg={theme.fg}>Connecting to BEAM…</text>
      </box>
    )
  const err =
    (nodes.status === "error" && nodes.error) ||
    (presets.status === "error" && presets.error) ||
    (settings.status === "error" && settings.error)
  if (err)
    return (
      <box backgroundColor={theme.bg} flexGrow={1} padding={1}>
        <text fg={theme.off}>{`Connect error: ${err.message}`}</text>
      </box>
    )

  return (
    <Router
      nodesStore={nodes.store}
      presetsStore={presets.store}
      settingsStore={settings.store}
      screen={screen}
      setScreen={setScreen}
    />
  )
}

function Router({
  nodesStore,
  presetsStore,
  settingsStore,
  screen,
  setScreen
}: {
  nodesStore: NodesStore
  presetsStore: PresetsStore
  settingsStore: SettingsStore
  screen: Screen
  setScreen: (s: Screen) => void
}) {
  const settingsSnap = useMusubiSnapshot(settingsStore)
  const settings = settingsSnap.settings as Server.Schema.Settings | undefined
  setTheme(settings?.theme ?? "dark")

  if (screen.name === "session")
    return (
      <SessionScreen
        nodeId={screen.nodeId}
        sessionId={screen.sessionId}
        settings={settings}
        onBack={() => setScreen({ name: "tree" })}
      />
    )

  if (screen.name === "presets")
    return <PresetManager onBack={() => setScreen({ name: "tree" })} />

  if (screen.name === "settings")
    return <SettingsScreen onBack={() => setScreen({ name: "tree" })} />

  return (
    <S1View
      nodesStore={nodesStore}
      presetsStore={presetsStore}
      onOpenSession={(nodeId, sessionId) => setScreen({ name: "session", nodeId, sessionId })}
      onOpenPresets={() => setScreen({ name: "presets" })}
      onOpenSettings={() => setScreen({ name: "settings" })}
    />
  )
}

function flatten(nodes: readonly Node[]): Row[] {
  const rows: Row[] = []
  for (const node of nodes) {
    rows.push({ kind: "node", node })
    for (const session of node.sessions)
      rows.push({ kind: "session", node, session })
  }
  return rows
}

function S1View({
  nodesStore,
  presetsStore,
  onOpenSession,
  onOpenPresets,
  onOpenSettings
}: {
  nodesStore: NodesStore
  presetsStore: PresetsStore
  onOpenSession: (nodeId: string, sessionId: string) => void
  onOpenPresets: () => void
  onOpenSettings: () => void
}) {
  const nodesSnap = useMusubiSnapshot(nodesStore)
  const presetsSnap = useMusubiSnapshot(presetsStore)

  const rows = flatten(nodesSnap.nodes ?? [])
  const [sel, setSel] = useState(0)
  const [modal, setModal] = useState<Modal>({ kind: "none" })
  const [presetIdx, setPresetIdx] = useState(0)

  const cur = rows[Math.min(sel, rows.length - 1)]
  const nodeContext = cur?.kind === "node" ? cur.node : cur?.session ? cur.node : null

  const dispatch = (name: Parameters<NodesStore["dispatchCommand"]>[0], payload: any) =>
    void nodesStore.dispatchCommand(name as any, payload).catch(() => {})

  // preset options for the new-session picker: "blank" + each preset
  const presetList = presetsSnap.presets ?? []

  useKeyboard((key) => {
    const name = key.name

    switch (modal.kind) {
      case "help":
        setModal({ kind: "none" })
        return

      case "confirm":
        if (name === "y") {
          modal.run()
          setModal({ kind: "none" })
        } else if (name === "n" || name === "escape") {
          setModal({ kind: "none" })
        }
        return

      case "newSessionPreset": {
        const max = presetList.length // index 0 = blank, 1..N = presets
        if (name === "j" || name === "down") setPresetIdx((i) => Math.min(i + 1, max))
        else if (name === "k" || name === "up") setPresetIdx((i) => Math.max(i - 1, 0))
        else if (name === "escape") setModal({ kind: "none" })
        else if (name === "return") {
          const fromPresetId = presetIdx === 0 ? null : presetList[presetIdx - 1].id
          dispatch("createSession", {
            node_id: modal.nodeId,
            name: modal.name,
            from_preset_id: fromPresetId
          })
          setModal({ kind: "none" })
        }
        return
      }

      // text-input modals: input handles typing + Enter (onSubmit); only Esc here
      case "newNodeName":
      case "newNodeCookie":
      case "editNodeName":
      case "editNodeCookie":
      case "newSessionName":
        if (name === "escape") setModal({ kind: "none" })
        return
    }

    // no modal: tree navigation
    switch (name) {
      case "return":
        if (cur?.kind === "session") onOpenSession(cur.node.id, cur.session.id)
        break
      case "j":
      case "down":
        setSel((i) => Math.min(i + 1, rows.length - 1))
        break
      case "k":
      case "up":
        setSel((i) => Math.max(i - 1, 0))
        break
      case "n":
        setModal({ kind: "newNodeName" })
        break
      case "s":
        if (nodeContext) {
          setPresetIdx(0)
          setModal({ kind: "newSessionName", nodeId: nodeContext.id })
        }
        break
      case "e":
        if (nodeContext)
          setModal({
            kind: "editNodeName",
            id: nodeContext.id,
            name: nodeContext.name,
            cookie: nodeContext.cookie
          })
        break
      case "c":
        if (nodeContext)
          dispatch(nodeContext.connected ? "disconnect" : "connect", {
            node_id: nodeContext.id
          })
        break
      case "d":
        if (cur?.kind === "node")
          setModal({
            kind: "confirm",
            label: `Delete node "${cur.node.name}" and all its sessions?`,
            run: () => dispatch("deleteNode", { id: cur.node.id })
          })
        else if (cur?.kind === "session")
          setModal({
            kind: "confirm",
            label: `Delete session "${cur.session.name}"?`,
            run: () =>
              dispatch("deleteSession", {
                node_id: cur.node.id,
                session_id: cur.session.id
              })
          })
        break
      case "p":
        onOpenPresets()
        break
      case ",":
        onOpenSettings()
        break
      case "?":
        setModal({ kind: "help" })
        break
      case "q":
        process.exit(0)
    }
  })

  return (
    <box flexDirection="column" flexGrow={1} backgroundColor={theme.bg}>
      <box
        border
        borderColor={theme.border}
        backgroundColor={theme.bg}
        title="redbug · nodes ▸ sessions"
        titleColor={theme.title}
        flexGrow={1}
        flexDirection="column"
        padding={1}
      >
        {rows.length === 0 ? (
          <text fg={theme.dim}>No nodes. Press n to add one.</text>
        ) : (
          rows.map((row, i) => <TreeRow key={rowKey(row)} row={row} active={i === sel} />)
        )}
      </box>

      <box backgroundColor={theme.bg} paddingLeft={1}>
        <text fg={theme.dim}>
          j/k · enter open · n node · s session · e edit · c connect · d delete · p presets · , settings · ? help · q quit
        </text>
      </box>

      {modal.kind !== "none" && (
        <ModalLayer
          modal={modal}
          presetList={presetList}
          presetIdx={presetIdx}
          onCommit={(m, payload) => {
            switch (m) {
              case "newNodeName":
                setModal({ kind: "newNodeCookie", name: payload })
                break
              case "newNodeCookie":
                dispatch("createNode", { name: (modal as any).name, cookie: payload })
                setModal({ kind: "none" })
                break
              case "editNodeName":
                setModal({
                  kind: "editNodeCookie",
                  id: (modal as any).id,
                  name: payload,
                  cookie: (modal as any).cookie
                })
                break
              case "editNodeCookie":
                dispatch("editNode", {
                  id: (modal as any).id,
                  name: (modal as any).name,
                  cookie: payload
                })
                setModal({ kind: "none" })
                break
              case "newSessionName":
                setModal({ kind: "newSessionPreset", nodeId: (modal as any).nodeId, name: payload })
                break
            }
          }}
        />
      )}
    </box>
  )
}

function rowKey(row: Row): string {
  return row.kind === "node" ? `n:${row.node.id}` : `s:${row.session.id}`
}

function TreeRow({ row, active }: { row: Row; active: boolean }) {
  const bg = active ? theme.selBg : theme.bg
  const fg = active ? theme.selFg : theme.fg

  if (row.kind === "node") {
    const n = row.node
    const dot = n.connected ? "●" : "○"
    const dotColor = n.connected ? theme.on : theme.off
    return (
      <box backgroundColor={bg} flexDirection="row">
        <text bg={bg} fg={dotColor}>{`${dot} `}</text>
        <text bg={bg} fg={fg}>{n.name}</text>
        <text bg={bg} fg={theme.dim}>{`  (${n.sessions.length})`}</text>
      </box>
    )
  }

  const s = row.session
  return (
    <box backgroundColor={bg} flexDirection="row">
      <text bg={bg} fg={theme.dim}>{"    • "}</text>
      <text bg={bg} fg={fg}>{s.name}</text>
      <text bg={bg} fg={theme.dim}>{`  [${s.status}]`}</text>
    </box>
  )
}

function ModalLayer({
  modal,
  presetList,
  presetIdx,
  onCommit
}: {
  modal: Modal
  presetList: readonly Server.Schema.Preset[]
  presetIdx: number
  onCommit: (kind: Modal["kind"], value: string) => void
}) {
  const box = (children: ReactNode) => (
    <box
      border
      borderColor={theme.title}
      backgroundColor={theme.overlay}
      flexDirection="column"
      padding={1}
      marginLeft={2}
      marginRight={2}
    >
      {children}
    </box>
  )

  switch (modal.kind) {
    case "help":
      return box(
        <>
          <text fg={theme.title}>redbug · help</text>
          <text fg={theme.dim}>kinds: ↓ call (cyan) · ↑ retn (green) · → send (yellow) · ← recv (purple)</text>
          <text fg={theme.title}>Tree (S1)</text>
          <text fg={theme.fg}>j/k move · enter open session · n node · s session</text>
          <text fg={theme.fg}>e edit node · c connect/disconnect · d delete</text>
          <text fg={theme.fg}>p presets · , settings · q quit</text>
          <text fg={theme.title}>Session (S2/S3)</text>
          <text fg={theme.fg}>enter detail · o sort · / filter · g group · z zoom</text>
          <text fg={theme.fg}>E $EDITOR · e traces · Shift+S/X start/stop</text>
          <text fg={theme.fg}>Ctrl+S apply · Ctrl+L clear · Ctrl+W save preset</text>
          <text fg={theme.title}>Presets (S4) / Settings (S6)</text>
          <text fg={theme.fg}>j/k move · enter/tab edit · space toggle · esc back</text>
          <text fg={theme.dim}>press any key to close</text>
        </>
      )

    case "newNodeName":
      return box(
        <TextField
          key="newNodeName"
          label="New node — name:"
          hint="format: name@host (longname), e.g. myapp@127.0.0.1"
          onSubmit={(v) => onCommit("newNodeName", v)}
        />
      )

    case "newNodeCookie":
      return box(
        <TextField
          key="newNodeCookie"
          label={`New node "${modal.name}" — cookie:`}
          hint="Erlang distribution cookie; must match the target node"
          onSubmit={(v) => onCommit("newNodeCookie", v)}
        />
      )

    case "editNodeName":
      return box(
        <TextField
          key="editNodeName"
          label="Edit node — name:"
          hint="format: name@host (longname), e.g. myapp@127.0.0.1"
          initial={modal.name}
          onSubmit={(v) => onCommit("editNodeName", v)}
        />
      )

    case "editNodeCookie":
      return box(
        <TextField
          key="editNodeCookie"
          label="Edit node — cookie:"
          hint="Erlang distribution cookie; must match the target node"
          initial={modal.cookie}
          onSubmit={(v) => onCommit("editNodeCookie", v)}
        />
      )

    case "newSessionName":
      return box(
        <TextField
          key="newSessionName"
          label="New session — name:"
          hint="a label for this trace session"
          onSubmit={(v) => onCommit("newSessionName", v)}
        />
      )

    case "newSessionPreset":
      return box(
        <>
          <text fg={theme.title}>{`Session "${modal.name}" — init from:`}</text>
          <PickRow label="(blank)" active={presetIdx === 0} />
          {presetList.map((p, i) => (
            <PickRow key={p.id} label={p.name} active={presetIdx === i + 1} />
          ))}
          <text fg={theme.dim}>j/k move · Enter create · Esc cancel</text>
        </>
      )

    case "confirm":
      return box(
        <>
          <text fg={theme.fg}>{modal.label}</text>
          <text fg={theme.dim}>y = yes · n/Esc = no</text>
        </>
      )

    default:
      return null
  }
}

function PickRow({ label, active }: { label: string; active: boolean }) {
  const bg = active ? theme.selBg : theme.overlay
  const fg = active ? theme.selFg : theme.fg
  return (
    <box backgroundColor={bg}>
      <text bg={bg} fg={fg}>{`${active ? "›" : " "} ${label}`}</text>
    </box>
  )
}

function TextField({
  label,
  initial,
  hint,
  onSubmit
}: {
  label: string
  initial?: string
  hint?: string
  onSubmit: (value: string) => void
}) {
  const [value, setValue] = useState(initial ?? "")
  return (
    <>
      <text fg={theme.title}>{label}</text>
      {hint && <text fg={theme.dim}>{hint}</text>}
      <input
        focused
        value={value}
        onInput={(v: string) => setValue(v)}
        onSubmit={() => onSubmit(value)}
        backgroundColor={theme.bg}
        textColor={theme.fg}
      />
      <text fg={theme.dim}>Enter ok · Esc cancel</text>
    </>
  )
}
