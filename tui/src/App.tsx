/** @jsxImportSource @opentui/react */
import { useRef, useState, useEffect } from "react"
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
import { Chip, HelpOverlay, HintProvider, Notice, Overlay, Panel, StatusBar, TextField, truncate, useSpinner, useScrollFollow } from "./ui"
import { DialogSelect } from "./DialogSelect"
import { NodeRow, SessionRow, NodeDetailBand, EmptyTree, isValidHost } from "./Tree"
import { ModalLayer as NodeModalLayer } from "./NodeModal"
import { SessionScreen } from "./SessionScreen"
import { PresetManager } from "./PresetManager"
import { SnippetManager } from "./SnippetManager"
import { reconcileEditFiles, sessionPrefix } from "./editor"
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
  | { name: "settings"; from: Screen }

type Modal =
  | { kind: "none" }
  | { kind: "help" }
  | { kind: "newNode" }
  | { kind: "editNode"; id: string }
  | { kind: "newSessionName"; nodeId: string }
  | { kind: "newSessionPreset"; nodeId: string; name: string }
  | { kind: "renameSession"; nodeId: string; sessionId: string }
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
  const presetsSnap = useMusubiSnapshot(presetsStore)
  const settings = settingsSnap?.settings as Server.Schema.Settings | undefined
  setTheme(settings?.theme ?? "dark")

  // Tree selection lives here, not in S1View, so it survives opening a session
  // (S1View unmounts while the SessionScreen is up).
  const [nodeSel, setNodeSel] = useState(0)
  const [sessSel, setSessSel] = useState(0)

  return (
    <HintProvider show={settings?.show_hints ?? true}>
      {renderScreen()}
    </HintProvider>
  )

  function renderScreen(): ReactNode {
    // Settings is reachable from every screen via `,`; it remembers where it was
    // opened from so closing returns there.
    if (screen.name === "settings")
      return <SettingsOverlay onClose={() => setScreen(screen.from)} />

    const openSettings = () => setScreen({ name: "settings", from: screen })

    if (screen.name === "session")
      return (
        <SessionScreen
          nodeId={screen.nodeId}
          sessionId={screen.sessionId}
          settings={settings}
          presets={presetsSnap?.presets as Server.Schema.Preset[] | undefined}
          onBack={() => setScreen({ name: "tree" })}
          onOpenSettings={openSettings}
        />
      )

    if (screen.name === "presets")
      return <PresetManager onBack={() => setScreen({ name: "tree" })} onOpenSettings={openSettings} />

    if (screen.name === "snippets")
      return <SnippetManager onBack={() => setScreen({ name: "tree" })} onOpenSettings={openSettings} />

    return (
      <S1View
        nodesStore={nodesStore}
        presetsStore={presetsStore}
        nodeSel={nodeSel}
        setNodeSel={setNodeSel}
        sessSel={sessSel}
        setSessSel={setSessSel}
        onOpenSession={(nodeId, sessionId) => setScreen({ name: "session", nodeId, sessionId })}
        onOpenPresets={() => setScreen({ name: "presets" })}
        onOpenSnippets={() => setScreen({ name: "snippets" })}
        onOpenSettings={openSettings}
      />
    )
  }
}

type Focus = "nodes" | "sessions"

type SetNum = (v: number | ((prev: number) => number)) => void

