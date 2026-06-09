/** @jsxImportSource @opentui/react */
import { useState } from "react"
import type { StoreProxy } from "@musubi/react"

import { TRACE_ROOT, useMusubiRoot, useMusubiSnapshot } from "./musubi"

type TraceStore = StoreProxy<"Server.Stores.TraceStore", Musubi.Stores>

const theme = {
  bg: "#f5f5f5",
  fg: "#1c1c1c",
  border: "#9aa0a6",
  title: "#0b57d0",
  selBg: "#cfe3ff",
  selFg: "#0b1f3a",
  desc: "#5f6368"
}

const kindColor: Record<string, string> = {
  call: "#0b57d0",
  retn: "#188038",
  send: "#a8540a",
  recv: "#8430ce"
}

export function App() {
  const root = useMusubiRoot(TRACE_ROOT)

  if (root.status === "loading")
    return (
      <box backgroundColor={theme.bg} flexGrow={1}>
        <text fg={theme.fg}>Connecting to BEAM…</text>
      </box>
    )
  if (root.status === "error")
    return (
      <box backgroundColor={theme.bg} flexGrow={1}>
        <text fg={theme.fg}>{`Connect error: ${root.error.message}`}</text>
      </box>
    )

  return <TraceView store={root.store} />
}

function TraceView({ store }: { store: TraceStore }) {
  const page = useMusubiSnapshot(store)
  const events = page.events ?? []

  const [selected, setSelected] = useState(0)
  const current = events[selected]

  const options = events.map((e) => ({
    name: `${e.ts}  ${e.kind.padEnd(4)}  ${e.mfa}`,
    description: e.name,
    value: e.id
  }))

  return (
    <box flexDirection="row" flexGrow={1} backgroundColor={theme.bg}>
      <box
        border
        borderColor={theme.border}
        backgroundColor={theme.bg}
        title={`Trace events (${events.length})`}
        titleColor={theme.title}
        flexGrow={2}
        flexBasis={0}
        minWidth={20}
        flexDirection="column"
      >
        <select
          focused
          flexGrow={1}
          options={options}
          showDescription
          onChange={(index: number) => setSelected(index)}
          backgroundColor={theme.bg}
          focusedBackgroundColor={theme.bg}
          textColor={theme.fg}
          focusedTextColor={theme.fg}
          selectedBackgroundColor={theme.selBg}
          selectedTextColor={theme.selFg}
          descriptionColor={theme.desc}
          selectedDescriptionColor={theme.desc}
        />
      </box>

      <box
        border
        borderColor={theme.border}
        backgroundColor={theme.bg}
        title="Detail"
        titleColor={theme.title}
        flexGrow={1}
        flexBasis={0}
        minWidth={20}
        flexDirection="column"
        padding={1}
      >
        {current ? (
          <>
            <text fg={kindColor[current.kind] ?? theme.fg}>{`kind:  ${current.kind}`}</text>
            <text fg={theme.fg}>{`ts:    ${current.ts}`}</text>
            <text fg={theme.fg}>{`pid:   ${current.pid}`}</text>
            <text fg={theme.fg}>{`name:  ${current.name}`}</text>
            <text fg={theme.fg}>{`mfa:   ${current.mfa}`}</text>
            <text fg={theme.fg}>{`info:  ${current.info}`}</text>
          </>
        ) : (
          <text fg={theme.fg}>Waiting for trace events…</text>
        )}
      </box>
    </box>
  )
}
