/** @jsxImportSource @opentui/react */
import { useState } from "react"
import { useKeyboard } from "@opentui/react"
import type { StoreProxy } from "@musubi/react"

import { PRESETS_ROOT, dispatcher, useMusubiRoot, useMusubiSnapshot } from "./musubi"
import { formatLimits, parseLimits } from "./limits"
import { theme } from "./theme"
import { Header, HelpOverlay, Overlay, RootGate, StatusBar, TextField } from "./ui"

type PresetsStore = StoreProxy<"Server.Stores.PresetsRoot", Musubi.Stores>
type PresetProxy = StoreProxy<"Server.Stores.PresetStore", Musubi.Stores>
type Preset = Server.Schema.Preset
type Rtp = Server.Schema.Rtp

type Focus = "list" | "detail"

type Modal =
  | { kind: "none" }
  | { kind: "help" }
  | { kind: "newPreset" }
  | { kind: "rename"; id: string; name: string }
  | { kind: "addTrace"; presetId: string }
  | { kind: "editTrace"; presetId: string; traceId: string; text: string }
  | { kind: "limits"; presetId: string; draft: string }
  | { kind: "confirmPreset"; id: string; name: string }
  | { kind: "confirmTrace"; presetId: string; traceId: string }

export function PresetManager({ onBack }: { onBack: () => void }) {
  const root = useMusubiRoot(PRESETS_ROOT)
  return (
    <RootGate root={root} loading="Loading presets…" errorLabel="Presets">
      {(store) => <PresetView store={store} onBack={onBack} />}
    </RootGate>
  )
}

