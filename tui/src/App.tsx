/** @jsxImportSource @opentui/react */
import { useState } from "react"
import type { ReactNode } from "react"
import { useKeyboard } from "@opentui/react"
import type { StoreProxy } from "@musubi/react"

import {
  NODES_ROOT,
  PRESETS_ROOT,
  SETTINGS_ROOT,
  dispatcher,
  useMusubiRoot,
  useMusubiSnapshot
} from "./musubi"
import { theme, setTheme } from "./theme"
import { Flash, Header, HelpOverlay, HintProvider, Notice, Overlay, PickRow, StatusBar, TextField } from "./ui"
import { SessionScreen } from "./SessionScreen"
import { PresetManager } from "./PresetManager"
import { SnippetManager } from "./SnippetManager"
import { SettingsOverlay } from "./SettingsScreen"

declare const process: { exit(code?: number): never }

type NodesStore = StoreProxy<"Server.Stores.NodesRoot", Musubi.Stores>
type PresetsStore = StoreProxy<"Server.Stores.PresetsRoot", Musubi.Stores>
type SettingsStore = StoreProxy<"Server.Stores.SettingsRoot", Musubi.Stores>

type NodeProxy = StoreProxy<"Server.Stores.NodeStore", Musubi.Stores>

type Node = Server.Schema.Node
type Session = Server.Schema.Session

type Screen =
  | { name: "tree" }
  | { name: "session"; nodeId: string; sessionId: string }
  | { name: "presets" }
  | { name: "snippets" }

type Modal =
  | { kind: "none" }
  | { kind: "help" }
  | { kind: "settings" }
  | { kind: "newNode" }
  | { kind: "editNode"; id: string }
  | { kind: "newSessionName"; nodeId: string }
  | { kind: "newSessionPreset"; nodeId: string; name: string }
  | { kind: "confirm"; label: string; run: () => void }

export function App() {
  const nodes = useMusubiRoot(NODES_ROOT)
  const presets = useMusubiRoot(PRESETS_ROOT)
  const settings = useMusubiRoot(SETTINGS_ROOT)
  const [screen, setScreen] = useState<Screen>({ name: "tree" })

  if (nodes.status === "loading" || presets.status === "loading" || settings.status === "loading")
    return <Notice text="Connecting to BEAM…" />
  const err =
    (nodes.status === "error" && nodes.error) ||
    (presets.status === "error" && presets.error) ||
    (settings.status === "error" && settings.error)
  // The root socket carries all state, so a drop leaves nothing to interact
  // with — keep a full-screen notice, but signal that musubi keeps retrying so
  // it doesn't read as a dead end.
  if (err) return <Notice tone="error" text={`Lost connection to BEAM — retrying…  (${err.message})`} />

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
  const settings = settingsSnap?.settings as Server.Schema.Settings | undefined
  setTheme(settings?.theme ?? "dark")

  return (
    <HintProvider show={settings?.show_hints ?? true}>
      {renderScreen()}
    </HintProvider>
  )

  function renderScreen(): ReactNode {
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

    if (screen.name === "snippets")
      return <SnippetManager onBack={() => setScreen({ name: "tree" })} />

    return (
      <S1View
        nodesStore={nodesStore}
        presetsStore={presetsStore}
        onOpenSession={(nodeId, sessionId) => setScreen({ name: "session", nodeId, sessionId })}
        onOpenPresets={() => setScreen({ name: "presets" })}
        onOpenSnippets={() => setScreen({ name: "snippets" })}
      />
    )
  }
}

type Focus = "nodes" | "sessions"

