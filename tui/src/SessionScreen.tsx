/** @jsxImportSource @opentui/react */
import { useMemo, useState } from "react"
import { useKeyboard, useRenderer } from "@opentui/react"
import type { StoreProxy } from "@musubi/react"

import { sessionRoot, dispatcher, useMusubiRoot, useMusubiSnapshot } from "./musubi"
import { DEFAULT_LIMITS, formatLimits, parseLimits } from "./limits"
import { theme, kindColor } from "./theme"
import { ErrorDetailOverlay, Flash, Header, HelpOverlay, Overlay, PickRow, RootGate, StatusBar, TextField, fit } from "./ui"
import { ConsoleTab } from "./ConsoleTab"
import { editInEditor } from "./editor"

type SessionStore = StoreProxy<"Server.Stores.SessionRoot", Musubi.Stores>
type Rtp = Server.Schema.Rtp
type TraceEvent = Server.Schema.TraceEvent

type SortKey = "ts" | "kind" | "pid" | "mfa"
type SortDir = "asc" | "desc"
type Sort = { key: SortKey; dir: SortDir }
type FilterScope = "all" | "mfa" | "pid" | "info"
type Filter = { scope: FilterScope; query: string }
type GroupKey = "none" | "pid" | "mfa" | "kind"

type Overlay = "none" | "sort" | "filter" | "editor" | "limits" | "help" | "errorDetail"
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

const COL = { ts: 12, k: 1, name: 16, pid: 11, mfa: 22, info: 44 }
const COLGAP = 2

