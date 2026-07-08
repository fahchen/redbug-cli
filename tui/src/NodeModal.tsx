/** @jsxImportSource @opentui/react */
import type { ReactNode } from "react"
import type { StoreProxy } from "@musubi/react"

import { dispatcher } from "./musubi"
import { theme } from "./theme"
import { DialogSelect } from "./DialogSelect"
import { HelpOverlay, Overlay, TextField } from "./ui"
import { ConfirmOverlay } from "./ConfirmOverlay"

type Node = Server.Schema.Node
type NodeProxy = StoreProxy<"Server.Stores.NodeStore", Musubi.Stores>

type Modal =
  | { kind: "none" }
  | { kind: "help" }
  | { kind: "settings" }
  | { kind: "newNode" }
  | { kind: "editNode"; id: string }
  | { kind: "newSessionName"; nodeId: string }
  | { kind: "newSessionPreset"; nodeId: string; name: string }
  | { kind: "renameSession"; nodeId: string; sessionId: string }
  | { kind: "confirm"; label: string; run: () => void }

export function ModalLayer({
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
  labelDraft,
  renameDraft,
  nodeField,
  nodeErr,
  nodeList,
  nodeProxyById,
  onName,
  onHost,
  onPort,
  onCookie,
  onSshHost,
  onSshPort,
  onSshUser,
  onContainer,
  onLabel,
  onPresetChange,
  onPickPreset,
  onDismiss,
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
  labelDraft: string
  renameDraft: string
  nodeField: number
  nodeErr: string | null
  nodeList: readonly Node[]
  nodeProxyById: (id: string) => NodeProxy | undefined
  onName: (v: string) => void
  onHost: (v: string) => void
  onPort: (v: string) => void
  onCookie: (v: string) => void
  onSshHost: (v: string) => void
  onSshPort: (v: string) => void
  onSshUser: (v: string) => void
  onContainer: (v: string) => void
  onLabel: (v: string) => void
  onPresetChange: (index: number) => void
  onPickPreset: (index: number) => void
  onDismiss: () => void
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
                ["d", "delete"],
                ["⌃D", "delete (no confirm)"]
              ]
            },
            {
              title: "sessions focus",
              lines: [
                ["j / k", "move"],
                ["enter", "open session"],
                ["r", "rename"],
                ["s", "new session"],
                ["d", "delete"],
                ["#g", "jump to session #"],
                ["tab / esc / h", "back to nodes"]
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
            label="Name"
            hint="myapp"
            value={nameDraft}
            onInput={onName}
            focused={nodeField === 0}
          />
          <Field
            label="Host"
            hint="127.0.0.1"
            value={hostDraft}
            onInput={onHost}
            focused={nodeField === 1}
          />
          <Field
            label="Port"
            hint="(optional — direct dist port)"
            value={portDraft}
            onInput={onPort}
            focused={nodeField === 2}
          />
          <Field
            label="Cookie"
            hint="secretcookie"
            value={cookieDraft}
            onInput={onCookie}
            focused={nodeField === 3}
          />
          <text fg={theme.dim} marginTop={1}>SSH (optional — leave blank to dial directly)</text>
          <Field
            label="SSH host"
            hint="prod-1.example.com"
            value={sshHostDraft}
            onInput={onSshHost}
            focused={nodeField === 4}
          />
          <Field
            label="SSH port"
            hint="22"
            value={sshPortDraft}
            onInput={onSshPort}
            focused={nodeField === 5}
          />
          <Field
            label="SSH user"
            hint="deploy"
            value={sshUserDraft}
            onInput={onSshUser}
            focused={nodeField === 6}
          />
          <text fg={theme.dim} marginTop={1}>Container (optional — leave blank for a host process)</text>
          <Field
            label="Container"
            hint="myapp"
            value={containerDraft}
            onInput={onContainer}
            focused={nodeField === 7}
          />
          <text fg={theme.dim} marginTop={1}>Label (optional — human-readable alias)</text>
          <Field
            label="Label"
            hint="Staging"
            value={labelDraft}
            onInput={onLabel}
            focused={nodeField === 8}
          />
          {nodeErr && <text fg={theme.error} marginTop={1}>{`✗ ${nodeErr}`}</text>}
          <text fg={theme.dim} marginTop={1}>Tab/Shift+Tab switch field · Enter save · Esc cancel</text>
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
      return (
        <DialogSelect
          title={`Session "${modal.name}" — init from`}
          items={[
            { id: "_blank", name: "(blank)", query: "blank" },
            ...presetList.map((p) => ({ id: p.id, name: p.name, query: p.name }))
          ]}
          selectedIndex={presetIdx}
          onSelect={(item) => {
            const idx = item.id === "_blank" ? 0 : presetList.findIndex((p) => p.id === item.id) + 1
            onPickPreset(idx)
          }}
          onClose={() => onDismiss()}
        />
      )

    case "renameSession":
      return box(
        "Rename session",
        <TextField
          key={modal.sessionId}
          label="name"
          initial={renameDraft}
          onSubmit={(v) => {
            if (v.trim() !== "") {
              const np = nodeProxyById(modal.nodeId)
              const si = nodeList.findIndex((n) => n.id === modal.nodeId)
              if (np && si >= 0) {
                const sIdx = nodeList[si].sessions.findIndex((s) => s.id === modal.sessionId)
                if (sIdx >= 0) dispatcher(np.sessions[sIdx])("renameSession", { name: v })
              }
            }
            onDismiss()
          }}
        />
      )

    case "confirm":
      return (
        <ConfirmOverlay question={modal.label} />
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
