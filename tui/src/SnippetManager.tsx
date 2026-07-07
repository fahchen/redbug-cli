/** @jsxImportSource @opentui/react */
import { useState, useRef, useEffect } from "react"
import { useKeyboard, useRenderer } from "@opentui/react"
import type { StoreProxy } from "@musubi/react"

import { SNIPPETS_ROOT, dispatcher, useMusubiRoot, useMusubiSnapshot } from "./musubi"
import { editInEditor } from "./editor"
import { theme } from "./theme"
import { elixirStyle, tsClient } from "./treesitter"
import { HelpOverlay, Overlay, RootGate, StatusBar, TextField } from "./ui"

type SnippetsStore = StoreProxy<"Server.Stores.SnippetsRoot", Musubi.Stores>
type SnippetProxy = StoreProxy<"Server.Stores.SnippetStore", Musubi.Stores>
type Snippet = Server.Schema.Snippet

type Modal =
  | { kind: "none" }
  | { kind: "help" }
  | { kind: "newSnippet" }
  | { kind: "rename"; id: string; name: string }
  | { kind: "confirmDelete"; id: string; name: string }

export function SnippetManager({ onBack }: { onBack: () => void }) {
  const root = useMusubiRoot(SNIPPETS_ROOT)
  return (
    <RootGate root={root} loading="Loading snippets…" errorLabel="Snippets">
      {(store) => <SnippetView store={store} onBack={onBack} />}
    </RootGate>
  )
}

