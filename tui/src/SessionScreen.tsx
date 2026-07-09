/** @jsxImportSource @opentui/react */
import { useEffect, useMemo, useRef, useState } from "react"
import { useKeyboard, useRenderer } from "@opentui/react"
import type { StoreProxy } from "@musubi/react"
import type { TabSelectRenderable } from "@opentui/core"

import { sessionRoot, dispatcher, useMusubiRoot, useMusubiSnapshot } from "./musubi"
import { DEFAULT_LIMITS, formatLimits, parseLimits } from "./limits"
import { theme, PANEL_BORDER } from "./theme"
import { Flash, ErrorDetailOverlay, RootGate, StatusBar, useSpinner } from "./ui"
import { ConsoleTab } from "./ConsoleTab"

import { parseSort, processEvents, sparkline, openInEditor } from "./sessionHelpers"
import { COL, SORT_OPTS, GROUP_CYCLE, ALL_COLS } from "./sessionTypes"
import type { Sort, Filter, FilterScope, GroupKey, Focus, Cols, DRow } from "./sessionTypes"
import type { Rtp, TraceEvent } from "./types"

import { ColumnHeader, EventRow } from "./SessionEvents"
import { DetailPane } from "./SessionDetail"
import {
  FilterOverlay, SortOverlay, LimitsOverlay,
  SessionHelpOverlay, ConfirmExitOverlay,
  ZoomOverlay
} from "./SessionOverlays"
import { ConfirmOverlay } from "./ConfirmOverlay"
import { EditorOverlay } from "./SessionEditor"
import type { RtpModal, ImportState } from "./SessionEditor"
import { SessionStat } from "./SessionStatus"
import { useSessionLiveness } from "./useSessionLiveness"

type SessionStore = StoreProxy<"Server.Stores.SessionRoot", Musubi.Stores>

type Overlay = "none" | "sort" | "filter" | "editor" | "limits" | "help" | "errorDetail" | "confirmExit" | "confirmDelete"

export function SessionScreen({
  nodeId,
  sessionId,
  settings,
  presets,
  onBack
}: {
  nodeId: string
  sessionId: string
  settings?: Server.Schema.Settings
  presets?: Server.Schema.Preset[]
  onBack: () => void
}) {
  const root = useMusubiRoot(sessionRoot(nodeId, sessionId))
  return (
    <RootGate root={root} loading="Loading session…" errorLabel="Session">
      {(store) => (
        <SessionView
          store={store}
          nodeId={nodeId}
          sessionId={sessionId}
          settings={settings}
          presets={presets ?? []}
          onBack={onBack}
        />
      )}
    </RootGate>
  )
}

