/** @jsxImportSource @opentui/react */
import { useRef, useState } from "react"
import type { ReactNode } from "react"
import { useKeyboard, useTerminalDimensions } from "@opentui/react"
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
import { Chip, HelpOverlay, HintProvider, Notice, Overlay, Panel, StatusBar, TextField, truncate, useSpinner } from "./ui"
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
  const { width: termWidth } = useTerminalDimensions()
  // session name column width: total minus the nodes pane (40) and the frame /
  // padding / number-column chrome around the name. Truncated with an ellipsis.
  const sessNameWidth = Math.max(8, termWidth - 40 - 12)

  const nodeList = nodesSnap?.nodes ?? []
  // env mode is mutually exclusive: if any node is env-injected, all are, and the
  // node list is read-only (only new sessions allowed under them).
  const envMode = nodeList.some((n) => n.source === "env")
  const connCount = nodeList.filter((n) => n.status === "connected").length

  const [nodeSel, setNodeSel] = useState(0)
  const [sessSel, setSessSel] = useState(0)
  // number-nav for the session list: accumulate typed digits (so 10+ is
  // reachable), jump to that 1-based session, reset the buffer after a pause.
  const sessNumBuf = useRef("")
  const sessNumTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const [focus, setFocus] = useState<Focus>("nodes")
  const [modal, setModal] = useState<Modal>({ kind: "none" })
  const [presetIdx, setPresetIdx] = useState(0)
  const [nameDraft, setNameDraft] = useState("")
  const [hostDraft, setHostDraft] = useState("")
  const [portDraft, setPortDraft] = useState("")
  const [cookieDraft, setCookieDraft] = useState("")
  const [sshHostDraft, setSshHostDraft] = useState("")
  const [sshPortDraft, setSshPortDraft] = useState("")
  const [sshUserDraft, setSshUserDraft] = useState("")
  const [containerDraft, setContainerDraft] = useState("")
  const [nodeField, setNodeField] = useState(0)
  const NODE_FIELDS = 8

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

  // commit the new-session picker at a chosen index (0 = blank, 1..N = presets)
  const commitPreset = (index: number) => {
    if (modal.kind !== "newSessionPreset") return
    const fromPresetId = index === 0 ? null : presetList[index - 1]?.id ?? null
    const np = nodeProxyById(modal.nodeId)
    if (np) dispatcher(np)("createSession", { name: modal.name, from_preset_id: fromPresetId })
    setModal({ kind: "none" })
  }

  const openNewNode = () => {
    if (envMode) return
    setNameDraft("")
    setHostDraft("")
    setPortDraft("")
    setCookieDraft("")
    setSshHostDraft("")
    setSshPortDraft("")
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

      case "newSessionPreset":
        // <select> owns j/k/return; only Esc closes the overlay
        if (name === "escape") setModal({ kind: "none" })
        return

      case "newNode":
      case "editNode":
        if (name === "escape") setModal({ kind: "none" })
        else if (name === "tab") setNodeField((f) => (f + 1) % NODE_FIELDS)
        else if (name === "return") {
          // ssh nodes auto-discover their name + cookie, so only require those
          // two for a directly-dialed node.
          const ok =
            sshHostDraft.trim() !== "" ||
            (nameDraft.trim() !== "" && cookieDraft.trim() !== "")
          if (ok) {
            // the Erlang node name is name@host; recombine the split fields.
            const fullName =
              hostDraft.trim() !== "" ? `${nameDraft.trim()}@${hostDraft.trim()}` : nameDraft
            const payload = {
              name: fullName,
              cookie: cookieDraft,
              port: portDraft,
              ssh_host: sshHostDraft,
              ssh_port: sshPortDraft,
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
          // wrap up past the first item to the last
          setSessSel((i) => (i <= 0 ? Math.max(0, sessions.length - 1) : i - 1))
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
        default:
          // digit → jump to that 1-based session; accumulate for 10+, clamp to last
          if (/^[0-9]$/.test(name) && sessions.length > 0) {
            if (sessNumTimer.current) clearTimeout(sessNumTimer.current)
            sessNumBuf.current += name
            const n = parseInt(sessNumBuf.current, 10)
            setSessSel(Math.min(Math.max(n - 1, 0), sessions.length - 1))
            sessNumTimer.current = setTimeout(() => {
              sessNumBuf.current = ""
            }, 800)
          }
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
          // node.name is name@host; split back into the two form fields.
          const at = node.name.indexOf("@")
          setNameDraft(at >= 0 ? node.name.slice(0, at) : node.name)
          setHostDraft(at >= 0 ? node.name.slice(at + 1) : "")
          setPortDraft(node.port ?? "")
          setCookieDraft(node.cookie)
          setSshHostDraft(node.ssh_host ?? "")
          setSshPortDraft(node.ssh_port ?? "")
          setSshUserDraft(node.ssh_user ?? "")
          setContainerDraft(node.container ?? "")
          setNodeField(0)
          setModal({ kind: "editNode", id: node.id })
        }
        break
      case "c":
        // connected → disconnect; anything else (idle/connecting/error) →
        // (re)connect. request_connect resets the retry counter, so `c` doubles
        // as the manual retry after a failed connect.
        if (node && nodeProxy)
          dispatcher(nodeProxy)(node.status === "connected" ? "disconnect" : "connect")
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
    <box flexDirection="column" flexGrow={1} backgroundColor={theme.background}>
      <box flexDirection="row" flexGrow={1} paddingTop={1}>
        <Panel heading="nodes" active={focus === "nodes"} width={40}>
          {nodeList.length === 0 ? (
            <EmptyTree />
          ) : (
            nodeList.map((n, i) => (
              <NodeRow key={n.id} node={n} active={i === nodeIdx} />
            ))
          )}
        </Panel>

        <Panel heading={node ? node.name : "—"} active={focus === "sessions"} grow>
          {node && <NodeDetailBand node={node} error={nodeError} />}
          {!node ? (
            <text fg={theme.textMuted}>Select a node</text>
          ) : sessions.length === 0 ? (
            <text fg={theme.textMuted}>No sessions · s to add</text>
          ) : (
            sessions.map((s, i) => (
              <SessionRow key={s.id} session={s} index={i + 1} nameWidth={sessNameWidth} active={focus === "sessions" && i === sessIdx} />
            ))
          )}
        </Panel>
      </box>

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
          hostDraft={hostDraft}
          portDraft={portDraft}
          cookieDraft={cookieDraft}
          sshHostDraft={sshHostDraft}
          sshPortDraft={sshPortDraft}
          sshUserDraft={sshUserDraft}
          containerDraft={containerDraft}
          nodeField={nodeField}
          onName={setNameDraft}
          onHost={setHostDraft}
          onPort={setPortDraft}
          onCookie={setCookieDraft}
          onSshHost={setSshHostDraft}
          onSshPort={setSshPortDraft}
          onSshUser={setSshUserDraft}
          onContainer={setContainerDraft}
          onPresetChange={setPresetIdx}
          onPickPreset={commitPreset}
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
  const bg = active ? theme.backgroundElement : theme.background
  // color-weight: connected node reads bright, others muted. A small status dot
  // carries the state; a braille spinner while connecting.
  const spin = useSpinner(node.status === "connecting", "braille")
  // only surface exceptions: idle nodes get no glyph (just alignment space);
  // connected/connecting/error carry a colored dot.
  const dot =
    node.status === "connected" ? "●"
    : node.status === "connecting" ? spin
    : node.status === "error" ? "✖"
    : " "
  const dotColor =
    node.status === "connected" ? theme.success
    : node.status === "connecting" ? theme.warning
    : node.status === "error" ? theme.error
    : theme.textMuted
  const nameColor = active || node.status === "connected" ? theme.text : theme.textMuted
  return (
    <box backgroundColor={bg} flexDirection="row" paddingLeft={1} paddingRight={1}>
      <text bg={bg} fg={dotColor}>{`${dot} `}</text>
      <text bg={bg} fg={nameColor}>{node.name}</text>
      {node.source === "env" && <text bg={bg} fg={theme.textMuted}>{"  env"}</text>}
      <box flexGrow={1} backgroundColor={bg} />
      <text bg={bg} fg={theme.textMuted}>{`${node.sessions.length}`}</text>
    </box>
  )
}

// Redact a cookie to first-2 + last-2, masking the middle. A cookie is an RCE
// credential, so never render it in full — enough to recognize, not to reuse.
function redactCookie(c: string | null | undefined): string {
  if (!c) return "—"
  if (c.length <= 4) return "•".repeat(c.length)
  return `${c.slice(0, 2)}••••${c.slice(-2)}`
}

// Detail block at the top of the sessions pane: host / cookie(redacted) / ssh
// route, aligned key–value rows. The connect error (if any) rides underneath.
function NodeDetailBand({ node, error }: { node: Node; error: Server.Schema.AppError | null }) {
  const host = node.ssh_host || (node.name.includes("@") ? node.name.split("@")[1] : node.name)
  const rows: [string, string][] = [
    ["host", host],
    ["cookie", redactCookie(node.cookie)]
  ]
  if (node.ssh_host) {
    rows.push([
      "ssh",
      `${node.ssh_user ? `${node.ssh_user}@` : ""}${node.ssh_host}` +
        (node.container ? ` · ${node.container}` : "")
    ])
  }
  if (node.source === "env") rows.push(["source", "env (read-only)"])
  return (
    <box flexDirection="row" flexWrap="wrap" marginBottom={1}>
      {rows.map(([k, v]) => (
        <Chip key={k} label={k} value={v} />
      ))}
      {error && <Chip label="error" value={`${error.message} · c retry`} tone="error" />}
    </box>
  )
}

// Session-number style: "period" = `1.`, "dot" = `1 ·`.
const SESSION_NUM_STYLE: "period" | "dot" = "dot"

function SessionRow({
  session,
  index,
  nameWidth,
  active
}: {
  session: Session
  index: number
  nameWidth: number
  active: boolean
}) {
  const bg = active ? theme.backgroundElement : theme.background
  const num = SESSION_NUM_STYLE === "dot" ? `${index} ·` : `${index}.`
  return (
    <box backgroundColor={bg} flexDirection="row" paddingLeft={1} paddingRight={1}>
      <text bg={bg} fg={theme.textMuted}>{num.padStart(4)}</text>
      <text bg={bg} fg={active ? theme.text : theme.textMuted}>{`  ${truncate(session.name, nameWidth)}`}</text>
    </box>
  )
}

function ModalLayer({
  modal,
  presetList,
  presetIdx,
  nameDraft,
  hostDraft,
  portDraft,
  cookieDraft,
  sshHostDraft,
  sshPortDraft,
  sshUserDraft,
  containerDraft,
  nodeField,
  onName,
  onHost,
  onPort,
  onCookie,
  onSshHost,
  onSshPort,
  onSshUser,
  onContainer,
  onPresetChange,
  onPickPreset,
  onCommit
}: {
  modal: Modal
  presetList: readonly Server.Schema.Preset[]
  presetIdx: number
  nameDraft: string
  hostDraft: string
  portDraft: string
  cookieDraft: string
  sshHostDraft: string
  sshPortDraft: string
  sshUserDraft: string
  containerDraft: string
  nodeField: number
  onName: (v: string) => void
  onHost: (v: string) => void
  onPort: (v: string) => void
  onCookie: (v: string) => void
  onSshHost: (v: string) => void
  onSshPort: (v: string) => void
  onSshUser: (v: string) => void
  onContainer: (v: string) => void
  onPresetChange: (index: number) => void
  onPickPreset: (index: number) => void
  onCommit: (kind: Modal["kind"], value: string) => void
}) {
  const box = (title: string, children: ReactNode) => (
    <Overlay title={title}>{children}</Overlay>
  )

  switch (modal.kind) {
    case "help":
      return (
        <HelpOverlay
          title="help"
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
            hint="myapp"
            value={nameDraft}
            onInput={onName}
            focused={nodeField === 0}
          />
          <Field
            label="host"
            hint="127.0.0.1"
            value={hostDraft}
            onInput={onHost}
            focused={nodeField === 1}
          />
          <Field
            label="port"
            hint="(optional — direct dist port)"
            value={portDraft}
            onInput={onPort}
            focused={nodeField === 2}
          />
          <Field
            label="cookie"
            hint="secretcookie"
            value={cookieDraft}
            onInput={onCookie}
            focused={nodeField === 3}
          />
          <text fg={theme.dim} marginTop={1}>over SSH (optional — leave blank to dial directly)</text>
          <Field
            label="ssh host"
            hint="prod-1.example.com"
            value={sshHostDraft}
            onInput={onSshHost}
            focused={nodeField === 4}
          />
          <Field
            label="ssh port"
            hint="22"
            value={sshPortDraft}
            onInput={onSshPort}
            focused={nodeField === 5}
          />
          <Field
            label="ssh user"
            hint="deploy"
            value={sshUserDraft}
            onInput={onSshUser}
            focused={nodeField === 6}
          />
          <Field
            label="container"
            hint="myapp"
            value={containerDraft}
            onInput={onContainer}
            focused={nodeField === 7}
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
          hint="checkout-flow"
          onSubmit={(v) => onCommit("newSessionName", v)}
        />
      )

    case "newSessionPreset":
      return box(
        `Session "${modal.name}" — init from`,
        <>
          <select
            focused
            height={presetList.length + 1}
            itemSpacing={0}
            options={[
              { name: "(blank)", description: "" },
              ...presetList.map((p) => ({ name: p.name, description: "" }))
            ]}
            selectedIndex={presetIdx}
            showDescription={false}
            backgroundColor={theme.overlay}
            textColor={theme.textMuted}
            focusedBackgroundColor={theme.overlay}
            focusedTextColor={theme.text}
            selectedBackgroundColor={theme.backgroundElement}
            selectedTextColor={theme.selectedForeground}
            onChange={(i: number) => onPresetChange(i)}
            onSelect={(i: number) => onPickPreset(i)}
          />
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
      <text fg={focused ? theme.title : theme.dim}>{label}</text>
      <input
        focused={focused}
        value={value}
        onInput={onInput}
        placeholder={hint}
        backgroundColor={theme.bg}
        textColor={theme.fg}
        focusedBackgroundColor={theme.selBg}
        focusedTextColor={theme.selFg}
      />
    </box>
  )
}
