/** @jsxImportSource @opentui/react */
import { useState } from "react"
import type { ReactNode } from "react"
import { useKeyboard } from "@opentui/react"
import type { StoreProxy } from "@musubi/react"

import { PRESETS_ROOT, useMusubiRoot, useMusubiSnapshot } from "./musubi"
import { theme } from "./theme"

type PresetsStore = StoreProxy<"Server.Stores.PresetsRoot", Musubi.Stores>
type Preset = Server.Schema.Preset
type Rtp = Server.Schema.Rtp

type Focus = "list" | "detail"

type Modal =
  | { kind: "none" }
  | { kind: "newPreset" }
  | { kind: "rename"; id: string; name: string }
  | { kind: "addTrace"; presetId: string }
  | { kind: "editTrace"; presetId: string; traceId: string; text: string }
  | { kind: "limits"; presetId: string; draft: string }
  | { kind: "confirmPreset"; id: string; name: string }
  | { kind: "confirmTrace"; presetId: string; traceId: string }

export function PresetManager({ onBack }: { onBack: () => void }) {
  const root = useMusubiRoot(PRESETS_ROOT)

  if (root.status === "loading")
    return (
      <box backgroundColor={theme.bg} flexGrow={1} padding={1}>
        <text fg={theme.fg}>Loading presets…</text>
      </box>
    )
  if (root.status === "error")
    return (
      <box backgroundColor={theme.bg} flexGrow={1} padding={1}>
        <text fg={theme.off}>{`Presets error: ${root.error.message}`}</text>
      </box>
    )

  return <PresetView store={root.store} onBack={onBack} />
}