function S1View({
  nodesStore,
  presetsStore,
  onOpenSession,
  onOpenPresets,
  onOpenSnippets
}: {
  nodesStore: NodesStore
  presetsStore: PresetsStore
  onOpenSession: (nodeId: string, sessionId: string) => void
  onOpenPresets: () => void
  onOpenSnippets: () => void
}) {
  const nodesSnap = useMusubiSnapshot(nodesStore)
  const presetsSnap = useMusubiSnapshot(presetsStore)

  const nodeList = nodesSnap?.nodes ?? []
  // env mode is mutually exclusive: if any node is env-injected, all are, and the
  // node list is read-only (only new sessions allowed under them).
  const envMode = nodeList.some((n) => n.source === "env")
  const connCount = nodeList.filter((n) => n.connected).length

  const [nodeSel, setNodeSel] = useState(0)
  const [sessSel, setSessSel] = useState(0)
  const [focus, setFocus] = useState<Focus>("nodes")
  const [modal, setModal] = useState<Modal>({ kind: "none" })
  const [presetIdx, setPresetIdx] = useState(0)
  const [nameDraft, setNameDraft] = useState("")
  const [cookieDraft, setCookieDraft] = useState("")
  const [sshHostDraft, setSshHostDraft] = useState("")
  const [sshUserDraft, setSshUserDraft] = useState("")
  const [containerDraft, setContainerDraft] = useState("")
  const [nodeField, setNodeField] = useState(0)
  const NODE_FIELDS = 5

  const nodeIdx = Math.min(nodeSel, Math.max(0, nodeList.length - 1))
  const node = nodeList[nodeIdx] ?? null
  const nodeProxy = node ? nodesStore.nodes[nodeIdx] : undefined
  const sessions = node?.sessions ?? []
  const sessIdx = Math.min(sessSel, Math.max(0, sessions.length - 1))
  const session = sessions[sessIdx] ?? null
  const sessionProxy = node && session ? nodeProxy!.sessions[sessIdx] : undefined

  // `error` lives on the NodeStore child state (node-scoped); `Node` is aliased
  // to Schema.Node which omits it, so reach it via intersection.
  const nodeError =
    (node as (Node & { error?: Server.Schema.AppError | null }) | null)?.error ?? null

  // createNode is the only root command; node/session mutations dispatch on the
  // matching child proxy (the store path is the routing — no ids in payload).
  const createNode = dispatcher(nodesStore)
  const nodeProxyById = (id: string): NodeProxy | undefined => {
    const i = nodeList.findIndex((n) => n.id === id)
    return i >= 0 ? nodesStore.nodes[i] : undefined
  }

  // preset options for the new-session picker: "blank" + each preset
  const presetList = presetsSnap?.presets ?? []

  const openNewNode = () => {
    if (envMode) return
    setNameDraft("")
    setCookieDraft("")
    setSshHostDraft("")
    setSshUserDraft("")
    setContainerDraft("")
    setNodeField(0)
    setModal({ kind: "newNode" })
  }

  useKeyboard((key) => {
    const name = key.name

    switch (modal.kind) {
      case "help":
        setModal({ kind: "none" })
        return

      case "settings":
        // SettingsOverlay owns its own keyboard handling while open.
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
          const np = nodeProxyById(modal.nodeId)
          if (np)
            dispatcher(np)("createSession", { name: modal.name, from_preset_id: fromPresetId })
          setModal({ kind: "none" })
        }
        return
      }

      case "newNode":
      case "editNode":
        if (name === "escape") setModal({ kind: "none" })
        else if (name === "tab") setNodeField((f) => (f + 1) % NODE_FIELDS)
        else if (name === "return") {
          if (nameDraft.trim() !== "" && cookieDraft.trim() !== "") {
            const payload = {
              name: nameDraft,
              cookie: cookieDraft,
              ssh_host: sshHostDraft,
              ssh_user: sshUserDraft,
              container: containerDraft
            }
            if (modal.kind === "newNode") createNode("createNode", payload)
            else {
              const np = nodeProxyById(modal.id)
              if (np) dispatcher(np)("editNode", payload)
            }
            setModal({ kind: "none" })
          }
        }
        return

      // text-input modal: input handles typing + Enter (onSubmit); only Esc here
      case "newSessionName":
        if (name === "escape") setModal({ kind: "none" })
        return
    }

    // no modal — two-pane navigation
    const newSession = () => {
      if (node) {
        setPresetIdx(0)
        setModal({ kind: "newSessionName", nodeId: node.id })
      }
    }

    if (focus === "sessions") {
      switch (name) {
        case "escape":
        case "tab":
        case "left":
        case "h":
          setFocus("nodes")
          break
        case "j":
        case "down":
          setSessSel((i) => Math.min(i + 1, sessions.length - 1))
          break
        case "k":
        case "up":
          setSessSel((i) => Math.max(i - 1, 0))
          break
        case "return":
          if (node && session) onOpenSession(node.id, session.id)
          break
        case "s":
          newSession()
          break
        case "d":
          if (node && session) {
            const proxy = sessionProxy
            setModal({
              kind: "confirm",
              label: `Delete session "${session.name}"?`,
              run: () => proxy && dispatcher(proxy)("deleteSession")
            })
          }
          break
        case "?":
          setModal({ kind: "help" })
          break
      }
      return
    }

    // focus === "nodes"
    switch (name) {
      case "j":
      case "down":
        setNodeSel((i) => Math.min(i + 1, nodeList.length - 1))
        setSessSel(0)
        break
      case "k":
      case "up":
        setNodeSel((i) => Math.max(i - 1, 0))
        setSessSel(0)
        break
      case "return":
      case "tab":
      case "right":
        if (node && sessions.length > 0) {
          setSessSel(0)
          setFocus("sessions")
        }
        break
      case "n":
        openNewNode()
        break
      case "s":
        newSession()
        break
      case "e":
        // env nodes are read-only
        if (node && node.source !== "env") {
          setNameDraft(node.name)
          setCookieDraft(node.cookie)
          setSshHostDraft(node.ssh_host ?? "")
          setSshUserDraft(node.ssh_user ?? "")
          setContainerDraft(node.container ?? "")
          setNodeField(0)
          setModal({ kind: "editNode", id: node.id })
        }
        break
      case "c":
        if (node && nodeProxy)
          dispatcher(nodeProxy)(node.connected ? "disconnect" : "connect")
        break
      case "d":
        if (node && node.source !== "env" && nodeProxy) {
          const proxy = nodeProxy
          setModal({
            kind: "confirm",
            label: `Delete node "${node.name}" and all its sessions?`,
            run: () => dispatcher(proxy)("deleteNode")
          })
        }
        break
      case "p":
        onOpenPresets()
        break
      case "l":
        onOpenSnippets()
        break
      case ",":
        setModal({ kind: "settings" })
        break
      case "?":
        setModal({ kind: "help" })
        break
      case "q":
        setModal({
          kind: "confirm",
          label: "Quit redbug?",
          run: () => process.exit(0)
        })
        break
    }
  })

  return (
    <box flexDirection="column" flexGrow={1} backgroundColor={theme.bg}>
      <Header title="redbug · nodes ▸ sessions" />

      <box flexDirection="row" flexGrow={1} gap={1}>
        <box
          border
          borderColor={focus === "nodes" ? theme.title : theme.border}
          backgroundColor={theme.bg}
          title={`Nodes (${nodeList.length})`}
          titleColor={theme.title}
          width={38}
          flexDirection="column"
          padding={1}
        >
          {nodeList.length === 0 ? (
            <EmptyTree />
          ) : (
            nodeList.map((n, i) => (
              <NodeRow key={n.id} node={n} active={i === nodeIdx} />
            ))
          )}
        </box>

        <box
          border
          borderColor={focus === "sessions" ? theme.title : theme.border}
          backgroundColor={theme.bg}
          title={node ? `${node.name} — sessions` : "—"}
          titleColor={theme.title}
          flexGrow={1}
          flexBasis={0}
          flexDirection="column"
          padding={1}
        >
          {!node ? (
            <text fg={theme.dim}>Select a node</text>
          ) : sessions.length === 0 ? (
            <text fg={theme.dim}>No sessions · s to add</text>
          ) : (
            sessions.map((s, i) => (
              <SessionRow key={s.id} session={s} active={focus === "sessions" && i === sessIdx} />
            ))
          )}
        </box>
      </box>

      {nodeError && <Flash error={nodeError} hint="c retry" />}

      <StatusBar
        statusText={`${connCount}/${nodeList.length} connected`}
        hints={
          focus === "nodes"
            ? envMode
              ? "j/k node · enter sessions · s session · c connect · env read-only · , settings · ? help · q quit"
              : "j/k node · enter sessions · n new · c connect · e edit · d del · p presets · , settings · ? help · q quit"
            : "j/k session · enter open · s new · d del · tab/esc nodes · ? help"
        }
      />

      {modal.kind === "settings" && (
        <SettingsOverlay onClose={() => setModal({ kind: "none" })} />
      )}

      {modal.kind !== "none" && modal.kind !== "settings" && (
        <ModalLayer
          modal={modal}
          presetList={presetList}
          presetIdx={presetIdx}
          nameDraft={nameDraft}
          cookieDraft={cookieDraft}
          sshHostDraft={sshHostDraft}
          sshUserDraft={sshUserDraft}
          containerDraft={containerDraft}
          nodeField={nodeField}
          onName={setNameDraft}
          onCookie={setCookieDraft}
          onSshHost={setSshHostDraft}
          onSshUser={setSshUserDraft}
          onContainer={setContainerDraft}
          onCommit={(m, payload) => {
            if (m === "newSessionName")
              setModal({ kind: "newSessionPreset", nodeId: (modal as any).nodeId, name: payload })
          }}
        />
      )}
    </box>
  )
}

