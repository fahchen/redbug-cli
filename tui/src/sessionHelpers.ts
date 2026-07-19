import type { Rtp, TraceEvent } from "./types"
import type { Filter, Sort, GroupKey, DRow } from "./sessionTypes"
import { SPARK_RAMP } from "./sessionTypes"
import { editInEditor } from "./editor"

export function splitEventInfo(ev: TraceEvent): { payload: string; stack: string[] } {
  if (ev.kind !== "call") return { payload: ev.info, stack: [] }

  const lines = ev.info.split("\n")
  const stack = lines.filter(isStackLine)
  if (stack.length === 0) return { payload: ev.info, stack: [] }

  const payload = lines.filter((line) => !isStackLine(line)).join("\n").trimEnd()
  return { payload, stack }
}

export function isStackLine(line: string): boolean {
  return line.includes("cp = ") || line.includes("Return addr")
}

export function processEvents(
  events: readonly TraceEvent[],
  filter: Filter | null,
  sort: Sort,
  group: GroupKey,
  fold = false
): { rows: DRow[]; count: number } {
  const filtering = !!(filter && filter.query)
  let evs = events.slice()

  const keepRestart = group === "none" && !filtering
  if (!keepRestart) evs = evs.filter((e) => e.kind !== "restart")
  if (filtering) evs = evs.filter((e) => matchFilter(e, filter!))

  // Fold mode: hide a return whose call is present and carry its value onto the
  // call row (paired exactly by `pair` id — no heuristic).
  const retByPair = new Map<string, string>()
  if (fold) {
    const callPairs = new Set(evs.filter((e) => e.kind === "call" && e.pair).map((e) => e.pair))
    for (const e of evs) if (e.kind === "retn" && e.pair) retByPair.set(e.pair, e.info)
    evs = evs.filter((e) => !(e.kind === "retn" && e.pair && callPairs.has(e.pair)))
  }

  const retOf = (ev: TraceEvent) =>
    fold && ev.kind === "call" && ev.pair ? retByPair.get(ev.pair) : undefined

  evs = sortEvents(evs, sort)

  const rows: DRow[] = []
  let sidx = 0

  if (group === "none") {
    for (const ev of evs) rows.push({ type: "event", key: ev.id, ev, sidx: sidx++, ret: retOf(ev) })
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
    for (const ev of list) rows.push({ type: "event", key: ev.id, ev, sidx: sidx++, ret: retOf(ev) })
  }
  return { rows, count: sidx }
}

export function parseSort(s: string | undefined): Sort {
  const def: Sort = { key: "ts", dir: "desc" }
  if (!s) return def
  const [key, dir] = s.split("_")
  const k = (["ts", "kind", "pid", "mfa"] as Sort["key"][]).includes(key as Sort["key"])
    ? (key as Sort["key"])
    : "ts"
  const d: Sort["dir"] = dir === "asc" ? "asc" : "desc"
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

export function segs(text: string, query: string): { t: string; hit: boolean }[] {
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

export function isRtpChanged(rtp: Rtp, applied: readonly Rtp[]): boolean {
  const orig = applied.find((a) => a.id === rtp.id)
  if (!orig) return true
  return rtp.text !== orig.text || rtp.enabled !== orig.enabled
}

export function sparkline(buckets: number[]): string {
  const mx = Math.max(1, ...buckets)
  return buckets
    .map((v) => SPARK_RAMP[Math.min(SPARK_RAMP.length - 1, Math.floor((v / mx) * (SPARK_RAMP.length - 1)))])
    .join("")
}

export function elixirTerm(ev: TraceEvent): string {
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

export async function openInEditor(
  renderer: { suspend: () => void; resume: () => void },
  ev: TraceEvent
): Promise<void> {
  await editInEditor(renderer, {
    file: `redbug-event-${ev.id}.exs`,
    seed: elixirTerm(ev),
    readBack: false
  })
}
