/** @jsxImportSource @opentui/react */
import { useEffect, useMemo, useRef, useState } from "react"
import { useKeyboard, useRenderer } from "@opentui/react"
import type { StoreProxy } from "@musubi/react"
import type { TabSelectRenderable } from "@opentui/core"

import { sessionRoot, dispatcher, useMusubiRoot, useMusubiSnapshot } from "./musubi"
import { DEFAULT_LIMITS, formatLimits, parseLimits } from "./limits"
import { theme, kindColor, PANEL_BORDER } from "./theme"
import { Chip, ErrorDetailOverlay, Flash, HelpOverlay, Overlay, RootGate, StatusBar, TextField, fit, useSpinner } from "./ui"
import { ConsoleTab } from "./ConsoleTab"
import { editInEditor } from "./editor"
import { elixirStyle, tsClient } from "./treesitter"

type SessionStore = StoreProxy<"Server.Stores.SessionRoot", Musubi.Stores>
type Rtp = Server.Schema.Rtp
type TraceEvent = Server.Schema.TraceEvent

type SortKey = "ts" | "kind" | "pid" | "mfa"
type SortDir = "asc" | "desc"
type Sort = { key: SortKey; dir: SortDir }
type FilterScope = "all" | "mfa" | "pid" | "info"
type Filter = { scope: FilterScope; query: string }
type GroupKey = "none" | "pid" | "mfa" | "kind"

type Overlay = "none" | "sort" | "filter" | "editor" | "limits" | "help" | "errorDetail" | "confirmExit" | "confirmDelete"
type Focus = "list" | "detail"
type Cols = { name: boolean; pid: boolean; mfa: boolean; info: boolean }

const ALL_COLS: Cols = { name: true, pid: true, mfa: true, info: true }

type DRow =
  | { type: "header"; key: string; label: string; count: number }
  | { type: "event"; key: string; ev: TraceEvent; sidx: number }

const kindSym: Record<string, string> = {
  call: "↓",
  retn: "↑",
  send: "→",
  recv: "←",
  restart: "·"
}

const SORT_OPTS: Sort[] = [
  { key: "ts", dir: "desc" },
  { key: "ts", dir: "asc" },
  { key: "kind", dir: "asc" },
  { key: "kind", dir: "desc" },
  { key: "pid", dir: "asc" },
  { key: "mfa", dir: "asc" }
]

const FILTER_SCOPES: FilterScope[] = ["all", "mfa", "pid", "info"]
const GROUP_CYCLE: GroupKey[] = ["none", "pid", "mfa", "kind"]

// Cheat-sheet shown in the trace editor: redbug RTP patterns in Elixir syntax.
const RTP_EXAMPLES: [string, string][] = [
  ["Enum.map/2 -> return", "call args + return value"],
  ["MyMod.func -> return;stack", "+ call stack"],
  ["Demo.tick when '$1' > 100 -> return", "guard on 1st arg"],
  ["Enum.map/2 · MyMod._ · MyMod", "arity · any fun · whole module"]
]

