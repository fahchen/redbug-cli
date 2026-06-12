/** @jsxImportSource @opentui/react */
import { useState } from "react"
import { useKeyboard, useRenderer } from "@opentui/react"
import type { StoreProxy } from "@musubi/react"

import { SNIPPETS_ROOT, dispatcher, useMusubiRoot, useMusubiSnapshot } from "./musubi"
import { editInEditor } from "./editor"
import { theme } from "./theme"
import { Footer, Header, HelpOverlay, Overlay, RootGate, TextField } from "./ui"

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
  const snippets = (snap.snippets ?? []) as Snippet[]
  const renderer = useRenderer()

  const [sel, setSel] = useState(0)
  const [modal, setModal] = useState<Modal>({ kind: "none" })

  const cur = snippets[Math.min(sel, snippets.length - 1)] ?? null

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
      case "return":
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
    }
  })

  return (
    <box flexDirection="column" flexGrow={1} backgroundColor={theme.bg}>
      <Header title="Snippets — global library" />

      <box flexDirection="row" flexGrow={1}>
        <box
          border
          borderColor={theme.title}
          backgroundColor={theme.bg}
          title={`Snippets (${snippets.length})`}
          titleColor={theme.title}
          width={32}
          flexDirection="column"
          padding={1}
        >
          {snippets.length === 0 ? (
            <text fg={theme.dim}>No snippets yet · n to add</text>
          ) : (
            snippets.map((s, i) => <SnippetRow key={s.id} snippet={s} active={i === sel} />)
          )}
        </box>

        <box
          border
          borderColor={theme.border}
          backgroundColor={theme.bg}
          title={cur ? cur.name : "—"}
          titleColor={theme.title}
          flexGrow={1}
          flexBasis={0}
          flexDirection="column"
          padding={1}
        >
          {!cur ? (
            <text fg={theme.dim}>Select a snippet</text>
          ) : cur.code.trim() === "" ? (
            <text fg={theme.dim}>Empty · enter to edit in $EDITOR</text>
          ) : (
            cur.code.split("\n").slice(0, 24).map((l, i) => (
              <text key={i} fg={theme.fg}>{l}</text>
            ))
          )}
        </box>
      </box>

      <Footer text="j/k move · enter edit · n new · r rename · f format · d del · ? help · esc back" />

      {modal.kind === "help" && (
        <HelpOverlay
          title="snippets"
          sections={[
            {
              lines: [
                ["j / k", "move"],
                ["enter", "edit code in $EDITOR"],
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
              if (v.trim() !== "") createSnippet("createSnippet", { name: v })
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

function SnippetRow({ snippet, active }: { snippet: Snippet; active: boolean }) {
  const bg = active ? theme.selBg : theme.bg
  const fg = active ? theme.selFg : theme.fg
  return (
    <box backgroundColor={bg}>
      <text bg={bg} fg={fg}>{snippet.name}</text>
    </box>
  )
}