export function SessionScreen({
  nodeId,
  sessionId,
  settings,
  onBack
}: {
  nodeId: string
  sessionId: string
  settings?: Server.Schema.Settings
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
  onBack
}: {
  store: SessionStore
  nodeId: string
  sessionId: string
  settings?: Server.Schema.Settings
  onBack: () => void
}) {
  const [tab, setTab] = useState<"events" | "console">("events")
  const snap = useMusubiSnapshot(store)
  const cols = settings?.columns ?? ALL_COLS
  const renderer = useRenderer()
  const traces = (snap?.traces ?? []) as Rtp[]
  const events = (snap?.events ?? []) as TraceEvent[]
  const limits = snap?.limits ?? DEFAULT_LIMITS
  const running = snap?.status === "running"
  const dirty = snap?.dirty === true
  const error = snap?.error ?? null

  const [sort, setSort] = useState<Sort>(() => parseSort(settings?.default_sort))
  const [filter, setFilter] = useState<Filter | null>(null)
  const [filterScope, setFilterScope] = useState<FilterScope>("all")
  const [filterDraft, setFilterDraft] = useState("")
  const [group, setGroup] = useState<GroupKey>("none")

  const [sel, setSel] = useState(0)
  const [detailOpen, setDetailOpen] = useState(false)
  const [focus, setFocus] = useState<Focus>("list")
  const [detailScroll, setDetailScroll] = useState(0)
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
  >({ kind: "none" })

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
      if (n === "escape") setOverlay("none")
      else if (n === "tab")
        setFilterScope(
          (s) => FILTER_SCOPES[(FILTER_SCOPES.indexOf(s) + 1) % FILTER_SCOPES.length]
        )
      return
    }

    if (overlay === "sort") {
      if (n === "tab") setSortIdx((i) => (i + 1) % SORT_OPTS.length)
      else if (n === "j" || n === "down") setSortIdx((i) => Math.min(i + 1, SORT_OPTS.length - 1))
      else if (n === "k" || n === "up") setSortIdx((i) => Math.max(i - 1, 0))
      else if (n === "escape") setOverlay("none")
      else if (n === "return") {
        setSort(SORT_OPTS[sortIdx])
        setOverlay("none")
      }
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
      if (detailOpen && (n === "j" || n === "down")) return moveSel(1)
      if (detailOpen && (n === "k" || n === "up")) return moveSel(-1)
      return
    }

    switch (n) {
      case "escape":
        if (detailOpen) setDetailOpen(false)
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
      case "s":
        if (key.shift) dispatch("startTrace")
        break
      case "x":
        if (key.shift) dispatch("stopTrace")
        break
      case "]":
        setTab("console")
        break
      case "e":
        if (error?.detail) setOverlay("errorDetail")
        break
      case "d":
        if (error) dispatch("dismissError")
        break
      case "?":
        setOverlay("help")
        break
    }
  })

  function handleEditorKeys(key: { name: string; ctrl: boolean }) {
    const n = key.name
    if (rtpModal.kind !== "none") {
      if (n === "escape") setRtpModal({ kind: "none" })
      return
    }
    if (key.ctrl && n === "w") {
      setRtpModal({ kind: "savePreset" })
      return
    }
    switch (n) {
      case "escape":
        setOverlay("none")
        break
      case "j":
      case "down":
        setRtpSel((i) => Math.min(i + 1, traces.length - 1))
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
    }
  }

  const headerInfo =
    `sort:${sort.key}${sort.dir === "asc" ? "↑" : "↓"}` +
    `    filter:${filter ? `${filter.scope}/${filter.query}` : "-"}` +
    `    group:${group}`

  return (
    <box flexDirection="column" flexGrow={1} backgroundColor={theme.bg}>
      <Header title={snap?.name ?? "session"}>
        <text fg={theme.dim}>{`  ${headerInfo}`}</text>
        {dirty && <text fg={theme.warn}>{"  ⚠ unapplied (⌃S)"}</text>}
      </Header>

      <box backgroundColor={theme.bg} paddingLeft={1} flexDirection="row">
        <text fg={tab === "events" ? theme.title : theme.dim}>
          {tab === "events" ? "● Events" : "○ Events"}
        </text>
        <text fg={theme.dim}>{"   "}</text>
        <text fg={tab === "console" ? theme.title : theme.dim}>
          {tab === "console" ? "● Console" : "○ Console"}
        </text>
        <text fg={theme.dim}>{"   [/] switch"}</text>
      </box>

      {tab === "console" ? (
        <ConsoleTab
          nodeId={nodeId}
          sessionId={sessionId}
          onSwitchToEvents={() => setTab("events")}
          onBack={onBack}
        />
      ) : (
      <>
      {!zoom && (
      <box flexDirection="row" flexGrow={1} gap={1}>
        <box
          border
          borderColor={focus === "list" ? theme.title : theme.border}
          backgroundColor={theme.bg}
          title={`Events (${count})`}
          titleColor={theme.title}
          flexGrow={1}
          flexBasis={0}
          flexDirection="column"
          padding={1}
        >
          <ColumnHeader cols={cols} pidWidth={pidWidth} />
          {rows.length === 0 ? (
            <text fg={theme.dim}>No events yet · ⇧S to start</text>
          ) : (
            rows
              .slice(0, 300)
              .map((row) =>
                row.type === "header" ? (
                  <text key={row.key} fg={theme.dim}>{`▸ ${row.label} (${row.count})`}</text>
                ) : (
                  <EventRow
                    key={row.key}
                    ev={row.ev}
                    active={row.sidx === selClamped}
                    filter={filter}
                    cols={cols}
                    pidWidth={pidWidth}
                  />
                )
              )
          )}
        </box>

        {detailOpen && !zoom && selectedEvent && (
          <DetailPane ev={selectedEvent} scroll={detailScroll} focused={focus === "detail"} />
        )}
      </box>
      )}

      {error && <Flash error={error} />}

      <StatusBar
        statusText={`${snap?.status ?? "stopped"} · ${count} evt · buf ${events.length}/${limits.keep}`}
        tone={running ? "on" : "dim"}
        hints="j/k move · enter detail · t traces · ⇧S/X run/stop · ? help · esc back"
      />

      {overlay === "errorDetail" && error && (
        <ErrorDetailOverlay body={error.detail ?? error.message} />
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
                ["e / d", "error detail / dismiss"]
              ]
            },
            {
              title: "traces",
              lines: [
                ["t", "edit traces (RTPs)"],
                ["⇧S / ⇧X", "start / stop trace"],
                ["⌃S", "apply (restart)"],
                ["⌃L", "clear events"]
              ]
            },
            {
              title: "tabs",
              lines: [
                ["]", "switch to Console"],
                ["esc", "back"]
              ]
            }
          ]}
        />
      )}

      {overlay === "filter" && (
        <Overlay>
          <text fg={theme.title}>Filter events</text>
          <box marginTop={1}>
            <FilterScopePicker scope={filterScope} onPick={setFilterScope} />
          </box>
          <box flexDirection="column" marginTop={1}>
            <text fg={theme.dim}>{`scope: ${filterScope} · Tab cycles`}</text>
            <input
              focused
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
          </box>
          <text fg={theme.dim} marginTop={1}>Enter apply · Esc cancel</text>
        </Overlay>
      )}

      {overlay === "sort" && (
        <Overlay>
          <text fg={theme.title}>Sort by</text>
          <box flexDirection="column" marginTop={1}>
            {SORT_OPTS.map((s, i) => (
              <PickRow
                key={`${s.key}-${s.dir}`}
                label={`${s.key} ${s.dir === "asc" ? "↑ asc" : "↓ desc"}`}
                active={i === sortIdx}
              />
            ))}
          </box>
          <text fg={theme.dim} marginTop={1}>j/k or Tab move · Enter apply · Esc cancel</text>
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

      {overlay === "editor" && (
        <Overlay>
          <text fg={theme.title}>{`Traces — ${snap?.name ?? ""}`}</text>
          <box flexDirection="column" marginTop={1}>
            {traces.length === 0 ? (
              <text fg={theme.dim}>No patterns yet · a to add</text>
            ) : (
              traces.map((t, i) => <RtpRow key={t.id} rtp={t} active={i === rtpSel} />)
            )}
          </box>
          <text fg={theme.dim} marginTop={1}>j/k move · space toggle · n add · e edit · d del · Ctrl+W save preset · esc close</text>
          {rtpModal.kind === "add" && (
            <TextField
              key="rtp-add"
              label="New RTP:"
              hint="redbug spec, e.g. lists:seq/2 -> return"
              onSubmit={(v) => {
                if (v.trim() !== "") dispatch("addTrace", { text: v })
                setRtpModal({ kind: "none" })
              }}
            />
          )}
          {rtpModal.kind === "edit" && (
            <TextField
              key="rtp-edit"
              label="Edit RTP:"
              hint="redbug spec, e.g. lists:seq/2 -> return"
              initial={rtpModal.text}
              onSubmit={(v) => {
                dispatch("updateTrace", { trace_id: rtpModal.id, text: v })
                setRtpModal({ kind: "none" })
              }}
            />
          )}
          {rtpModal.kind === "savePreset" && (
            <TextField
              key="rtp-savePreset"
              label="Save as preset — name:"
              hint="reusable template (traces + limits)"
              onSubmit={(v) => {
                if (v.trim() !== "") dispatch("saveAsPreset", { name: v })
                setRtpModal({ kind: "none" })
              }}
            />
          )}
        </Overlay>
      )}

      {zoom && selectedEvent && (
        <box
          position="absolute"
          top={0}
          left={0}
          right={0}
          bottom={0}
          justifyContent="center"
          alignItems="center"
        >
          <box
            border
            borderColor={theme.title}
            backgroundColor={theme.overlay}
            title="Detail (zoom · esc close · v view)"
            titleColor={theme.title}
            flexDirection="column"
            paddingTop={1}
            paddingBottom={1}
            paddingLeft={2}
            paddingRight={2}
            minWidth={70}
          >
            {detailLines(selectedEvent)
              .slice(detailScroll)
              .map((ln, i) => (
                <text key={i} fg={ln.dim ? theme.dim : theme.fg}>{ln.text}</text>
              ))}
          </box>
        </box>
      )}
      </>
      )}
    </box>
  )
}