const COL = { ts: 12, k: 3, name: 16, pid: 11, mfa: 22, info: 44 }
const COLGAP = 2
const SPARK_N = 12
const SPARK_RAMP = "▁▂▃▄▅▆▇█"

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
  // tab-select is display-only (not focused, so it never steals keys from the
  // list or a console sub-picker). We drive switching via [ / ] in the keymaps
  // and keep the tab-select's highlight in sync imperatively.
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

  // Node connection status (auto-connected on entry by SessionRoot). Drives the
  // breadcrumb glyph and the connect-error banner in the events pane.
  const nodeStatus = snap?.node_status ?? "idle"
  const nodeSpin = useSpinner(nodeStatus === "connecting", "braille")

  // One consolidated lifecycle state the UI reads (folds node connection + trace
  // run + limit-stop into a single axis). Space is the sole "go" action per state
  // (retry/start/restart); x stops. See docs/screens/02-session-events.md.
  const endedLimit = (snap?.ended ?? null) as "time" | "msgs" | null
  const sessionState: "connecting" | "unreachable" | "idle" | "running" | "ended" | "failed" =
    nodeStatus === "error" ? "unreachable"
    : nodeStatus !== "connected" ? "connecting"
    : running ? "running"
    : endedLimit ? "ended"
    : error ? "failed"
    : "idle"

  // Liveness: a running session that traces nothing looks identical to a healthy
  // one. Track wall-clock age since the event buffer last grew and tick a clock
  // while running so the status reads ● live vs ◇ idle Ns (the "is my pattern
  // even matching?" signal). Age from a client timestamp, not ev.ts, so it is
  // independent of the id/ts encoding.
  const lastEventAt = useRef(Date.now())
  const seenMaxId = useRef(0)
  // ticks a rerender each second while running so the sparkline advances (the
  // value itself is unused; only the state update matters).
  const [nowTick, setNowTick] = useState(() => Date.now())
  const runningSince = useRef<number | null>(null)
  if (running && runningSince.current === null) runningSince.current = nowTick
  if (!running && runningSince.current !== null) runningSince.current = null
  const remainingSec =
    running && runningSince.current !== null ?
      Math.max(0, limits.time - Math.floor((nowTick - runningSince.current) / 1000))
    : null
  // Detect new events by max id, NOT array length: the buffer is capped (keep),
  // so once it fills, length stops growing while events still stream in. Length
  // would then falsely read as "idle".
  const curMaxId = events.reduce((m, e) => Math.max(m, Number(e.id)), seenMaxId.current)
  if (curMaxId > seenMaxId.current) {
    lastEventAt.current = Date.now()
    seenMaxId.current = curMaxId
  }

  // Rate sparkline: per-second arrivals over a rolling window. Counted by max
  // event id (monotonic) rather than buffer length, so it stays accurate once
  // the capped buffer starts evicting. Shares the one liveness timer.
  const eventsRef = useRef(events)
  eventsRef.current = events
  const lastMaxId = useRef(0)
  const buckets = useRef<number[]>(new Array(SPARK_N).fill(0))
  useEffect(() => {
    if (!running) {
      buckets.current = new Array(SPARK_N).fill(0)
      return
    }
    const id = setInterval(() => {
      let delta = 0
      let mx = lastMaxId.current
      for (const e of eventsRef.current) {
        const n = Number(e.id)
        if (n > lastMaxId.current) delta++
        if (n > mx) mx = n
      }
      lastMaxId.current = mx
      buckets.current = [...buckets.current.slice(1), delta]
      setNowTick(Date.now())
    }, 1000)
    return () => clearInterval(id)
  }, [running])
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
  const [rtpModal, setRtpModal] = useState<
    | { kind: "none" }
    | { kind: "add" }
    | { kind: "edit"; id: string; text: string }
    | { kind: "savePreset" }
    | { kind: "savePresetOverwrite"; name: string }
  >({ kind: "none" })
  const [editingLimits, setEditingLimits] = useState(false)
  const [importState, setImportState] = useState<{
    presetIdx: number
    selected: Set<number>
    focus: "list" | "traces"
    traceSel: number
  } | null>(null)

  // Track the trace list as it was when last applied, so per-row * markers
  // show which RTPs differ from the live (running) config. Initialised on
  // mount to whatever the server sends; refreshed after every successful
  // apply (dirty → clean transition).
  const [appliedTraces, setAppliedTraces] = useState<Rtp[]>(() => traces)
  const prevDirty = useRef(dirty)
  // dirty true → false means applyRestart just succeeded: reset the baseline.
  if (prevDirty.current === true && dirty === false) {
    if (appliedTraces !== traces) setAppliedTraces(traces)
  }
  prevDirty.current = dirty

  const { rows, count } = useMemo(
    () => processEvents(events, filter, sort, group),
    [events, filter, sort, group]
  )

  // widen the pid column to its longest value so pids are never truncated
  const pidWidth = useMemo(
    () => events.reduce((m, e) => Math.max(m, e.pid.length), COL.pid),
    [events]
  )

  const selClamped = Math.min(sel, Math.max(0, count - 1))
  const selectedEvent =
    rows.find((r): r is Extract<DRow, { type: "event" }> => r.type === "event" && r.sidx === selClamped)
      ?.ev ?? null

  const rtpCur = traces[Math.min(rtpSel, traces.length - 1)]

  const dispatch = dispatcher(store)

  const moveSel = (delta: number) => {
    setSel((i) => clamp(i + delta, 0, count - 1))
    setDetailScroll(0)
  }

  const exportSelected = () => {
    if (!selectedEvent) return
    void openInEditor(renderer, selectedEvent)
  }

  useKeyboard((key) => {
    const n = key.name

    // ConsoleTab registers its own keyboard handler; both stay mounted, so bail
    // here to avoid double-handling keys while the console tab is active.
    if (tab === "console") return

    if (overlay === "filter") {
      // Tab toggles focus between the query <input> and the scope <select>;
      // the scope <select> owns j/k while focused.
      if (n === "escape") setOverlay("none")
      else if (n === "tab") setFilterFocus((f) => (f === "query" ? "scope" : "query"))
      return
    }

    if (overlay === "sort") {
      // <select> owns j/k/return; only Esc closes the overlay
      if (n === "escape") setOverlay("none")
      return
    }

    if (overlay === "limits") {
      if (n === "escape") setOverlay("none")
      return
    }

    if (overlay === "help") {
      setOverlay("none")
      return
    }

    if (overlay === "errorDetail") {
      if (n === "escape" || n === "e") setOverlay("none")
      return
    }

    if (overlay === "confirmExit") {
      // y leaves the screen; unmounting the SessionRoot stops the trace server-side.
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
        case "escape":
          setDetailOpen(false)
          setFocus("list")
          break
        case "tab":
          setFocus("list")
          break
        case "j":
        case "down":
          setDetailScroll((s) => s + 1)
          break
        case "k":
        case "up":
          setDetailScroll((s) => Math.max(0, s - 1))
          break
        case "z":
          if (selectedEvent) setZoom(true)
          break
        case "v":
          exportSelected()
          break
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

    // tab switch (Events ⇄ Console) via [ / ]; the <tab-select> header mirrors it.
    if (n === "]") return setTab("console")
    if (n === "[") return setTab("events")

    switch (n) {
      case "escape":
        if (detailOpen) setDetailOpen(false)
        else if (sessionState === "running") setOverlay("confirmExit")
        else onBack()
        break
      case "j":
      case "down":
        moveSel(1)
        break
      case "k":
      case "up":
        moveSel(-1)
        break
      case "return":
        if (selectedEvent) {
          setDetailOpen(true)
          setFocus("detail")
          setDetailScroll(0)
        }
        break
      case "tab":
        if (detailOpen) setFocus("detail")
        break
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
      case "g":
        setGroup((g) => GROUP_CYCLE[(GROUP_CYCLE.indexOf(g) + 1) % GROUP_CYCLE.length])
        break
      case "l":
        setLimitsDraft(formatLimits(limits))
        setOverlay("limits")
        break
      case "z":
        if (selectedEvent) {
          setDetailOpen(true)
          setZoom(true)
        }
        break
      case "t":
        setRtpSel(0)
        setOverlay("editor")
        break
      case "v":
        exportSelected()
        break
      case "space":
        // single context "go" action — never destructive (retry / start / restart)
        if (sessionState === "unreachable") dispatch("reconnect")
        else if (sessionState === "idle" || sessionState === "ended" || sessionState === "failed") dispatch("startTrace")
        break
      case "x":
        // abort a running trace: destructive, so its own key (not Space)
        if (sessionState === "running") dispatch("stopTrace")
        break
      case "e":
        if (error?.detail) setOverlay("errorDetail")
        break
      case "d":
        if (selectedEvent) setOverlay("confirmDelete")
        break
      case "?":
        setOverlay("help")
        break
    }
  })

  function handleEditorKeys(key: { name: string; ctrl: boolean }) {
    const n = key.name
    if (rtpModal.kind === "savePresetOverwrite") {
      if (n === "y") {
        dispatch("saveAsPreset", { name: (rtpModal as any).name })
        setRtpModal({ kind: "none" })
      } else if (n === "n" || n === "escape") {
        setRtpModal({ kind: "none" })
      }
      return
    }
    if (importState) {
      if (n === "escape") { setImportState(null); return }
      const p = presets[importState.presetIdx]
      if (!p) { setImportState(null); return }
      if (importState.focus === "traces") {
        if (n === "escape" || n === "tab") {
          setImportState({ ...importState, focus: "list" })
          return
        }
        if (n === "enter" || n === "return") {
          // Import selected RTPs, dedup against existing traces
          const existing = new Set(traces.map((t) => t.text))
          for (let j = 0; j < p.traces.length; j++) {
            if (importState.selected.has(j) && !existing.has(p.traces[j].text)) {
              dispatch("addTrace", { text: p.traces[j].text })
            }
          }
          setImportState(null)
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
        // list focus
        if (n === "enter" || n === "return" || n === "tab" || n === "right") {
          setImportState({ ...importState, focus: "traces", traceSel: 0 })
          return
        }
        if (n === "j" || n === "down") {
          const next = Math.min(importState.presetIdx + 1, presets.length - 1)
          const np = presets[next]
          setImportState({ presetIdx: next, selected: new Set(np.traces.map((_, j) => j)), focus: "list", traceSel: 0 })
          return
        }
        if (n === "k" || n === "up") {
          const next = Math.max(importState.presetIdx - 1, 0)
          const np = presets[next]
          setImportState({ presetIdx: next, selected: new Set(np.traces.map((_, j) => j)), focus: "list", traceSel: 0 })
          return
        }
      }
      return
    }
    if (rtpModal.kind !== "none") {
      if (n === "escape") setRtpModal({ kind: "none" })
      return
    }
    if (key.ctrl && n === "w") {
      setRtpModal({ kind: "savePreset" })
      return
    }
    if (editingLimits) {
      if (n === "escape") setEditingLimits(false)
      return
    }
    if (editingLimits) {
      if (n === "escape") setEditingLimits(false)
      return
    }
    switch (n) {
      case "escape":
        setOverlay("none")
        break
      case "j":
      case "down":
        setRtpSel((i) => (traces.length === 0 ? 0 : Math.min(i + 1, traces.length - 1)))
        break
      case "k":
      case "up":
        setRtpSel((i) => Math.max(i - 1, 0))
        break
      case "space":
        if (rtpCur) dispatch("toggleTrace", { trace_id: rtpCur.id })
        break
      case "n":
        setRtpModal({ kind: "add" })
        break
      case "e":
        if (rtpCur) setRtpModal({ kind: "edit", id: rtpCur.id, text: rtpCur.text })
        break
      case "d":
        if (rtpCur) dispatch("deleteTrace", { trace_id: rtpCur.id })
        break
      case "l":
        setEditingLimits((v) => !v)
        if (!editingLimits) setLimitsDraft(formatLimits(limits))
        break
      case "p":
        if (presets.length > 0) {
          setImportState({ presetIdx: 0, selected: new Set(presets[0].traces.map((_, j) => j)), focus: "list", traceSel: 0 })
        }
        break
    }
  }

  // sort/filter/group moved off the header onto the Events panel's top border
  // (right-aligned via a padded composite title, since a box has one title/edge).
  // Node connection status/error rides the Events frame's top border, not a body
  // row. Connected is silent (only exceptions surface); connecting/error take
  // over the title (and error tints the whole frame red), dropping the
  // sort/group meta since a down node has no events to sort anyway.
  const eventsBorderColor =
    nodeStatus === "error" ? theme.error
    : nodeStatus === "connecting" ? theme.warning
    : focus === "list" ? theme.borderActive
    : theme.borderSubtle

  // Footer hints: the Space-action label follows the current state (self-documenting).
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
                // ditto: dim a row's name/pid when identical to the row above so the
                // eye tracks changes, not repeats. Off while grouped or filtering.
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
        statChip={<SessionStat state={sessionState} nodeSpin={nodeSpin} endedLimit={endedLimit} dirty={dirty} spark={running && buckets.current.some((v) => v > 0) ? sparkline(buckets.current) : ""} count={events.length} limits={limits} remainingSec={remainingSec} />}
        hints={eventsHints}
      />

      {overlay === "errorDetail" && error && (
        <ErrorDetailOverlay body={error.detail ?? error.message} />
      )}

      {overlay === "confirmExit" && (
        <Overlay>
          <text fg={theme.text}>Stop trace and leave?</text>
          {dirty && <text fg={theme.warning} marginTop={1}>{"⚠ unapplied changes will be lost · Ctrl+S to apply first"}</text>}
          <text fg={theme.textMuted} marginTop={1}>y = stop &amp; leave · n/Esc = stay</text>
        </Overlay>
      )}

      {overlay === "confirmDelete" && (
        <Overlay>
          <text fg={theme.text}>Delete this event?</text>
          <text fg={theme.textMuted} marginTop={1}>y = yes · n/Esc = no</text>
        </Overlay>
      )}

      {overlay === "help" && (
        <HelpOverlay
          title="session · events"
          sections={[
            {
              lines: [
                ["j / k", "move"],
                ["enter", "open detail"],
                ["v", "view event in $EDITOR"],
                ["z", "zoom detail"],
                ["o", "sort"],
                ["/", "filter"],
                ["g", "cycle grouping"],
                ["l", "limits"],
                ["e / d", "error detail / delete event"],
                ["⌃D", "delete event (no confirm)"]
              ]
            },
            {
              title: "trace (space = context go, never destructive)",
              lines: [
                ["space", "retry / start / restart (per state)"],
                ["x", "stop trace"],
                ["⌃S", "apply RTP edits (restart)"],
                ["t", "edit traces (RTPs)"],
                ["⌃L", "clear events"]
              ]
            },
            {
              title: "tabs",
              lines: [
                ["[ / ]", "switch Events ⇄ Console"],
                ["esc", "back"]
              ]
            }
          ]}
        />
      )}

      {overlay === "filter" && (
        <Overlay>
          <text fg={theme.title}>Filter events</text>
          <text fg={theme.textMuted} marginTop={1}>Scope</text>
          <select
            focused={filterFocus === "scope"}
            height={FILTER_SCOPES.length}
            itemSpacing={0}
            options={FILTER_SCOPES.map((s) => ({ name: s, description: "" }))}
            selectedIndex={Math.max(0, FILTER_SCOPES.indexOf(filterScope))}
            showDescription={false}
            backgroundColor={theme.overlay}
            textColor={theme.textMuted}
            focusedBackgroundColor={theme.overlay}
            focusedTextColor={theme.text}
            selectedBackgroundColor={theme.backgroundElement}
            selectedTextColor={theme.selectedForeground}
            onChange={(i: number) => setFilterScope(FILTER_SCOPES[i])}
          />
          <text fg={theme.textMuted} marginTop={1}>Query</text>
          <input
            focused={filterFocus === "query"}
            value={filterDraft}
            onInput={(v: string) => setFilterDraft(v)}
            onSubmit={() => {
              setFilter(filterDraft.trim() === "" ? null : { scope: filterScope, query: filterDraft })
              setOverlay("none")
            }}
            backgroundColor={theme.bg}
            textColor={theme.fg}
            focusedBackgroundColor={theme.selBg}
            focusedTextColor={theme.selFg}
          />
          <text fg={theme.dim} marginTop={1}>Tab switch scope/query · Enter apply · Esc cancel</text>
        </Overlay>
      )}

      {overlay === "sort" && (
        <Overlay>
          <text fg={theme.title}>Sort by</text>
          <select
            focused
            marginTop={1}
            height={SORT_OPTS.length}
            itemSpacing={0}
            options={SORT_OPTS.map((s) => ({
              name: `${s.key} ${s.dir === "asc" ? "↑ asc" : "↓ desc"}`,
              description: ""
            }))}
            selectedIndex={sortIdx}
            showDescription={false}
            backgroundColor={theme.overlay}
            textColor={theme.textMuted}
            focusedBackgroundColor={theme.overlay}
            focusedTextColor={theme.text}
            selectedBackgroundColor={theme.backgroundElement}
            selectedTextColor={theme.selectedForeground}
            onChange={(i: number) => setSortIdx(i)}
            onSelect={(i: number) => {
              setSort(SORT_OPTS[i])
              setOverlay("none")
            }}
          />
          <text fg={theme.dim} marginTop={1}>j/k move · Enter apply · Esc cancel</text>
        </Overlay>
      )}

      {overlay === "limits" && (
        <Overlay>
          <text fg={theme.title}>Session limits</text>
          <box flexDirection="column" marginTop={1}>
            <text fg={theme.fg}>keep time msgs (space-separated)</text>
            <text fg={theme.dim}>keep = TUI buffer cap · time = stop after Ns · msgs = stop after N events</text>
            <input
              focused
              value={limitsDraft}
              onInput={(v: string) => setLimitsDraft(v)}
              onSubmit={() => {
                const p = parseLimits(limitsDraft)
                if (p) dispatch("updateLimits", p)
                setOverlay("none")
              }}
              backgroundColor={theme.bg}
              textColor={theme.fg}
              focusedBackgroundColor={theme.selBg}
              focusedTextColor={theme.selFg}
            />
          </box>
          <text fg={theme.dim} marginTop={1}>Enter apply (Ctrl+S to restart if running) · Esc cancel</text>
        </Overlay>
      )}

      {overlay === "editor" && rtpModal.kind === "none" && (
        // Level 1 — trace list: select / toggle / delete. New & edit open a
        // second page (below) so this stays clean; examples live on that page.
        <Overlay>
          <text fg={theme.title}>{"Traces"}</text>
          <box flexDirection="column" marginTop={1}>
            {traces.length === 0 ? (
              <text fg={theme.dim}>No patterns yet · n to add</text>
            ) : (
              // manual list (not <select>): highlight = selection, no ► marker.
              // * prefix = RTP differs from what was last applied to the live trace.
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
                  onInput={(v: string) => setLimitsDraft(v)}
                  onSubmit={() => {
                    const p = parseLimits(limitsDraft)
                    if (p) dispatch("updateLimits", p)
                    setEditingLimits(false)
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
          <text fg={theme.dim} marginTop={1}>n new · e edit · d del · p import · l limits · space toggle · ⌃W save · esc close</text>
        </Overlay>
      )}

      {overlay === "editor" && (rtpModal.kind === "add" || rtpModal.kind === "edit") && (
        // Level 2 — new / edit form. Input on top, RTP cheat-sheet as reference.
        <Overlay>
          <TextField
            key={rtpModal.kind === "edit" ? "rtp-edit" : "rtp-add"}
            label={rtpModal.kind === "edit" ? "Edit RTP:" : "New RTP:"}
            hint="redbug spec, e.g. lists:seq/2 -> return"
            initial={rtpModal.kind === "edit" ? rtpModal.text : undefined}
            onSubmit={(v) => {
              if (rtpModal.kind === "edit") dispatch("updateTrace", { trace_id: rtpModal.id, text: v })
              else if (v.trim() !== "") dispatch("addTrace", { text: v })
              setRtpModal({ kind: "none" })
            }}
          />
          <box flexDirection="column" marginTop={1}>
            <text fg={theme.textMuted}>Common RTP rules (Elixir)</text>
            {RTP_EXAMPLES.map(([pat, desc]) => (
              <box key={pat} flexDirection="row">
                <text fg={theme.dim}>{pat.padEnd(38)}</text>
                <text fg={theme.dim}>{desc}</text>
              </box>
            ))}
          </box>
        </Overlay>
      )}

      {overlay === "editor" && rtpModal.kind === "savePreset" && (
        <Overlay>
          <TextField
            key="rtp-savePreset"
            label="Save as preset — name:"
            hint="reusable template (traces + limits)"
            onSubmit={(v) => {
              const name = v.trim()
              if (name === "") { setRtpModal({ kind: "none" }); return }
              if (presets.some((p) => p.name === name)) {
                setRtpModal({ kind: "savePresetOverwrite", name })
              } else {
                dispatch("saveAsPreset", { name })
                setRtpModal({ kind: "none" })
              }
            }}
          />
        </Overlay>
      )}

      {overlay === "editor" && rtpModal.kind === "savePresetOverwrite" && (
        <Overlay>
          <text fg={theme.text}>{`Overwrite preset "${rtpModal.name}"?`}</text>
          <text fg={theme.textMuted} marginTop={1}>y = overwrite · n/Esc = cancel</text>
        </Overlay>
      )}

      {overlay === "editor" && importState !== null && (() => {
        const p = presets[importState.presetIdx]
        if (!p) return null
        const selCount = importState.selected.size
        const totalCount = p.traces.length
        return (
          <Overlay title="Import traces from preset">
            <box flexDirection="row">
              {/* Left: preset list */}
              <box flexDirection="column" width={30} marginRight={2}>
                {presets.map((pr, i) => {
                  const active = i === importState.presetIdx && importState.focus === "list"
                  const bg = active ? theme.backgroundElement : theme.overlay
                  return (
                    <box key={pr.id} backgroundColor={bg} flexDirection="row" paddingLeft={1}>
                      <text bg={bg} fg={active ? theme.text : theme.textMuted}>
                        {pr.name}
                      </text>
                      <box flexGrow={1} backgroundColor={bg} />
                      <text bg={bg} fg={theme.dim}>{pr.traces.length}</text>
                    </box>
                  )
                })}
              </box>
              {/* Right: RTP preview with checkboxes */}
              <box flexDirection="column" flexGrow={1}>
                <text fg={theme.title}>{p.name}</text>
                <text fg={theme.dim} marginBottom={1}>{`${selCount}/${totalCount} selected`}</text>
                {p.traces.map((t, j) => {
                  const active = j === importState.traceSel && importState.focus === "traces"
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
            </box>
            <text fg={theme.dim} marginTop={1}>
              {importState.focus === "list" ? "j/k preset · Enter/tab → traces · Esc close" : "j/k trace · space toggle · Enter import · Esc/tab ← presets"}
            </text>
          </Overlay>
        )
      })()}

      {zoom && selectedEvent && (
        <Overlay title="Detail · esc close · v view" minWidth={70}>
          <DetailMeta ev={selectedEvent} />
          <EventDetailBody ev={selectedEvent} />
        </Overlay>
      )}
      </>
      )}
    </box>
  )
}

function ColumnHeader({ cols, pidWidth }: { cols: Cols; pidWidth: number }) {
  return (
    <box flexDirection="row">
      <text fg={theme.dim} marginRight={COLGAP}>{fit("Ts", COL.ts)}</text>
      <text fg={theme.dim} marginRight={COLGAP}>{fit(" k ", COL.k)}</text>
      {cols.name && <text fg={theme.dim} marginRight={COLGAP}>{fit("Name", COL.name)}</text>}
      {cols.pid && <text fg={theme.dim} marginRight={COLGAP}>{fit("Pid", pidWidth)}</text>}
      {cols.mfa && <text fg={theme.dim} marginRight={COLGAP}>{fit("Mfa", COL.mfa)}</text>}
      {cols.info && <text fg={theme.dim}>{fit("Info", COL.info)}</text>}
    </box>
  )
}

function EventRow({
  ev,
  active,
  filter,
  cols,
  pidWidth,
  dittoName,
  dittoPid
}: {
  ev: TraceEvent
  active: boolean
  filter: Filter | null
  cols: Cols
  pidWidth: number
  dittoName?: boolean
  dittoPid?: boolean
}) {
  if (ev.kind === "restart")
    return <text fg={theme.dim}>{`── ${ev.info} ──`}</text>

  const bg = active ? theme.backgroundElement : theme.background
  const fg = active ? theme.selectedForeground : theme.text
  const kc = kindColor[ev.kind] ?? theme.text
  const sym = kindSym[ev.kind] ?? "?"
  const hl = (scope: FilterScope) =>
    filter && (filter.scope === scope || filter.scope === "all") ? filter.query : ""
  // the active row always shows real values; ditto only recedes unselected repeats
  const nameFg = dittoName && !active ? theme.dim : fg
  const pidFg = dittoPid && !active ? theme.dim : fg

  return (
    <box backgroundColor={bg} flexDirection="row">
      <text bg={bg} fg={theme.dim} marginRight={COLGAP}>{fit(ev.ts, COL.ts)}</text>
      <text bg={bg} fg={kc} marginRight={COLGAP}>{fit(` ${sym} `, COL.k)}</text>
      {cols.name && <Cell text={fit(ev.name || "-", COL.name)} bg={bg} fg={nameFg} q={hl("all")} mr />}
      {cols.pid && <Cell text={fit(ev.pid, pidWidth)} bg={bg} fg={pidFg} q={hl("pid")} mr />}
      {cols.mfa && <Cell text={fit(ev.mfa || "-", COL.mfa)} bg={bg} fg={fg} q={hl("mfa")} mr />}
      {cols.info && <Cell text={fit(ev.info, COL.info)} bg={bg} fg={fg} q={hl("info")} />}
    </box>
  )
}

function Cell({
  text,
  bg,
  fg,
  q,
  mr
}: {
  text: string
  bg: string
  fg: string
  q: string
  mr?: boolean
}) {
  const marginRight = mr ? COLGAP : 0
  if (!q) return <text bg={bg} fg={fg} marginRight={marginRight}>{text}</text>
  return (
    <box backgroundColor={bg} flexDirection="row" marginRight={marginRight}>
      {segs(text, q).map((s, i) => (
        <text key={i} bg={s.hit ? theme.warn : bg} fg={s.hit ? theme.bg : fg}>{s.t}</text>
      ))}
    </box>
  )
}

// Bottom-left status: one glyph per lifecycle state so ● live / ◇ idle / ⧗ ended
// are distinct at a glance. Running shows sparkline + count; ended names the cap.
function SessionStat({
  state,
  nodeSpin,
  endedLimit,
  dirty,
  spark,
  count,
  limits,
  remainingSec
}: {
  state: "connecting" | "unreachable" | "idle" | "running" | "ended" | "failed"
  nodeSpin: string
  endedLimit: "time" | "msgs" | null
  dirty: boolean
  spark: string
  count: number
  limits: { keep: number; time: number; msgs: number }
  remainingSec: number | null
}) {
  switch (state) {
    case "connecting":
      return <text fg={theme.warning}>{`${nodeSpin} connecting…`}</text>
    case "unreachable":
      return <text fg={theme.error}>{"✖ can't reach node"}</text>
    case "idle":
      return <text fg={theme.textMuted}>{"◇ idle"}</text>
    case "ended":
      return (
        <text fg={theme.warning}>
          {`⧗ ${endedLimit === "msgs" ? `msgs limit (${limits.msgs})` : `time limit (${limits.time}s)`}`}
        </text>
      )
    case "failed":
      return <text fg={theme.error}>{"✖ restart failed · space retry"}</text>
    case "running":
      return (
        <box flexDirection="row">
          <text fg={theme.success}>{`● ${spark ? `${spark} ` : ""}${count}/${limits.keep}${remainingSec === null ? "" : ` · ${remainingSec}s`}`}</text>
          {dirty && <text fg={theme.warning}>{"  ⚠ unapplied"}</text>}
        </box>
      )
  }
}

function DetailMeta({ ev }: { ev: TraceEvent }) {
  const sym = kindSym[ev.kind] ?? "?"
  return (
    <box flexDirection="row" flexWrap="wrap">
      <Chip label="Kind" value={`${sym} ${ev.kind}`} />
      <Chip label="Ts" value={ev.ts} />
      <Chip label="Pid" value={ev.pid} />
      <Chip label="Name" value={ev.name || "-"} />
      <Chip label="Mfa" value={ev.mfa || "-"} />
    </box>
  )
}

function DetailPane({ ev, focused }: { ev: TraceEvent; focused: boolean }) {
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
      <EventDetailBody ev={ev} />
    </box>
  )
}

function EventDetailBody({ ev }: { ev: TraceEvent }) {
  const { payload, stack } = splitEventInfo(ev)
  const payloadLabel = ev.kind === "call" ? "args" : ev.kind === "retn" ? "return" : "payload"

  return (
    <>
      <text fg={theme.textMuted} marginTop={1}>{payloadLabel}</text>
      <code
        content={payload}
        filetype="elixir"
        syntaxStyle={elixirStyle}
        treeSitterClient={tsClient}
      />
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
    </>
  )
}

// --- pure helpers ---

function splitEventInfo(ev: TraceEvent): { payload: string; stack: string[] } {
  if (ev.kind !== "call") return { payload: ev.info, stack: [] }

  const lines = ev.info.split("\n")
  const stack = lines.filter(isStackLine)
  if (stack.length === 0) return { payload: ev.info, stack: [] }

  const payload = lines.filter((line) => !isStackLine(line)).join("\n").trimEnd()
  return { payload, stack }
}

function isStackLine(line: string): boolean {
  return line.includes("cp = ") || line.includes("Return addr")
}

function processEvents(
  events: readonly TraceEvent[],
  filter: Filter | null,
  sort: Sort,
  group: GroupKey
): { rows: DRow[]; count: number } {
  const filtering = !!(filter && filter.query)
  let evs = events.slice()

  // restart markers only carry meaning chronologically (ungrouped, unfiltered)
  const keepRestart = group === "none" && !filtering
  if (!keepRestart) evs = evs.filter((e) => e.kind !== "restart")
  if (filtering) evs = evs.filter((e) => matchFilter(e, filter!))

  evs = sortEvents(evs, sort)

  const rows: DRow[] = []
  let sidx = 0

  if (group === "none") {
    for (const ev of evs) rows.push({ type: "event", key: ev.id, ev, sidx: sidx++ })
    return { rows, count: sidx }
  }

  const groups = new Map<string, TraceEvent[]>()
  for (const ev of evs) {
    const k = groupKeyOf(ev, group)
    const bucket = groups.get(k)
    if (bucket) bucket.push(ev)
    else groups.set(k, [ev])
  }
  for (const [k, list] of groups) {
    rows.push({ type: "header", key: `h:${k}`, label: k || "-", count: list.length })
    for (const ev of list) rows.push({ type: "event", key: ev.id, ev, sidx: sidx++ })
  }
  return { rows, count: sidx }
}

function parseSort(s: string | undefined): Sort {
  const def: Sort = { key: "ts", dir: "desc" }
  if (!s) return def
  const [key, dir] = s.split("_")
  const k = (["ts", "kind", "pid", "mfa"] as SortKey[]).includes(key as SortKey)
    ? (key as SortKey)
    : "ts"
  const d: SortDir = dir === "asc" ? "asc" : "desc"
  return { key: k, dir: d }
}

function groupKeyOf(ev: TraceEvent, group: GroupKey): string {
  if (group === "pid") return ev.pid
  if (group === "mfa") return ev.mfa || "-"
  if (group === "kind") return ev.kind
  return ""
}

function matchFilter(ev: TraceEvent, f: Filter): boolean {
  const q = f.query.toLowerCase()
  const fields =
    f.scope === "pid"
      ? [ev.pid]
      : f.scope === "mfa"
        ? [ev.mfa]
        : f.scope === "info"
          ? [ev.info]
          : [ev.pid, ev.mfa, ev.info, ev.name]
  return fields.some((s) => s.toLowerCase().includes(q))
}

function sortEvents(evs: TraceEvent[], sort: Sort): TraceEvent[] {
  const dir = sort.dir === "asc" ? 1 : -1
  return evs.slice().sort((a, b) => {
    let r = 0
    switch (sort.key) {
      case "ts":
        r = Number(a.id) - Number(b.id)
        break
      case "kind":
        r = a.kind.localeCompare(b.kind)
        break
      case "pid":
        r = a.pid.localeCompare(b.pid)
        break
      case "mfa":
        r = a.mfa.localeCompare(b.mfa)
        break
    }
    if (r === 0) r = Number(a.id) - Number(b.id)
    return r * dir
  })
}

function segs(text: string, query: string): { t: string; hit: boolean }[] {
  const lower = text.toLowerCase()
  const q = query.toLowerCase()
  const out: { t: string; hit: boolean }[] = []
  let i = 0
  while (true) {
    const idx = lower.indexOf(q, i)
    if (idx < 0) {
      if (i < text.length) out.push({ t: text.slice(i), hit: false })
      break
    }
    if (idx > i) out.push({ t: text.slice(i, idx), hit: false })
    out.push({ t: text.slice(idx, idx + q.length), hit: true })
    i = idx + q.length
  }
  return out.length === 0 ? [{ t: text, hit: false }] : out
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(n, hi))
}

// Rolling per-second arrival counts → a block sparkline, scaled to its own peak
// Compare one RTP against the applied-traces baseline. An RTP is "changed"
// (staged, not yet applied) when:
//   - its id is not in the applied set at all  (newly added)
//   - its text or enabled flag differs            (edited / toggled)
// Deleted traces disappear from the list entirely, so no * marker needed.
function isRtpChanged(rtp: Rtp, applied: readonly Rtp[]): boolean {
  const orig = applied.find((a) => a.id === rtp.id)
  if (!orig) return true
  return rtp.text !== orig.text || rtp.enabled !== orig.enabled
}

// Rolling per-second arrival counts → a block sparkline, scaled to its own peak
// (relative shape, not absolute rate). Flat baseline when idle.
function sparkline(buckets: number[]): string {
  const mx = Math.max(1, ...buckets)
  return buckets
    .map((v) => SPARK_RAMP[Math.min(SPARK_RAMP.length - 1, Math.floor((v / mx) * (SPARK_RAMP.length - 1)))])
    .join("")
}

async function openInEditor(
  renderer: { suspend: () => void; resume: () => void },
  ev: TraceEvent
): Promise<void> {
  await editInEditor(renderer, {
    file: `redbug-event-${ev.id}.exs`,
    seed: elixirTerm(ev),
    readBack: false
  })
}

function elixirTerm(ev: TraceEvent): string {
  const { payload, stack } = splitEventInfo(ev)
  const lines = [
    "%{",
    `  kind: ${JSON.stringify(ev.kind)},`,
    `  ts: ${JSON.stringify(ev.ts)},`,
    `  pid: ${JSON.stringify(ev.pid)},`,
    `  name: ${JSON.stringify(ev.name)},`,
    `  mfa: ${JSON.stringify(ev.mfa)},`,
    `  payload: ${payload}${stack.length > 0 ? "," : ""}`
  ]

  if (stack.length > 0) {
    lines.push("  stack: [")
    lines.push(...stack.map((line) => `    ${JSON.stringify(line)},`))
    lines.push("  ]")
  }

  return [
    ...lines,
    "}",
    ""
  ].join("\n")
}
