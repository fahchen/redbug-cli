/** @jsxImportSource @opentui/react */
import type { ReactNode } from "react"
import { theme } from "./theme"
import { isRtpChanged } from "./sessionHelpers"
import type { Rtp } from "./types"
import { parseLimits } from "./limits"
import { Overlay, TextField } from "./ui"
import { ConfirmOverlay } from "./ConfirmOverlay"
import { RtpCheatSheet } from "./RtpCheatSheet"

// --- Types ---

export type RtpModal =
  | { kind: "none" }
  | { kind: "add" }
  | { kind: "edit"; id: string; text: string }
  | { kind: "savePreset" }
  | { kind: "savePresetOverwrite"; name: string }
  | { kind: "confirmTraceDelete"; id: string }

export type ImportState = {
  phase: "pick" | "traces"
  presetIdx: number
  selected: Set<number>
  traceSel: number
}

type Preset = Server.Schema.Preset

// --- Props ---

interface EditorProps {
  traces: Rtp[]
  rtpSel: number
  rtpModal: RtpModal
  editingLimits: boolean
  limitsDraft: string
  importState: ImportState | null
  presets: Preset[]
  appliedTraces: readonly Rtp[]
  running: boolean
  dirty: boolean
  limits: { keep: number; time: number; msgs: number }
  onRtpSel: (i: number) => void
  onRtpModal: (m: RtpModal) => void
  onEditingLimits: (v: boolean) => void
  onLimitsDraft: (v: string) => void
  onImportState: (s: ImportState | null) => void
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  dispatch: (action: string, payload?: any) => void
}

// --- Component ---

export function EditorOverlay(props: EditorProps): ReactNode {
  const {
    traces, rtpSel, rtpModal, editingLimits, limitsDraft, importState, presets,
    appliedTraces, running, dirty, limits, onRtpSel, onRtpModal, onEditingLimits,
    onLimitsDraft, onImportState, dispatch
  } = props

  // Import: pick preset phase
  if (importState !== null && importState.phase === "pick") {
    return (
      <Overlay title="Import from preset">
        {presets.map((pr, i) => {
          const active = i === importState.presetIdx
          const bg = active ? theme.backgroundElement : theme.overlay
          return (
            <box key={pr.id} backgroundColor={bg} flexDirection="row" paddingLeft={1} paddingRight={1}>
              <text bg={bg} fg={active ? theme.text : theme.textMuted}>{pr.name}</text>
              <box flexGrow={1} backgroundColor={bg} />
              <text bg={bg} fg={theme.dim}>{pr.traces.length}</text>
            </box>
          )
        })}
        <text fg={theme.dim} marginTop={1}>j/k move · Enter select · Esc cancel</text>
      </Overlay>
    )
  }

  // Import: select traces phase
  if (importState !== null && importState.phase === "traces") {
    const p = presets[importState.presetIdx]
    const sc = importState.selected.size
    const tc = p.traces.length
    return (
      <Overlay title={`Import from ${p.name} (${sc}/${tc})`}>
        <box flexDirection="column">
          {p.traces.map((t, j) => {
            const active = j === importState.traceSel
            const bg = active ? theme.backgroundElement : theme.overlay
            return (
              <box key={t.id} backgroundColor={bg} flexDirection="row" paddingLeft={1}>
                <text bg={bg} fg={importState.selected.has(j) ? theme.success : theme.textMuted}>
                  {importState.selected.has(j) ? "[x] " : "[ ] "}
                </text>
                <text bg={bg} fg={active ? theme.text : theme.textMuted}>{t.text}</text>
              </box>
            )
          })}
        </box>
        <text fg={theme.dim} marginTop={1}>j/k move · space toggle · a select all · Enter import · Esc back</text>
      </Overlay>
    )
  }

  // Level 3: savePreset name form
  if (rtpModal.kind === "savePreset") {
    return (
      <Overlay>
        <TextField
          key="rtp-savePreset"
          label="Save as preset — name:"
          hint="reusable template (traces + limits)"
          onSubmit={(v) => {
            const name = v.trim()
            if (name === "") { onRtpModal({ kind: "none" }); return }
            if (presets.some((p) => p.name === name)) {
              onRtpModal({ kind: "savePresetOverwrite", name })
            } else {
              dispatch("saveAsPreset", { name })
              onRtpModal({ kind: "none" })
            }
          }}
        />
      </Overlay>
    )
  }

  // Level 3: savePreset overwrite confirm
  if (rtpModal.kind === "savePresetOverwrite") {
    return (
      <ConfirmOverlay
        question={`Overwrite preset "${rtpModal.name}"?`}
        labels={{ y: "overwrite", n: "cancel" }}
      />
    )
  }

  // Level 3: confirmTraceDelete
  if (rtpModal.kind === "confirmTraceDelete") {
    return <ConfirmOverlay question="Delete this trace?" />
  }

  // Level 2: add / edit form
  if (rtpModal.kind === "add" || rtpModal.kind === "edit") {
    return (
      <Overlay>
        <TextField
          key={rtpModal.kind === "edit" ? "rtp-edit" : "rtp-add"}
          label={rtpModal.kind === "edit" ? "Edit RTP:" : "New RTP:"}
          hint="redbug spec, e.g. lists:seq/2 -> return"
          initial={rtpModal.kind === "edit" ? rtpModal.text : undefined}
          onSubmit={(v) => {
            if (rtpModal.kind === "edit") dispatch("updateTrace", { trace_id: rtpModal.id, text: v })
            else if (v.trim() !== "") dispatch("addTrace", { text: v })
            onRtpModal({ kind: "none" })
          }}
        />
        <RtpCheatSheet />
      </Overlay>
    )
  }

  // Level 1 — trace list: select / toggle / delete
  return (
    <Overlay>
      <text fg={theme.title}>{"Traces"}</text>
      <box flexDirection="column" marginTop={1}>
        {traces.length === 0 ? (
          <text fg={theme.dim}>No patterns yet · n to add</text>
        ) : (
          traces.map((t, i) => {
            const on = i === rtpSel
            const bg = on ? theme.backgroundElement : theme.overlay
            const changed = running && dirty && isRtpChanged(t, appliedTraces)
            return (
              <box key={t.id} backgroundColor={bg} flexDirection="row" paddingLeft={1} paddingRight={1}>
                {changed && <text bg={bg} fg={theme.warning}>{"* "}</text>}
                <text bg={bg} fg={t.enabled ? theme.success : theme.textMuted}>{t.enabled ? "[x] " : "[ ] "}</text>
                <text bg={bg} fg={on ? theme.text : theme.textMuted}>{t.text}</text>
              </box>
            )
          })
        )}
      </box>
      <box flexDirection="column" marginTop={1}>
        {editingLimits ? (
          <>
            <text fg={theme.textMuted}>keep time msgs (space-separated) · Enter save · Esc cancel</text>
            <input
              focused
              value={limitsDraft}
              onInput={(v: string) => onLimitsDraft(v)}
              onSubmit={() => {
                const p = parseLimits(limitsDraft)
                if (p) dispatch("updateLimits", p)
                onEditingLimits(false)
              }}
              backgroundColor={theme.bg}
              textColor={theme.fg}
              focusedBackgroundColor={theme.selBg}
              focusedTextColor={theme.selFg}
            />
          </>
        ) : (
          <text fg={theme.textMuted}>{`Limits: keep ${limits.keep} · time ${limits.time}s · msgs ${limits.msgs}`}</text>
        )}
      </box>
      <text fg={theme.dim} marginTop={1}>n new · e edit · d del · i import · l limits · space toggle · ⌃W save · esc close</text>
    </Overlay>
  )
}