// First-run: instead of a bare "nothing here", teach the domain model in a
// glance so the empty screen is the shortest path to understanding what to add.
function EmptyTree() {
  return (
    <box flexDirection="column">
      <text fg={theme.fg}>No nodes yet</text>
      <text fg={theme.dim} marginTop={1}>Node ▸ Session ▸ Trace</text>
      <text fg={theme.dim}>{"                └ → Events"}</text>
      <text fg={theme.dim} marginTop={1}>a target, a run, a pattern,</text>
      <text fg={theme.dim}>the calls it catches, live.</text>
      <box flexDirection="row" marginTop={1}>
        <text fg={theme.accent}>n</text>
        <text fg={theme.dim}>{"  add your first node"}</text>
      </box>
    </box>
  )
}

function NodeRow({ node, active }: { node: Node; active: boolean }) {
  const bg = active ? theme.selBg : theme.bg
  const fg = active ? theme.selFg : theme.fg
  const dot = node.connected ? "●" : "○"
  const dotColor = node.connected ? theme.on : theme.off
  return (
    <box backgroundColor={bg} flexDirection="row">
      <text bg={bg} fg={dotColor}>{`${dot} `}</text>
      <text bg={bg} fg={fg}>{node.name}</text>
      <text bg={bg} fg={theme.dim}>{`  (${node.sessions.length})`}</text>
      {node.source === "env" && <text bg={bg} fg={theme.dim}>{"  env"}</text>}
    </box>
  )
}

