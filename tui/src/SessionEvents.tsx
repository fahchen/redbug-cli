/** @jsxImportSource @opentui/react */
import { theme, kindColor } from "./theme"
import { segs } from "./sessionHelpers"
import { COL, COLGAP, kindSym } from "./sessionTypes"
import type { Filter, FilterScope, Cols } from "./sessionTypes"
import type { TraceEvent } from "./types"
import { fit } from "./ui"

export function ColumnHeader({ cols, pidWidth }: { cols: Cols; pidWidth: number }) {
  return (
    <box flexDirection="row" flexWrap="no-wrap">
      <text flexShrink={0} fg={theme.dim} marginRight={COLGAP}>{fit("#", COL.pair)}</text>
      <text flexShrink={0} fg={theme.dim} marginRight={COLGAP}>{fit("Ts", COL.ts)}</text>
      {cols.name && <text flexShrink={0} fg={theme.dim} marginRight={COLGAP}>{fit("Name", COL.name)}</text>}
      {cols.pid && <text flexShrink={0} fg={theme.dim} marginRight={COLGAP}>{fit("Pid", pidWidth)}</text>}
      {/* leading 2 cols reserve the kind-glyph slot that rides in front of Mfa */}
      {cols.mfa && <text flexShrink={0} fg={theme.dim} marginRight={COLGAP}>{fit("  Mfa", COL.mfa + 2)}</text>}
      {cols.info && <text flexShrink={0} fg={theme.dim}>{fit("Info", COL.info)}</text>}
    </box>
  )
}

export function EventRow({
  ev,
  ret,
  active,
  filter,
  cols,
  pidWidth,
  dittoName,
  dittoPid,
  id
}: {
  ev: TraceEvent
  ret?: string
  active: boolean
  filter: Filter | null
  cols: Cols
  pidWidth: number
  dittoName?: boolean
  dittoPid?: boolean
  id?: string
}) {
  if (ev.kind === "restart")
    return <text id={id} fg={theme.dim}>{`── ${ev.info} ──`}</text>

  const bg = active ? theme.backgroundElement : theme.background
  const fg = active ? theme.selectedForeground : theme.text
  const kc = kindColor[ev.kind] ?? theme.text
  const sym = kindSym[ev.kind] ?? "?"
  const hl = (scope: FilterScope) =>
    filter && (filter.scope === scope || filter.scope === "all") ? filter.query : ""
  const nameFg = dittoName && !active ? theme.dim : fg
  const pidFg = dittoPid && !active ? theme.dim : fg
  // Nesting indent for the payload; the pair id (#N) rides in its own leading col.
  const lead = "  ".repeat(Math.min(ev.depth, 8))
  // fold mode: the paired return is merged onto the call row as "args → ret".
  const info = ret != null ? `${ev.info} → ${ret}` : ev.info

  return (
    <box id={id} backgroundColor={bg} flexDirection="row" flexWrap="no-wrap">
      <text flexShrink={0} bg={bg} fg={theme.dim} marginRight={COLGAP}>{fit(ev.pair ? `#${ev.pair}` : "", COL.pair)}</text>
      <text flexShrink={0} bg={bg} fg={theme.dim} marginRight={COLGAP}>{fit(ev.ts, COL.ts)}</text>
      {cols.name && <Cell text={fit(ev.name || "-", COL.name)} bg={bg} fg={nameFg} q={hl("all")} mr />}
      {cols.pid && <Cell text={fit(ev.pid, pidWidth)} bg={bg} fg={pidFg} q={hl("pid")} mr />}
      {/* kind glyph (colored) folded in front of the Mfa — no separate column */}
      {cols.mfa && (
        <box flexShrink={0} flexDirection="row" flexWrap="no-wrap" backgroundColor={bg} marginRight={COLGAP}>
          <text bg={bg} fg={kc}>{`${sym} `}</text>
          <Cell text={fit(ev.mfa || "-", COL.mfa)} bg={bg} fg={fg} q={hl("mfa")} />
        </box>
      )}
      {cols.info && (
        <box flexShrink={0} flexDirection="row" flexWrap="no-wrap" backgroundColor={bg}>
          {lead !== "" && <text bg={bg} fg={theme.dim}>{lead}</text>}
          <Cell text={fit(info, COL.info)} bg={bg} fg={fg} q={hl("info")} />
        </box>
      )}
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
  if (!q) return <text flexShrink={0} bg={bg} fg={fg} marginRight={marginRight}>{text}</text>
  return (
    <box flexShrink={0} backgroundColor={bg} flexDirection="row" flexWrap="no-wrap" marginRight={marginRight}>
      {segs(text, q).map((s, i) => (
        <text key={i} flexShrink={0} bg={s.hit ? theme.warn : bg} fg={s.hit ? theme.bg : fg}>{s.t}</text>
      ))}
    </box>
  )
}
