/** @jsxImportSource @opentui/react */
import { theme, kindColor } from "./theme"
import { segs } from "./sessionHelpers"
import { COL, COLGAP, kindSym } from "./sessionTypes"
import type { Filter, FilterScope, Cols } from "./sessionTypes"
import type { TraceEvent } from "./types"
import { fit } from "./ui"

export function ColumnHeader({ cols, pidWidth }: { cols: Cols; pidWidth: number }) {
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

export function EventRow({
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