function PresetView({ store, onBack }: { store: PresetsStore; onBack: () => void }) {
  const snap = useMusubiSnapshot(store)
  const presets = (snap.presets ?? []) as Preset[]

  const [sel, setSel] = useState(0)
  const [focus, setFocus] = useState<Focus>("list")
  const [traceSel, setTraceSel] = useState(0)
  const [modal, setModal] = useState<Modal>({ kind: "none" })

  const cur = presets[Math.min(sel, presets.length - 1)] ?? null
  const traces = (cur?.traces ?? []) as Rtp[]
  const traceCur = traces[Math.min(traceSel, traces.length - 1)] ?? null

  const dispatch = (name: Parameters<PresetsStore["dispatchCommand"]>[0], payload: any) =>
    void store.dispatchCommand(name as any, payload).catch(() => {})

  useKeyboard((key) => {
    const n = key.name

    if (modal.kind !== "none") {
      if (modal.kind === "confirmPreset") {
        if (n === "y") {
          dispatch("deletePreset", { id: modal.id })
          setModal({ kind: "none" })
          setSel((i) => Math.max(0, i - 1))
        } else if (n === "n" || n === "escape") setModal({ kind: "none" })
        return
      }
      if (modal.kind === "confirmTrace") {
        if (n === "y") {
          dispatch("deletePresetTrace", { preset_id: modal.presetId, trace_id: modal.traceId })
          setModal({ kind: "none" })
        } else if (n === "n" || n === "escape") setModal({ kind: "none" })
        return
      }
      if (n === "escape") setModal({ kind: "none" })
      return
    }

    if (focus === "detail") {
      if (key.ctrl && n === "d") {
        if (cur && traceCur)
          setModal({ kind: "confirmTrace", presetId: cur.id, traceId: traceCur.id })
        return
      }
      switch (n) {
        case "escape":
        case "tab":
          setFocus("list")
          break
        case "j":
        case "down":
          setTraceSel((i) => Math.min(i + 1, traces.length - 1))
          break
        case "k":
        case "up":
          setTraceSel((i) => Math.max(i - 1, 0))
          break
        case "space":
          if (cur && traceCur)
            dispatch("togglePresetTrace", { preset_id: cur.id, trace_id: traceCur.id })
          break
        case "a":
          if (cur) setModal({ kind: "addTrace", presetId: cur.id })
          break
        case "e":
          if (cur && traceCur)
            setModal({ kind: "editTrace", presetId: cur.id, traceId: traceCur.id, text: traceCur.text })
          break
        case "l":
          if (cur) setModal({ kind: "limits", presetId: cur.id, draft: limitsDraft(cur.limits) })
          break
      }
      return
    }

    // list focus
    if (key.ctrl && n === "d") {
      if (cur) setModal({ kind: "confirmPreset", id: cur.id, name: cur.name })
      return
    }
    switch (n) {
      case "escape":
        onBack()
        break
      case "j":
      case "down":
        setSel((i) => Math.min(i + 1, presets.length - 1))
        break
      case "k":
      case "up":
        setSel((i) => Math.max(i - 1, 0))
        break
      case "return":
      case "tab":
        if (cur) {
          setTraceSel(0)
          setFocus("detail")
        }
        break
      case "n":
        setModal({ kind: "newPreset" })
        break
      case "r":
        if (cur) setModal({ kind: "rename", id: cur.id, name: cur.name })
        break
    }
  })

  return (
    <box flexDirection="column" flexGrow={1} backgroundColor={theme.bg}>
      <box backgroundColor={theme.bg} paddingLeft={1}>
        <text fg={theme.title}>Presets</text>
      </box>

      <box flexDirection="row" flexGrow={1}>
        <box
          border
          borderColor={focus === "list" ? theme.title : theme.border}
          backgroundColor={theme.bg}
          title={`Presets (${presets.length})`}
          titleColor={theme.title}
          width={36}
          flexDirection="column"
          padding={1}
        >
          {presets.length === 0 ? (
            <text fg={theme.dim}>No presets. n to add.</text>
          ) : (
            presets.map((p, i) => (
              <PresetRow key={p.id} preset={p} active={i === sel} />
            ))
          )}
        </box>

        <box
          border
          borderColor={focus === "detail" ? theme.title : theme.border}
          backgroundColor={theme.bg}
          title={cur ? `${cur.name} — traces` : "—"}
          titleColor={theme.title}
          flexGrow={1}
          flexBasis={0}
          flexDirection="column"
          padding={1}
        >
          {!cur ? (
            <text fg={theme.dim}>Select a preset.</text>
          ) : (
            <>
              {traces.length === 0 ? (
                <text fg={theme.dim}>No patterns. enter then a to add.</text>
              ) : (
                traces.map((t, i) => (
                  <TraceRow key={t.id} rtp={t} active={focus === "detail" && i === traceSel} />
                ))
              )}
              <text fg={theme.dim}>{`limits: keep ${cur.limits.keep} · time ${cur.limits.time}s · msgs ${cur.limits.msgs}`}</text>
            </>
          )}
        </box>
      </box>

      <box backgroundColor={theme.bg} paddingLeft={1}>
        <text fg={theme.dim}>
          {focus === "list"
            ? "j/k move · enter edit · n new · r rename · Ctrl+D delete · esc back"
            : "j/k move · space toggle · a add · e edit · l limits · Ctrl+D del · tab/esc back"}
        </text>
      </box>

      {modal.kind === "newPreset" && (
        <OverlayBox>
          <TextField
            label="New preset — name:"
            onSubmit={(v) => {
              if (v.trim() !== "") dispatch("createPreset", { name: v })
              setModal({ kind: "none" })
            }}
          />
        </OverlayBox>
      )}

      {modal.kind === "rename" && (
        <OverlayBox>
          <TextField
            label="Rename preset:"
            initial={modal.name}
            onSubmit={(v) => {
              if (v.trim() !== "") dispatch("updatePreset", { id: modal.id, name: v })
              setModal({ kind: "none" })
            }}
          />
        </OverlayBox>
      )}

      {modal.kind === "addTrace" && (
        <OverlayBox>
          <TextField
            label="New RTP:"
            hint="redbug spec, e.g. lists:seq/2 -> return"
            onSubmit={(v) => {
              if (v.trim() !== "") dispatch("addPresetTrace", { preset_id: modal.presetId, text: v })
              setModal({ kind: "none" })
            }}
          />
        </OverlayBox>
      )}

      {modal.kind === "editTrace" && (
        <OverlayBox>
          <TextField
            label="Edit RTP:"
            hint="redbug spec, e.g. lists:seq/2 -> return"
            initial={modal.text}
            onSubmit={(v) => {
              dispatch("updatePresetTrace", {
                preset_id: modal.presetId,
                trace_id: modal.traceId,
                text: v
              })
              setModal({ kind: "none" })
            }}
          />
        </OverlayBox>
      )}

      {modal.kind === "limits" && (
        <OverlayBox>
          <TextField
            label="Limits — keep time msgs (space-separated):"
            initial={modal.draft}
            onSubmit={(v) => {
              const p = parseLimits(v)
              if (p) dispatch("updatePresetLimits", { preset_id: modal.presetId, ...p })
              setModal({ kind: "none" })
            }}
          />
        </OverlayBox>
      )}

      {modal.kind === "confirmPreset" && (
        <OverlayBox>
          <text fg={theme.fg}>{`Delete preset "${modal.name}"?`}</text>
          <text fg={theme.dim}>y = yes · n/Esc = no</text>
        </OverlayBox>
      )}

      {modal.kind === "confirmTrace" && (
        <OverlayBox>
          <text fg={theme.fg}>Delete this pattern?</text>
          <text fg={theme.dim}>y = yes · n/Esc = no</text>
        </OverlayBox>
      )}
    </box>
  )
}

function PresetRow({ preset, active }: { preset: Preset; active: boolean }) {
  const bg = active ? theme.selBg : theme.bg
  const fg = active ? theme.selFg : theme.fg
  return (
    <box backgroundColor={bg} flexDirection="row">
      <text bg={bg} fg={fg}>{preset.name}</text>
      <text bg={bg} fg={theme.dim}>{`  (${preset.traces.length})`}</text>
    </box>
  )
}

function TraceRow({ rtp, active }: { rtp: Rtp; active: boolean }) {
  const bg = active ? theme.selBg : theme.bg
  const fg = active ? theme.selFg : theme.fg
  const mark = rtp.enabled ? "[x]" : "[ ]"
  const markColor = rtp.enabled ? theme.on : theme.dim
  return (
    <box backgroundColor={bg} flexDirection="row">
      <text bg={bg} fg={markColor}>{`${mark} `}</text>
      <text bg={bg} fg={rtp.enabled ? fg : theme.dim}>{rtp.text}</text>
    </box>
  )
}

function OverlayBox({ children }: { children: ReactNode }) {
  return (
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

function limitsDraft(l: Server.Schema.Limits): string {
  return `${l.keep} ${l.time} ${l.msgs}`
}

function parseLimits(s: string): { keep: number; time: number; msgs: number } | null {
  const parts = s.trim().split(/\s+/).map(Number)
  if (parts.length !== 3 || parts.some((x) => !Number.isFinite(x) || x < 0)) return null
  return { keep: parts[0], time: parts[1], msgs: parts[2] }
}