function S1View({
  nodesStore,
  presetsStore,
  nodeSel,
  setNodeSel,
  sessSel,
  setSessSel,
  onOpenSession,
  onOpenPresets,
  onOpenSnippets,
  onOpenSettings
}: {
  nodesStore: NodesStore
  presetsStore: PresetsStore
  nodeSel: number
  setNodeSel: SetNum
  sessSel: number
  setSessSel: SetNum
  onOpenSession: (nodeId: string, sessionId: string) => void
  onOpenPresets: () => void
  onOpenSnippets: () => void
  onOpenSettings: () => void
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

  // number-nav for the session list: accumulate typed digits (so 10+ is
  // reachable), jump to that 1-based session, reset the buffer after a pause.
  const sessNumBuf = useRef("")
  const sessNumTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const pendingSession = useRef<{ nodeId: string; name: string } | null>(null)
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
  const [labelDraft, setLabelDraft] = useState("")
  const [nodeField, setNodeField] = useState(0)
  const [nodeErr, setNodeErr] = useState<string | null>(null)
  const [renameDraft, setRenameDraft] = useState("")
  const NODE_FIELDS = 9
  const moveNodeField = (delta: number) => {
    setNodeField((f) => (f + delta + NODE_FIELDS) % NODE_FIELDS)
  }

  const nodeIdx = Math.min(nodeSel, Math.max(0, nodeList.length - 1))
  const node = nodeList[nodeIdx] ?? null
  const nodeProxy = node ? nodesStore.nodes[nodeIdx] : undefined
  const sessions = node?.sessions ?? []
  const sessIdx = Math.min(sessSel, Math.max(0, sessions.length - 1))
  const session = sessions[sessIdx] ?? null
  const nodesScrollRef = useScrollFollow(node?.id)
  const sessScrollRef = useScrollFollow(session?.id)
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
    if (np) {
      dispatcher(np)("createSession", { name: modal.name, from_preset_id: fromPresetId })
      pendingSession.current = { nodeId: modal.nodeId, name: modal.name }
    }
    setModal({ kind: "none" })
  }

  // After creating a session, auto-open it once it appears in the list.
  useEffect(() => {
    if (!pendingSession.current) return
    const node = nodeList.find((n) => n.id === pendingSession.current!.nodeId)
    if (!node) return
    const session = node.sessions.find((s) => s.name === pendingSession.current!.name)
    if (session) {
      const ps = pendingSession.current!
      pendingSession.current = null
      onOpenSession(ps.nodeId, session.id)
    }
  }, [nodeList])

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
    setLabelDraft("")
    setNodeField(0)
    setModal({ kind: "newNode" })
  }

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

      case "renameSession":
        // TextField owns Enter; only Esc closes
        if (name === "escape") setModal({ kind: "none" })
        return

      case "newSessionPreset":
        // DialogSelect owns all keys
        return

      case "newNode":
      case "editNode":
        if (name === "escape") {
          setNodeErr(null)
          setModal({ kind: "none" })
        } else if (name === "tab") moveNodeField(key.shift ? -1 : 1)
        else if (name === "return") {
          // ssh nodes auto-discover their name + cookie/host, so validation only
          // applies to a directly-dialed node (name@host must be a real Erlang name).
          const isSsh = sshHostDraft.trim() !== ""
          if (!isSsh) {
            if (nameDraft.trim() === "" || cookieDraft.trim() === "") {
              setNodeErr("Direct node needs a name and cookie")
              break
            }
            if (!isValidHost(hostDraft)) {
              setNodeErr("Host must be a hostname or IP (e.g. 127.0.0.1 or app.example.com), not a bare number")
              break
            }
          }
          setNodeErr(null)
          {
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
              container: containerDraft,
              label: labelDraft || null
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

    // The server drops a deleted session's console history; its .redbug/ edit
    // buffers are ours to sweep (nothing else records their names).
    const sweepSessionFiles = (ids: string[]) => {
      ids.forEach((id) => void reconcileEditFiles(sessionPrefix(id), []))
    }

    // no modal — two-pane navigation
    const newSession = () => {
      if (node) {
        setPresetIdx(0)
        setModal({ kind: "newSessionName", nodeId: node.id })
      }
    }

    if (focus === "sessions") {
      if (key.ctrl && name === "d" && node && session && sessionProxy) {
        dispatcher(sessionProxy)("deleteSession")
        sweepSessionFiles([session.id])
        setSessSel((i) => Math.max(0, i - 1))
        return
      }
      switch (name) {
        case "escape":
        case "tab":
        case "left":
        case "h":
          setFocus("nodes")
          break
        case "j":
        case "down":
          setSessSel((i) => (i + 1 >= sessions.length ? 0 : i + 1))
          break
        case "k":
        case "up":
          // wrap
          setSessSel((i) => (i <= 0 ? Math.max(0, sessions.length - 1) : i - 1))
          break
        case "return":
          if (node && session) onOpenSession(node.id, session.id)
          break
        case "n":
          newSession()
          break
        case "r":
          if (node && session) {
            setRenameDraft(session.name)
            setModal({ kind: "renameSession", nodeId: node.id, sessionId: session.id })
          }
          break
        case "g":
          if (sessNumBuf.current !== "" && sessions.length > 0) {
            const n = parseInt(sessNumBuf.current, 10)
            if (n >= 1) setSessSel(Math.min(n - 1, sessions.length - 1))
            sessNumBuf.current = ""
            if (sessNumTimer.current) clearTimeout(sessNumTimer.current)
          }
          break
        case "d":
          if (node && session) {
            const proxy = sessionProxy
            setModal({
              kind: "confirm",
              label: `Delete session "${session.name}"?`,
              run: () => {
                if (!proxy) return
                dispatcher(proxy)("deleteSession")
                sweepSessionFiles([session.id])
                setSessSel((i) => Math.max(0, i - 1))
              }
            })
          }
          break
        case "?":
          setModal({ kind: "help" })
          break
        default:
          // digit → accumulate buffer; press g to jump
          if (/^[0-9]$/.test(name) && sessions.length > 0) {
            if (sessNumTimer.current) clearTimeout(sessNumTimer.current)
            sessNumBuf.current += name
            sessNumTimer.current = setTimeout(() => {
              sessNumBuf.current = ""
            }, 2000)
          }
          break
      }
      return
    }

    // focus === "nodes"
    if (key.ctrl && name === "d" && node && node.source !== "env" && nodeProxy) {
      dispatcher(nodeProxy)("deleteNode")
      sweepSessionFiles(node.sessions.map((s) => s.id))
      setNodeSel((i) => Math.max(0, i - 1))
      setSessSel(0)
      return
    }
    switch (name) {
      case "j":
      case "down":
        setNodeSel((i) => (i + 1 >= nodeList.length ? 0 : i + 1))
        setSessSel(0)
        break
      case "k":
      case "up":
        setNodeSel((i) => (i <= 0 ? Math.max(0, nodeList.length - 1) : i - 1))
        setSessSel(0)
        break
      case "return":
      case "tab":
      case "right":
        // focus sessions even when empty, so `n` there creates the first one
        if (node) {
          setSessSel(0)
          setFocus("sessions")
        }
        break
      case "n":
        openNewNode()
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
          setLabelDraft(node.label ?? "")
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
            run: () => {
              dispatcher(proxy)("deleteNode")
              sweepSessionFiles(node.sessions.map((s) => s.id))
              setNodeSel((i) => Math.max(0, i - 1))
              setSessSel(0)
            }
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
        onOpenSettings()
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
        <Panel heading="Nodes" active={focus === "nodes"} width={40}>
          <scrollbox ref={nodesScrollRef} scrollY flexGrow={1}>
          {nodeList.length === 0 ? (
            <EmptyTree />
          ) : (
            nodeList.map((n, i) => (
              <NodeRow key={n.id} id={n.id} node={n} active={i === nodeIdx} />
            ))
          )}
          </scrollbox>
        </Panel>

        <Panel heading={node ? node.name : "—"} active={focus === "sessions"} grow>
          {node && <NodeDetailBand node={node} error={nodeError} />}
          <scrollbox ref={sessScrollRef} scrollY flexGrow={1}>
          {!node ? (
            <text fg={theme.textMuted}>Select a node</text>
          ) : sessions.length === 0 ? (
            <text fg={theme.textMuted}>No sessions · n to add</text>
          ) : (
            sessions.map((s, i) => (
              <SessionRow key={s.id} id={s.id} session={s} index={i + 1} nameWidth={sessNameWidth} active={focus === "sessions" && i === sessIdx} />
            ))
          )}
          </scrollbox>
        </Panel>
      </box>

      <StatusBar
        statusText={`${connCount}/${nodeList.length} connected`}
        hints={
          focus === "nodes"
            ? envMode
              ? "j/k node · enter sessions · n new · c connect · e edit · d del · p presets · l snippets · env read-only · , settings · ? help · q quit"
              : "j/k node · enter sessions · n new · c connect · e edit · d del · p presets · l snippets · , settings · ? help · q quit"
            : "j/k session · enter open · r rename · n new · d del · #g jump · tab/esc nodes · ? help"
        }
      />

      {modal.kind !== "none" && (
        <NodeModalLayer
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
          labelDraft={labelDraft}
          renameDraft={renameDraft}
          nodeField={nodeField}
          nodeErr={nodeErr}
          nodeList={nodeList}
          nodeProxyById={nodeProxyById}
          onName={setNameDraft}
          onHost={setHostDraft}
          onPort={setPortDraft}
          onCookie={setCookieDraft}
          onSshHost={setSshHostDraft}
          onSshPort={setSshPortDraft}
          onSshUser={setSshUserDraft}
          onContainer={setContainerDraft}
          onLabel={setLabelDraft}
          onPresetChange={setPresetIdx}
          onPickPreset={commitPreset}
          onDismiss={() => setModal({ kind: "none" })}
          onCommit={(m, payload) => {
            if (m === "newSessionName")
              setModal({ kind: "newSessionPreset", nodeId: (modal as any).nodeId, name: payload })
          }}
        />
      )}
    </box>
  )
}