function SnippetView({ store, onBack }: { store: SnippetsStore; onBack: () => void }) {
  const snap = useMusubiSnapshot(store)
  const snippets = (snap?.snippets ?? []) as Snippet[]
  const renderer = useRenderer()

  const [sel, setSel] = useState(0)
  const [modal, setModal] = useState<Modal>({ kind: "none" })

  const cur = snippets[Math.min(sel, snippets.length - 1)] ?? null
  const numBuf = useRef("")
  const numTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const pendingSnippet = useRef<string | null>(null)

  // After creating a new snippet, auto-select and open $EDITOR.
  useEffect(() => {
    if (!pendingSnippet.current) return
    const idx = snippets.findIndex((s) => s.name === pendingSnippet.current)
    if (idx >= 0) {
      setSel(idx)
      pendingSnippet.current = null
      // Need to wait for the state update before opening editor
      setTimeout(() => {
        const snip = snippets[idx]
        if (snip) editCode(snip)
      }, 100)
    }
  }, [snippets])

  // createSnippet is the only root command; snippet-scoped mutations dispatch on
  // the matching child proxy (store path is the routing — no snippet_id payload).
  const createSnippet = dispatcher(store)
  const proxyById = (id: string): SnippetProxy | undefined => {
    const i = snippets.findIndex((s) => s.id === id)
    return i >= 0 ? store.snippets[i] : undefined
  }

  const editCode = (snip: Snippet) => {
    const proxy = proxyById(snip.id)
    if (!proxy) return
    void (async () => {
      const code = await editInEditor(renderer, {
        file: `redbug-snippet-${snip.id}-${Date.now()}.exs`,
        seed: snip.code
      })
      if (code !== null) dispatcher(proxy)("updateSnippet", { code })
    })()
  }

  useKeyboard((key) => {
    const n = key.name

    if (modal.kind === "confirmDelete") {
      if (n === "y") {
        const p = proxyById(modal.id)
        if (p) dispatcher(p)("deleteSnippet")
        setModal({ kind: "none" })
        setSel((i) => Math.max(0, i - 1))
      } else if (n === "n" || n === "escape") setModal({ kind: "none" })
      return
    }
    if (modal.kind === "help") {
      setModal({ kind: "none" })
      return
    }
    if (modal.kind !== "none") {
      if (n === "escape") setModal({ kind: "none" })
      return
    }

    switch (n) {
      case "escape":
        onBack()
        break
      case "j":
      case "down":
        setSel((i) => Math.min(i + 1, snippets.length - 1))
        break
      case "k":
      case "up":
        setSel((i) => Math.max(i - 1, 0))
        break
      case "e":
        if (cur) editCode(cur)
        break
      case "n":
        setModal({ kind: "newSnippet" })
        break
      case "r":
        if (cur) setModal({ kind: "rename", id: cur.id, name: cur.name })
        break
      case "f":
        if (cur) {
          const p = proxyById(cur.id)
          if (p) dispatcher(p)("formatSnippet")
        }
        break
      case "d":
        if (cur) setModal({ kind: "confirmDelete", id: cur.id, name: cur.name })
        break
      case "?":
        setModal({ kind: "help" })
        break
      default:
        if (/^[0-9]$/.test(n) && snippets.length > 0) {
          if (numTimer.current) clearTimeout(numTimer.current)
          numBuf.current += n
          const num = parseInt(numBuf.current, 10)
          setSel(Math.min(Math.max(num - 1, 0), snippets.length - 1))
          numTimer.current = setTimeout(() => { numBuf.current = "" }, 800)
        }
        break
    }
  })

  return (
    <box flexDirection="column" flexGrow={1} backgroundColor={theme.background}>
      <box flexDirection="row" flexGrow={1} gap={1} paddingTop={1}>
        <box
          border
          borderColor={theme.title}
          backgroundColor={theme.background}
          title={` Snippets (${snippets.length}) `}
          titleColor={theme.title}
          width={32}
          flexDirection="column"
          padding={1}
        >
          {snippets.length === 0 ? (
            <text fg={theme.dim}>No snippets yet · n to add</text>
          ) : (
            snippets.map((s, i) => <SnippetRow key={s.id} snippet={s} active={i === sel} index={i + 1} />)
          )}
        </box>

        <box
          border
          borderColor={theme.border}
          backgroundColor={theme.background}
          title={cur ? ` ${cur.name} ` : " — "}
          titleColor={theme.title}
          flexGrow={1}
          flexBasis={0}
          flexDirection="column"
          padding={1}
        >
          {!cur ? (
            <text fg={theme.dim}>Select a snippet</text>
          ) : cur.code.trim() === "" ? (
            <text fg={theme.dim}>Empty · e to edit in $EDITOR</text>
          ) : (
            <code
              content={cur.code}
              filetype="elixir"
              syntaxStyle={elixirStyle}
              treeSitterClient={tsClient}
            />
          )}
        </box>
      </box>

      <StatusBar
        statusText={`${snippets.length} snippets`}
        hints="j/k move · e edit · n new · ? help · esc back"
      />

      {modal.kind === "help" && (
        <HelpOverlay
          title="snippets"
          sections={[
            {
              lines: [
                ["j / k", "move"],
                ["e", "edit code in $EDITOR"],
                ["n", "new snippet"],
                ["r", "rename"],
                ["f", "format code"],
                ["d", "delete"],
                ["esc", "back"]
              ]
            }
          ]}
        />
      )}

      {modal.kind === "newSnippet" && (
        <Overlay>
          <TextField
            label="New snippet — name:"
            onSubmit={(v) => {
              const name = v.trim()
              if (name !== "") {
                pendingSnippet.current = name
                createSnippet("createSnippet", { name })
              }
              setModal({ kind: "none" })
            }}
          />
        </Overlay>
      )}

      {modal.kind === "rename" && (
        <Overlay>
          <TextField
            label="Rename snippet:"
            initial={modal.name}
            onSubmit={(v) => {
              const p = proxyById(modal.id)
              if (v.trim() !== "" && p) dispatcher(p)("renameSnippet", { name: v })
              setModal({ kind: "none" })
            }}
          />
        </Overlay>
      )}

      {modal.kind === "confirmDelete" && (
        <Overlay>
          <text fg={theme.fg}>{`Delete snippet "${modal.name}"?`}</text>
          <text fg={theme.dim} marginTop={1}>y = yes · n/Esc = no</text>
        </Overlay>
      )}
    </box>
  )
}

function SnippetRow({ snippet, active, index }: { snippet: Snippet; active: boolean; index: number }) {
  const bg = active ? theme.selBg : theme.background
  const fg = active ? theme.selFg : theme.fg
  return (
    <box backgroundColor={bg} flexDirection="row" paddingLeft={1} paddingRight={1}>
      <text bg={bg} fg={theme.dim}>{`${index} · `}</text>
      <text bg={bg} fg={fg}>{snippet.name}</text>
    </box>
  )
}

