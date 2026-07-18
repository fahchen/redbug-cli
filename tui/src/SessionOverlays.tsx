/** @jsxImportSource @opentui/react */
import type { RefObject } from "react"
import { useTerminalDimensions } from "@opentui/react"
import type { ScrollBoxRenderable } from "@opentui/core"
import { theme } from "./theme"
import { FILTER_SCOPES, SORT_OPTS } from "./sessionTypes"
import type { FilterScope, Filter } from "./sessionTypes"
import type { TraceEvent } from "./types"
import { Overlay, HelpOverlay } from "./ui"
import { ConfirmOverlay } from "./ConfirmOverlay"
import { DetailMeta, EventDetailBody } from "./SessionDetail"
import { DialogSelect } from "./DialogSelect"
import type { DialogItem } from "./DialogSelect"

// --- Filter Overlay ---

export function FilterOverlay({
  filterScope,
  filterDraft,
  filterFocus,
  onFilterScope,
  onFilterDraft,
  onFilterFocus,
  onApply,
  onClose
}: {
  filterScope: FilterScope
  filterDraft: string
  filterFocus: "query" | "scope"
  onFilterScope: (s: FilterScope) => void
  onFilterDraft: (v: string) => void
  onFilterFocus: (f: "query" | "scope") => void
  onApply: (f: Filter | null) => void
  onClose: () => void
}) {
  return (
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
        onChange={(i: number) => onFilterScope(FILTER_SCOPES[i])}
      />
      <text fg={theme.textMuted} marginTop={1}>Query</text>
      <input
        focused={filterFocus === "query"}
        value={filterDraft}
        onInput={(v: string) => onFilterDraft(v)}
        onSubmit={() => {
          onApply(filterDraft.trim() === "" ? null : { scope: filterScope, query: filterDraft })
        }}
        backgroundColor={theme.bg}
        textColor={theme.fg}
        focusedBackgroundColor={theme.selBg}
        focusedTextColor={theme.selFg}
      />
      <text fg={theme.dim} marginTop={1}>Tab switch scope/query · Enter apply · Esc cancel</text>
    </Overlay>
  )
}

// --- Sort Overlay ---

export function SortOverlay({
  sortIdx,
  onSelect,
  onClose
}: {
  sortIdx: number
  onSelect: (item: DialogItem) => void
  onClose: () => void
}) {
  return (
    <DialogSelect
      title="Sort by"
      items={SORT_OPTS.map((s) => ({
        id: `${s.key}_${s.dir}`,
        name: `${s.key} ${s.dir === "asc" ? "↑ asc" : "↓ desc"}`,
        query: `${s.key} ${s.dir}`
      }))}
      selectedIndex={sortIdx}
      onSelect={onSelect}
      onClose={onClose}
    />
  )
}

// --- Limits Overlay ---

export function LimitsOverlay({
  limitsDraft,
  onLimitsDraft,
  onApply,
  onClose
}: {
  limitsDraft: string
  onLimitsDraft: (v: string) => void
  onApply: () => void
  onClose: () => void
}) {
  return (
    <Overlay>
      <text fg={theme.title}>Session limits</text>
      <box flexDirection="column" marginTop={1}>
        <text fg={theme.fg}>keep time msgs (space-separated)</text>
        <text fg={theme.dim}>keep = TUI buffer cap · time = stop after Ns · msgs = stop after N events</text>
        <input
          focused
          value={limitsDraft}
          onInput={(v: string) => onLimitsDraft(v)}
          onSubmit={() => onApply()}
          backgroundColor={theme.bg}
          textColor={theme.fg}
          focusedBackgroundColor={theme.selBg}
          focusedTextColor={theme.selFg}
        />
      </box>
      <text fg={theme.dim} marginTop={1}>Enter apply (Ctrl+S to restart if running) · Esc cancel</text>
    </Overlay>
  )
}

// --- Help Overlay (session events) ---

export function SessionHelpOverlay() {
  return (
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
          title: "detail pane",
          lines: [
            ["tab", "switch list ↔ detail focus"],
            ["j / k", "scroll detail"],
            ["⌃F / ⌃B", "page down / up"],
            ["⌃J / ⌃K", "move selection from detail"]
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
  )
}

// --- Confirm Exit ---

export function ConfirmExitOverlay({ dirty }: { dirty: boolean }) {
  return (
    <ConfirmOverlay
      question="Stop trace and leave?"
      labels={{ y: "stop & leave", n: "stay" }}
    >
      {dirty && <text fg={theme.warning} marginTop={1}>{"⚠ unapplied changes will be lost · Ctrl+S to apply first"}</text>}
    </ConfirmOverlay>
  )
}

// --- Zoom Overlay ---

export function ZoomOverlay({
  ev,
  scrollRef
}: {
  ev: TraceEvent
  scrollRef?: RefObject<ScrollBoxRenderable | null>
}) {
  const { height } = useTerminalDimensions()
  const bodyHeight = Math.max(5, height - 10)
  return (
    <Overlay title="Detail · esc close · j/k scroll · ⌃F/⌃B page · v view" minWidth={70}>
      <DetailMeta ev={ev} />
      <scrollbox ref={scrollRef} scrollY stickyStart="top" height={bodyHeight}>
        <EventDetailBody ev={ev} />
      </scrollbox>
    </Overlay>
  )
}
