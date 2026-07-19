/** @jsxImportSource @opentui/react */
import type { RefObject } from "react"
import type { ScrollBoxRenderable } from "@opentui/core"
import { theme, PANEL_BORDER } from "./theme"
import { splitEventInfo } from "./sessionHelpers"
import { kindSym } from "./sessionTypes"
import type { TraceEvent } from "./types"
import { Chip } from "./ui"
import { elixirStyle, tsClient } from "./treesitter"

export function DetailMeta({ ev }: { ev: TraceEvent }) {
  const sym = kindSym[ev.kind] ?? "?"
  return (
    <>
      <box flexDirection="row" flexWrap="wrap">
        <Chip label="Kind" value={`${sym} ${ev.kind}`} />
        <Chip label="Ts" value={ev.ts} />
        <Chip label="Pid" value={ev.pid} />
        <Chip label="Name" value={ev.name || "-"} />
      </box>
      <box flexDirection="row" marginTop={1}>
        <Chip label="Mfa" value={ev.mfa || "-"} />
      </box>
    </>
  )
}

export function DetailPane({
  ev,
  ret,
  focused,
  scrollRef
}: {
  ev: TraceEvent
  ret?: string
  focused: boolean
  scrollRef?: RefObject<ScrollBoxRenderable | null>
}) {
  return (
    <box
      border
      borderStyle={PANEL_BORDER}
      borderColor={focused ? theme.borderActive : theme.borderSubtle}
      backgroundColor={theme.background}
      title=" Detail "
      titleColor={theme.textMuted}
      width={46}
      flexDirection="column"
      padding={1}
    >
      <DetailMeta ev={ev} />
      <scrollbox ref={scrollRef} scrollY stickyStart="top" flexGrow={1}>
        <EventDetailBody ev={ev} ret={ret} />
      </scrollbox>
    </box>
  )
}

export function EventDetailBody({ ev, ret }: { ev: TraceEvent; ret?: string }) {
  const { payload, stack } = splitEventInfo(ev)
  const payloadLabel = ev.kind === "call" ? "args" : ev.kind === "retn" ? "return" : "payload"

  return (
    <box flexDirection="column" paddingLeft={1}>
      <text fg={theme.textMuted} marginTop={1}>{payloadLabel}</text>
      <code
        content={payload}
        filetype="elixir"
        syntaxStyle={elixirStyle}
        treeSitterClient={tsClient}
      />
      {ret != null && (
        <>
          <text fg={theme.textMuted} marginTop={1}>return</text>
          <code content={ret} filetype="elixir" syntaxStyle={elixirStyle} treeSitterClient={tsClient} />
        </>
      )}
      {stack.length > 0 && (
        <>
          <text fg={theme.textMuted} marginTop={1}>stack</text>
          <box flexDirection="column">
            {stack.map((line, i) => (
              <box key={`${i}-${line}`} flexDirection="row">
                <text fg={theme.dim}>{`${i + 1}. `.padStart(4)}</text>
                <text fg={theme.textMuted}>{line}</text>
              </box>
            ))}
          </box>
        </>
      )}
    </box>
  )
}