function SessionView({
  store,
  nodeId,
  sessionId,
  settings,
  presets,
  onBack
}: {
  store: SessionStore
  nodeId: string
  sessionId: string
  settings?: Server.Schema.Settings
  presets: Server.Schema.Preset[]
  onBack: () => void
}) {
  const [tab, setTab] = useState<"events" | "console">("events")
  const tabRef = useRef<TabSelectRenderable>(null)
  useEffect(() => {
    tabRef.current?.setSelectedIndex(tab === "events" ? 0 : 1)
  }, [tab])
  const snap = useMusubiSnapshot(store)
  const cols = settings?.columns ?? ALL_COLS
  const renderer = useRenderer()
  const traces = (snap?.traces ?? []) as Rtp[]
  const events = (snap?.events ?? []) as TraceEvent[]
  const limits = snap?.limits ?? DEFAULT_LIMITS
  const running = snap?.status === "running"
  const dirty = snap?.dirty === true
  const error = snap?.error ?? null

  const nodeStatus = snap?.node_status ?? "idle"
  const nodeSpin = useSpinner(nodeStatus === "connecting")

  const endedLimit = (snap?.ended ?? null) as "time" | "msgs" | null
  const sessionState: "connecting" | "unreachable" | "idle" | "running" | "ended" | "failed" =
    nodeStatus === "error" ? "unreachable"
    : nodeStatus !== "connected" ? "connecting"
    : running ? "running"
    : endedLimit ? "ended"
    : error ? "failed"
    : "idle"

  // Liveness + sparkline tracking
  const { remainingSec, buckets } = useSessionLiveness(running, events, limits.time)

  const [sort, setSort] = useState<Sort>(() => parseSort(settings?.default_sort))
  const [filter, setFilter] = useState<Filter | null>(null)
  const [filterScope, setFilterScope] = useState<FilterScope>("all")
  const [filterDraft, setFilterDraft] = useState("")
  const [filterFocus, setFilterFocus] = useState<"query" | "scope">("query")
  const [group, setGroup] = useState<GroupKey>("none")

  const [sel, setSel] = useState(0)
  const [detailOpen, setDetailOpen] = useState(false)
  const [focus, setFocus] = useState<Focus>("list")
  const [, setDetailScroll] = useState(0)
  const [zoom, setZoom] = useState(false)

  const [overlay, setOverlay] = useState<Overlay>("none")
  const [sortIdx, setSortIdx] = useState(0)
  const [limitsDraft, setLimitsDraft] = useState("")

  // S3 editor overlay state
  const [rtpSel, setRtpSel] = useState(0)
  const [rtpModal, setRtpModal] = useState<RtpModal>({ kind: "none" })
  const [editingLimits, setEditingLimits] = useState(false)
  const [importState, setImportState] = useState<ImportState | null>(null)

  // Applied traces baseline
  const [appliedTraces, setAppliedTraces] = useState<Rtp[]>(() => traces)
  const prevDirty = useRef(dirty)
  if (prevDirty.current === true && dirty === false) {
    if (appliedTraces !== traces) setAppliedTraces(traces)
  }
  prevDirty.current = dirty

  const { rows, count } = useMemo(
    () => processEvents(events, filter, sort, group),
    [events, filter, sort, group]
  )

  const pidWidth = useMemo(
    () => events.reduce((m, e) => Math.max(m, e.pid.length), COL.pid),
    [events]
  )

  const selClamped = Math.min(sel, Math.max(0, count - 1))
  const selectedEvent =
    rows.find((r): r is Extract<DRow, { type: "event" }> => r.type === "event" && r.sidx === selClamped)
      ?.ev ?? null

  const dispatch = dispatcher(store)

  const moveSel = (delta: number) => {
    const next = sel + delta
    setSel(next < 0 ? count - 1 : next >= count ? 0 : next)
    setDetailScroll(0)
  }

  const exportSelected = () => {
    if (!selectedEvent) return
    void openInEditor(renderer, selectedEvent)
  }

  useKeyboard((key) => {
    const n = key.name

    if (tab === "console") return

    if (overlay === "filter") {
      if (n === "escape") setOverlay("none")
      else if (n === "tab") setFilterFocus((f) => (f === "query" ? "scope" : "query"))
      return
    }

    if (overlay === "sort") return // DialogSelect owns all keys

    if (overlay === "limits") {
      if (n === "escape") setOverlay("none")
      return
    }

    if (overlay === "help") { setOverlay("none"); return }
    if (overlay === "errorDetail") {
      if (n === "escape" || n === "e") setOverlay("none")
      return
    }

    if (overlay === "confirmExit") {
      if (n === "y") onBack()
      else if (n === "n" || n === "escape") setOverlay("none")
      return
    }

    if (overlay === "confirmDelete") {
      if (n === "y" && selectedEvent) dispatch("deleteEvent", { id: selectedEvent.id })
      if (n === "y" || n === "n" || n === "escape") setOverlay("none")
      return
    }

    if (overlay === "editor") {
      handleEditorKeys(key)
      return
    }

    if (zoom) {
      if (n === "escape" || n === "z") setZoom(false)
      else if (n === "j" || n === "down") setDetailScroll((s) => s + 1)
      else if (n === "k" || n === "up") setDetailScroll((s) => Math.max(0, s - 1))
      else if (n === "v") exportSelected()
      return
    }

    if (detailOpen && focus === "detail") {
      if (key.ctrl && (n === "j" || n === "down")) return moveSel(1)
      if (key.ctrl && (n === "k" || n === "up")) return moveSel(-1)
      switch (n) {
        case "escape": setDetailOpen(false); setFocus("list"); break
        case "tab": setFocus("list"); break
        case "j": case "down": setDetailScroll((s) => s + 1); break
        case "k": case "up": setDetailScroll((s) => Math.max(0, s - 1)); break
        case "z": if (selectedEvent) setZoom(true); break
        case "v": exportSelected(); break
      }
      return
    }

    // list focus
    if (key.ctrl) {
      if (n === "l") return dispatch("clearEvents")
      if (n === "s") return dispatch("applyRestart")
      if (n === "d" && selectedEvent) return dispatch("deleteEvent", { id: selectedEvent.id })
      if (detailOpen && (n === "j" || n === "down")) return moveSel(1)
      if (detailOpen && (n === "k" || n === "up")) return moveSel(-1)
      return
    }

    // [ / ] toggle between Events ⇄ Console tabs
    if (n === "]" || n === "[") {
      setTab((t) => (t === "events" ? "console" : "events"))
      return
    }

    switch (n) {
      case "escape":
        if (detailOpen) setDetailOpen(false)
        else if (sessionState === "running") setOverlay("confirmExit")
        else onBack()
        break
      case "j": case "down": moveSel(1); break
      case "k": case "up": moveSel(-1); break
      case "return":
        if (selectedEvent) { setDetailOpen(true); setFocus("detail"); setDetailScroll(0) }
        break
      case "tab": if (detailOpen) setFocus("detail"); break
      case "o":
        setSortIdx(Math.max(0, SORT_OPTS.findIndex((s) => s.key === sort.key && s.dir === sort.dir)))
        setOverlay("sort")
        break
      case "/":
        setFilterDraft(filter?.query ?? "")
        setFilterScope(filter?.scope ?? "all")
        setFilterFocus("query")
        setOverlay("filter")
        break
      case "g": setGroup((g) => GROUP_CYCLE[(GROUP_CYCLE.indexOf(g) + 1) % GROUP_CYCLE.length]); break
      case "l": setLimitsDraft(formatLimits(limits)); setOverlay("limits"); break
      case "z": if (selectedEvent) { setDetailOpen(true); setZoom(true) }; break
      case "t": setRtpSel(0); setOverlay("editor"); break
      case "v": exportSelected(); break
      case "space":
        if (sessionState === "unreachable") dispatch("reconnect")
        else if (sessionState === "idle" || sessionState === "ended" || sessionState === "failed") dispatch("startTrace")
        break
      case "x": if (sessionState === "running") dispatch("stopTrace"); break
      case "e": if (error?.detail) setOverlay("errorDetail"); break
      case "d": if (selectedEvent) setOverlay("confirmDelete"); break
      case "?": setOverlay("help"); break
    }
  })

  function handleEditorKeys(key: { name: string; ctrl: boolean }) {
    const n = key.name

    if (rtpModal.kind === "confirmTraceDelete") {
      if (n === "y") { dispatch("deleteTrace", { trace_id: (rtpModal as any).id }); setRtpModal({ kind: "none" }) }
      else if (n === "n" || n === "escape") setRtpModal({ kind: "none" })
      return
    }
    if (rtpModal.kind === "savePresetOverwrite") {
      if (n === "y") { dispatch("saveAsPreset", { name: (rtpModal as any).name }); setRtpModal({ kind: "none" }) }
      else if (n === "n" || n === "escape") setRtpModal({ kind: "none" })
      return
    }

    if (importState) {
      if (importState.phase === "traces") {
        const p = presets[importState.presetIdx]
        if (n === "escape" || n === "tab") { setImportState({ ...importState, phase: "pick" }); return }
        if (n === "enter" || n === "return") {
          if (importState.selected.size === 0) return
          const existing = new Set(traces.map((t) => t.text))
          for (let j = 0; j < p.traces.length; j++) {
            if (importState.selected.has(j) && !existing.has(p.traces[j].text)) {
              dispatch("addTrace", { text: p.traces[j].text })
            }
          }
          setImportState(null)
          return
        }
        if (n === "a") {
          const allSelected = importState.selected.size === p.traces.length
          setImportState({ ...importState, selected: allSelected ? new Set() : new Set(p.traces.map((_, j) => j)) })
          return
        }
        if (n === "space") {
          const next = new Set(importState.selected)
          if (next.has(importState.traceSel)) next.delete(importState.traceSel)
          else next.add(importState.traceSel)
          setImportState({ ...importState, selected: next })
          return
        }
        if (n === "j" || n === "down") {
          setImportState({ ...importState, traceSel: Math.min(importState.traceSel + 1, p.traces.length - 1) })
          return
        }
        if (n === "k" || n === "up") {
          setImportState({ ...importState, traceSel: Math.max(importState.traceSel - 1, 0) })
          return
        }
      } else {
        if (n === "escape") { setImportState(null); return }
        if (n === "enter" || n === "return") {
          const p = presets[importState.presetIdx]
          setImportState({ phase: "traces", presetIdx: importState.presetIdx, selected: new Set(p.traces.map((_, j) => j)), traceSel: 0 })
          return
        }
        if (n === "j" || n === "down") {
          setImportState({ ...importState, presetIdx: Math.min(importState.presetIdx + 1, presets.length - 1) })
          return
        }
        if (n === "k" || n === "up") {
          setImportState({ ...importState, presetIdx: Math.max(importState.presetIdx - 1, 0) })
          return
        }
      }
      return
    }

    if (rtpModal.kind !== "none") {
      if (n === "escape") setRtpModal({ kind: "none" })
      return
    }
    if (key.ctrl && n === "w") { setRtpModal({ kind: "savePreset" }); return }
    if (editingLimits) {
      if (n === "escape") setEditingLimits(false)
      return
    }
    if (key.ctrl && n === "d" && traces[rtpSel]) {
      dispatch("deleteTrace", { trace_id: traces[rtpSel].id })
      return
    }
    switch (n) {
      case "escape": setOverlay("none"); setImportState(null); break
      case "j": case "down":
        setRtpSel((i) => (traces.length === 0 ? 0 : (i + 1 >= traces.length ? 0 : i + 1)))
        break
      case "k": case "up":
        setRtpSel((i) => (i <= 0 ? Math.max(0, traces.length - 1) : i - 1))
        break
      case "space": if (traces[rtpSel]) dispatch("toggleTrace", { trace_id: traces[rtpSel].id }); break
      case "n": setRtpModal({ kind: "add" }); break
      case "e": if (traces[rtpSel]) setRtpModal({ kind: "edit", id: traces[rtpSel].id, text: traces[rtpSel].text }); break
      case "d": if (traces[rtpSel]) setRtpModal({ kind: "confirmTraceDelete", id: traces[rtpSel].id }); break
      case "l": setEditingLimits((v) => !v); if (!editingLimits) setLimitsDraft(formatLimits(limits)); break
      case "i":
        if (presets.length > 0) setImportState({ phase: "pick", presetIdx: 0, selected: new Set(), traceSel: 0 })
        break
    }
  }

  const eventsBorderColor =
    nodeStatus === "error" ? theme.error
    : nodeStatus === "connecting" ? theme.warning
    : focus === "list" ? theme.borderActive
    : theme.borderSubtle

  const spaceAction =
    sessionState === "unreachable" ? "space retry"
    : sessionState === "idle" ? "space start"
    : sessionState === "ended" || sessionState === "failed" ? "space restart"
    : sessionState === "running" ? (dirty ? "x stop · ⌃S apply" : "x stop")
    : ""
  const eventsHints = ["j/k move", "enter detail", "t traces", "d del", spaceAction, "[/] tabs", "? help", "esc back"]
    .filter((s) => s !== "")
    .join(" · ")

  return (
    <box flexDirection="column" flexGrow={1} backgroundColor={theme.background}>
      <box backgroundColor={theme.background} paddingLeft={1} paddingRight={1} paddingTop={1} flexDirection="row">
        <text fg={theme.text}>{snap?.name ?? "session"}</text>
        <box flexGrow={1} backgroundColor={theme.background} />
        <tab-select
          ref={tabRef}
          width={18}
          tabWidth={9}
          showDescription={false}
          showScrollArrows={false}
          showUnderline={false}
          options={[
            { name: "Traces", description: "" },
            { name: "Console", description: "" }
          ]}
          backgroundColor={theme.background}
          textColor={theme.textMuted}
          selectedBackgroundColor={theme.background}
          selectedTextColor={theme.primary}
        />
      </box>

      {tab === "console" ? (
        <ConsoleTab
          nodeId={nodeId}
          sessionId={sessionId}
          nodeStatus={nodeStatus}
          onSwitchToEvents={() => setTab("events")}
          onBack={onBack}
        />
      ) : (
      <>
      {!zoom && (
      <box flexDirection="row" flexGrow={1}>
        <box
          border
          borderStyle={PANEL_BORDER}
          borderColor={eventsBorderColor}
          title={
            detailOpen
              ? undefined
              : ` Sort:${sort.key}${sort.dir === "asc" ? "↑" : "↓"} · Filter:${filter ? `${filter.scope}/${filter.query}` : "-"} · Group:${group} `
          }
          titleAlignment="right"
          titleColor={theme.textMuted}
          backgroundColor={theme.background}
          flexGrow={1}
          flexBasis={0}
          flexDirection="column"
          padding={1}
        >
          <ColumnHeader cols={cols} pidWidth={pidWidth} />
          {rows.length === 0 ? (
            <text fg={theme.textMuted}>No events yet · space to start</text>
          ) : (
            <scrollbox scrollY stickyStart="top" flexGrow={1}>
              {(() => {
                const shown = rows.slice(0, 300)
                const ditto = group === "none" && !filter?.query
                return shown.map((row, i) => {
                  if (row.type === "header")
                    return <text key={row.key} fg={theme.textMuted}>{`${row.label} · ${row.count}`}</text>
                  const prev = i > 0 ? shown[i - 1] : null
                  const prevEv = prev && prev.type === "event" ? prev.ev : null
                  return (
                    <EventRow
                      key={row.key}
                      ev={row.ev}
                      active={row.sidx === selClamped}
                      filter={filter}
                      cols={cols}
                      pidWidth={pidWidth}
                      dittoName={ditto && !!prevEv && !!row.ev.name && prevEv.name === row.ev.name}
                      dittoPid={ditto && !!prevEv && prevEv.pid === row.ev.pid}
                    />
                  )
                })
              })()}
            </scrollbox>
          )}
        </box>

        {detailOpen && !zoom && selectedEvent && (
          <DetailPane ev={selectedEvent} focused={focus === "detail"} />
        )}
      </box>
      )}

      {error && <Flash error={error} />}

      <StatusBar
        statChip={<SessionStat state={sessionState} nodeSpin={nodeSpin} endedLimit={endedLimit} dirty={dirty} spark={running && buckets.some((v) => v > 0) ? sparkline(buckets) : ""} count={events.length} limits={limits} remainingSec={remainingSec} />}
        hints={eventsHints}
      />

      {overlay === "errorDetail" && error && (
        <ErrorDetailOverlay body={error.detail ?? error.message} />
      )}

      {overlay === "confirmExit" && <ConfirmExitOverlay dirty={dirty} />}
      {overlay === "confirmDelete" && <ConfirmOverlay question="Delete this event?" />}
      {overlay === "help" && <SessionHelpOverlay />}

      {overlay === "filter" && (
        <FilterOverlay
          filterScope={filterScope}
          filterDraft={filterDraft}
          filterFocus={filterFocus}
          onFilterScope={setFilterScope}
          onFilterDraft={setFilterDraft}
          onFilterFocus={setFilterFocus}
          onApply={(f) => { setFilter(f); setOverlay("none") }}
          onClose={() => setOverlay("none")}
        />
      )}

      {overlay === "sort" && (
        <SortOverlay
          sortIdx={sortIdx}
          onSelect={(item) => {
            const s = SORT_OPTS.find((x) => `${x.key}_${x.dir}` === item.id)
            if (s) setSort(s)
            setOverlay("none")
          }}
          onClose={() => setOverlay("none")}
        />
      )}

      {overlay === "limits" && (
        <LimitsOverlay
          limitsDraft={limitsDraft}
          onLimitsDraft={setLimitsDraft}
          onApply={() => {
            const p = parseLimits(limitsDraft)
            if (p) dispatch("updateLimits", p)
            setOverlay("none")
          }}
          onClose={() => setOverlay("none")}
        />
      )}

      {overlay === "editor" && (
        <EditorOverlay
          traces={traces}
          rtpSel={rtpSel}
          rtpModal={rtpModal}
          editingLimits={editingLimits}
          limitsDraft={limitsDraft}
          importState={importState}
          presets={presets}
          appliedTraces={appliedTraces}
          running={running}
          dirty={dirty}
          limits={limits}
          onRtpSel={setRtpSel}
          onRtpModal={setRtpModal}
          onEditingLimits={setEditingLimits}
          onLimitsDraft={setLimitsDraft}
          onImportState={setImportState}
          dispatch={(action, payload) => dispatch(action as any, payload)}
        />
      )}

      {zoom && selectedEvent && <ZoomOverlay ev={selectedEvent} />}
      </>
      )}
    </box>
  )
}