function ColumnHeader({ cols, pidWidth }: { cols: Cols; pidWidth: number }) {
  return (
    <box flexDirection="row">
      <text fg={theme.dim} marginRight={COLGAP}>{fit("ts", COL.ts)}</text>
      <text fg={theme.dim} marginRight={COLGAP}>{" k "}</text>
      {cols.name && <text fg={theme.dim} marginRight={COLGAP}>{fit("name", COL.name)}</text>}
      {cols.pid && <text fg={theme.dim} marginRight={COLGAP}>{fit("pid", pidWidth)}</text>}
      {cols.mfa && <text fg={theme.dim} marginRight={COLGAP}>{fit("mfa", COL.mfa)}</text>}
      {cols.info && <text fg={theme.dim}>{fit("info", COL.info)}</text>}
    </box>
  )
}

function EventRow({
  ev,
  active,
  filter,
  cols,
  pidWidth
}: {
  ev: TraceEvent
  active: boolean
  filter: Filter | null
  cols: Cols
  pidWidth: number
}) {
  if (ev.kind === "restart")
    return <text fg={theme.dim}>{`── ${ev.info} ──`}</text>

  const bg = active ? theme.selBg : theme.bg
  const fg = active ? theme.selFg : theme.fg
  const kc = kindColor[ev.kind] ?? theme.fg
  const sym = kindSym[ev.kind] ?? "?"
  const hl = (scope: FilterScope) =>
    filter && (filter.scope === scope || filter.scope === "all") ? filter.query : ""

  return (
    <box backgroundColor={bg} flexDirection="row">
      <text bg={bg} fg={theme.dim} marginRight={COLGAP}>{fit(ev.ts, COL.ts)}</text>
      <text bg={bg} fg={kc} marginRight={COLGAP}>{` ${sym} `}</text>
      {cols.name && <Cell text={fit(ev.name || "-", COL.name)} bg={bg} fg={fg} q={hl("all")} mr />}
      {cols.pid && <Cell text={fit(ev.pid, pidWidth)} bg={bg} fg={fg} q={hl("pid")} mr />}
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

function DetailPane({
  ev,
  scroll,
  focused
}: {
  ev: TraceEvent
  scroll: number
  focused: boolean
}) {
  return (
    <box
      border
      borderColor={focused ? theme.title : theme.border}
      backgroundColor={theme.bg}
      title="Detail (z zoom · v view)"
      titleColor={theme.title}
      width={46}
      flexDirection="column"
      padding={1}
    >
      {detailLines(ev)
        .slice(scroll)
        .map((ln, i) => (
          <text key={i} fg={ln.dim ? theme.dim : theme.fg}>{ln.text}</text>
        ))}
    </box>
  )
}

function detailLines(ev: TraceEvent): { text: string; dim?: boolean }[] {
  const sym = kindSym[ev.kind] ?? "?"
  const payloadLabel =
    ev.kind === "call" ? "args" : ev.kind === "retn" ? "return" : "payload"
  return [
    { text: `kind: ${sym} ${ev.kind}` },
    { text: `ts:   ${ev.ts}` },
    { text: `pid:  ${ev.pid}` },
    { text: `name: ${ev.name || "-"}` },
    { text: `mfa:  ${ev.mfa || "-"}` },
    { text: `${payloadLabel}:`, dim: true },
    ...wrap(ev.info, 42).map((t) => ({ text: t }))
  ]
}

function RtpRow({ rtp, active }: { rtp: Rtp; active: boolean }) {
  const bg = active ? theme.selBg : theme.overlay
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

function FilterScopePicker({
  scope,
  onPick
}: {
  scope: FilterScope
  onPick: (s: FilterScope) => void
}) {
  void onPick
  return (
    <box flexDirection="row">
      {FILTER_SCOPES.map((s) => (
        <text key={s} fg={s === scope ? theme.title : theme.dim}>{`[${s}] `}</text>
      ))}
    </box>
  )
}

// --- pure helpers ---

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

function wrap(s: string, width: number): string[] {
  if (s.length <= width) return [s]
  const out: string[] = []
  for (let i = 0; i < s.length; i += width) out.push(s.slice(i, i + width))
  return out
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(n, hi))
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
  return [
    "%{",
    `  kind: ${JSON.stringify(ev.kind)},`,
    `  ts: ${JSON.stringify(ev.ts)},`,
    `  pid: ${JSON.stringify(ev.pid)},`,
    `  name: ${JSON.stringify(ev.name)},`,
    `  mfa: ${JSON.stringify(ev.mfa)},`,
    `  payload: ${ev.info}`,
    "}",
    ""
  ].join("\n")
}