function PresetView({ store, onBack }: { store: PresetsStore; onBack: () => void }) {
  const snap = useMusubiSnapshot(store)
  const presets = (snap?.presets ?? []) as Preset[]

  const [sel, setSel] = useState(0)
  const [focus, setFocus] = useState<Focus>("list")
  const [traceSel, setTraceSel] = useState(0)
  const [modal, setModal] = useState<Modal>({ kind: "none" })

  const cur = presets[Math.min(sel, presets.length - 1)] ?? null
  const traces = (cur?.traces ?? []) as Rtp[]
  const traceCur = traces[Math.min(traceSel, traces.length - 1)] ?? null

  // createPreset is the only root command; preset-scoped mutations dispatch on
  // the matching child proxy (store path is the routing — no preset_id payload).
  const createPreset = dispatcher(store)
  const presetProxyById = (id: string): PresetProxy | undefined => {
    const i = presets.findIndex((p) => p.id === id)
    return i >= 0 ? store.presets[i] : undefined
  }

  useKeyboard((key) => {
    const n = key.name

    if (modal.kind !== "none") {
      if (modal.kind === "help") {
        setModal({ kind: "none" })
        return
      }
      if (modal.kind === "confirmPreset") {
        if (n === "y") {
          const p = presetProxyById(modal.id)
          if (p) dispatcher(p)("deletePreset")
          setModal({ kind: "none" })
          setSel((i) => Math.max(0, i - 1))
        } else if (n === "n" || n === "escape") setModal({ kind: "none" })
        return
      }
      if (modal.kind === "confirmTrace") {
        if (n === "y") {
          const p = presetProxyById(modal.presetId)
          if (p) dispatcher(p)("deletePresetTrace", { trace_id: modal.traceId })
          setModal({ kind: "none" })
        } else if (n === "n" || n === "escape") setModal({ kind: "none" })
        return
      }
      if (n === "escape") setModal({ kind: "none" })
      return
    }

    if (n === "?") {
      setModal({ kind: "help" })
      return
    }

    if (focus === "detail") {
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
          if (cur && traceCur) {
            const p = presetProxyById(cur.id)
            if (p) dispatcher(p)("togglePresetTrace", { trace_id: traceCur.id })
          }
          break
        case "n":
          if (cur) setModal({ kind: "addTrace", presetId: cur.id })
          break
        case "e":
          if (cur && traceCur)
            setModal({ kind: "editTrace", presetId: cur.id, traceId: traceCur.id, text: traceCur.text })
          break
        case "l":
          if (cur) setModal({ kind: "limits", presetId: cur.id, draft: formatLimits(cur.limits) })
          break
        case "d":
          if (cur && traceCur)
            setModal({ kind: "confirmTrace", presetId: cur.id, traceId: traceCur.id })
          break
      }
      return
    }

    // list focus
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
      case "d":
        if (cur) setModal({ kind: "confirmPreset", id: cur.id, name: cur.name })
        break
    }
  })

  return (
    <box flexDirection="column" flexGrow={1} backgroundColor={theme.bg}>
      <Header title="Presets" />

      <box flexDirection="row" flexGrow={1} gap={1}>
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
            <text fg={theme.dim}>No presets yet · n to add</text>
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
            <text fg={theme.dim}>Select a preset</text>
          ) : (
            <>
              {traces.length === 0 ? (
                <text fg={theme.dim}>No patterns yet · enter, then a to add</text>
              ) : (
                traces.map((t, i) => (
                  <TraceRow key={t.id} rtp={t} active={focus === "detail" && i === traceSel} />
                ))
              )}
              <text fg={theme.dim} marginTop={1}>{`limits: keep ${cur.limits.keep} · time ${cur.limits.time}s · msgs ${cur.limits.msgs}`}</text>
            </>
          )}
        </box>
      </box>

      <StatusBar
        statusText={`${presets.length} presets`}
        hints={
          focus === "list"
            ? "j/k move · enter edit · n new · ? help · esc back"
            : "j/k move · space toggle · n add · ? help · tab/esc back"
        }
      />

      {modal.kind === "help" && (
        <HelpOverlay
          title="presets"
          sections={[
            {
              title: "list",
              lines: [
                ["j / k", "move"],
                ["enter / tab", "edit (focus traces)"],
                ["n", "new preset"],
                ["r", "rename"],
                ["d", "delete preset"]
              ]
            },
            {
              title: "traces (detail focus)",
              lines: [
                ["j / k", "move"],
                ["space", "toggle pattern"],
                ["n", "add pattern"],
                ["e", "edit pattern"],
                ["l", "limits"],
                ["d", "delete pattern"],
                ["tab / esc", "back to list"]
              ]
            }
          ]}
        />
      )}

      {modal.kind === "newPreset" && (
        <Overlay>
          <TextField
            label="New preset — name:"
            onSubmit={(v) => {
              if (v.trim() !== "") createPreset("createPreset", { name: v })
              setModal({ kind: "none" })
            }}
          />
        </Overlay>
      )}

      {modal.kind === "rename" && (
        <Overlay>
          <TextField
            label="Rename preset:"
            initial={modal.name}
            onSubmit={(v) => {
              const p = presetProxyById(modal.id)
              if (v.trim() !== "" && p) dispatcher(p)("updatePreset", { name: v })
              setModal({ kind: "none" })
            }}
          />
        </Overlay>
      )}

      {modal.kind === "addTrace" && (
        <Overlay>
          <TextField
            label="New RTP:"
            hint="redbug spec, e.g. lists:seq/2 -> return"
            onSubmit={(v) => {
              const p = presetProxyById(modal.presetId)
              if (v.trim() !== "" && p) dispatcher(p)("addPresetTrace", { text: v })
              setModal({ kind: "none" })
            }}
          />
        </Overlay>
      )}

      {modal.kind === "editTrace" && (
        <Overlay>
          <TextField
            label="Edit RTP:"
            hint="redbug spec, e.g. lists:seq/2 -> return"
            initial={modal.text}
            onSubmit={(v) => {
              const p = presetProxyById(modal.presetId)
              if (p) dispatcher(p)("updatePresetTrace", { trace_id: modal.traceId, text: v })
              setModal({ kind: "none" })
            }}
          />
        </Overlay>
      )}

      {modal.kind === "limits" && (
        <Overlay>
          <TextField
            label="Limits — keep time msgs (space-separated):"
            initial={modal.draft}
            onSubmit={(v) => {
              const limits = parseLimits(v)
              const proxy = presetProxyById(modal.presetId)
              if (limits && proxy) dispatcher(proxy)("updatePresetLimits", limits)
              setModal({ kind: "none" })
            }}
          />
        </Overlay>
      )}

      {modal.kind === "confirmPreset" && (
        <Overlay>
          <text fg={theme.fg}>{`Delete preset "${modal.name}"?`}</text>
          <text fg={theme.dim} marginTop={1}>y = yes · n/Esc = no</text>
        </Overlay>
      )}

      {modal.kind === "confirmTrace" && (
        <Overlay>
          <text fg={theme.fg}>Delete this pattern?</text>
          <text fg={theme.dim} marginTop={1}>y = yes · n/Esc = no</text>
        </Overlay>
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