function SessionRow({ session, active }: { session: Session; active: boolean }) {
  const bg = active ? theme.selBg : theme.bg
  const fg = active ? theme.selFg : theme.fg
  return (
    <box backgroundColor={bg} flexDirection="row">
      <text bg={bg} fg={theme.dim}>{"• "}</text>
      <text bg={bg} fg={fg}>{session.name}</text>
      <text bg={bg} fg={theme.dim}>{`  [${session.status}]`}</text>
    </box>
  )
}

function ModalLayer({
  modal,
  presetList,
  presetIdx,
  nameDraft,
  cookieDraft,
  sshHostDraft,
  sshUserDraft,
  containerDraft,
  nodeField,
  onName,
  onCookie,
  onSshHost,
  onSshUser,
  onContainer,
  onCommit
}: {
  modal: Modal
  presetList: readonly Server.Schema.Preset[]
  presetIdx: number
  nameDraft: string
  cookieDraft: string
  sshHostDraft: string
  sshUserDraft: string
  containerDraft: string
  nodeField: number
  onName: (v: string) => void
  onCookie: (v: string) => void
  onSshHost: (v: string) => void
  onSshUser: (v: string) => void
  onContainer: (v: string) => void
  onCommit: (kind: Modal["kind"], value: string) => void
}) {
  const box = (title: string, children: ReactNode) => (
    <Overlay title={title}>{children}</Overlay>
  )

  switch (modal.kind) {
    case "help":
      return (
        <HelpOverlay
          title="redbug · nodes ▸ sessions"
          sections={[
            {
              lines: [
                ["j / k", "move"],
                ["enter", "sessions / open"],
                ["n", "new node"],
                ["s", "new session"],
                ["e", "edit node"],
                ["c", "connect / disconnect"],
                ["d", "delete"]
              ]
            },
            {
              title: "go to",
              lines: [
                ["p", "presets"],
                ["l", "snippet library"],
                [",", "settings"],
                ["q", "quit"]
              ]
            }
          ]}
        />
      )

    case "newNode":
    case "editNode":
      return box(
        modal.kind === "newNode" ? "New node" : "Edit node",
        <>
          <Field
            label="name"
            hint="name@host (longname), e.g. myapp@127.0.0.1"
            value={nameDraft}
            onInput={onName}
            focused={nodeField === 0}
          />
          <Field
            label="cookie"
            hint="Erlang distribution cookie; must match the target"
            value={cookieDraft}
            onInput={onCookie}
            focused={nodeField === 1}
          />
          <text fg={theme.dim} marginTop={1}>over SSH (optional — leave blank to dial directly)</text>
          <Field
            label="ssh host"
            hint="the server to SSH into, e.g. prod-1.example.com"
            value={sshHostDraft}
            onInput={onSshHost}
            focused={nodeField === 2}
          />
          <Field
            label="ssh user"
            hint="SSH login user (defaults to $USER)"
            value={sshUserDraft}
            onInput={onSshUser}
            focused={nodeField === 3}
          />
          <Field
            label="container"
            hint="Kamal service / container name on the host"
            value={containerDraft}
            onInput={onContainer}
            focused={nodeField === 4}
          />
          <text fg={theme.dim} marginTop={1}>Tab switch field · Enter save · Esc cancel</text>
        </>
      )

    case "newSessionName":
      return box(
        "New session",
        <TextField
          key="newSessionName"
          label="name"
          hint="a label for this trace session"
          onSubmit={(v) => onCommit("newSessionName", v)}
        />
      )

    case "newSessionPreset":
      return box(
        `Session "${modal.name}" — init from`,
        <>
          <PickRow label="(blank)" active={presetIdx === 0} />
          {presetList.map((p, i) => (
            <PickRow key={p.id} label={p.name} active={presetIdx === i + 1} />
          ))}
          <text fg={theme.dim} marginTop={1}>j/k move · Enter create · Esc cancel</text>
        </>
      )

    case "confirm":
      return box(
        "Confirm",
        <>
          <text fg={theme.fg}>{modal.label}</text>
          <text fg={theme.dim} marginTop={1}>y = yes · n/Esc = no</text>
        </>
      )

    default:
      return null
  }
}

function Field({
  label,
  hint,
  value,
  onInput,
  focused
}: {
  label: string
  hint?: string
  value: string
  onInput: (v: string) => void
  focused: boolean
}) {
  return (
    <box flexDirection="column" marginBottom={1}>
      <text fg={focused ? theme.title : theme.dim}>{`${focused ? "› " : "  "}${label}`}</text>
      {hint && <text fg={theme.dim}>{`  ${hint}`}</text>}
      <input
        focused={focused}
        value={value}
        onInput={onInput}
        backgroundColor={theme.bg}
        textColor={theme.fg}
        focusedBackgroundColor={theme.selBg}
        focusedTextColor={theme.selFg}
      />
    </box>
  )
}
