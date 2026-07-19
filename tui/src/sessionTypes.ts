import type { TraceEvent } from "./types"

export type SortKey = "ts" | "kind" | "pid" | "mfa"
export type SortDir = "asc" | "desc"
export type Sort = { key: SortKey; dir: SortDir }
export type FilterScope = "all" | "mfa" | "pid" | "info"
export type Filter = { scope: FilterScope; query: string }
export type GroupKey = "none" | "pid" | "mfa" | "kind"
export type Focus = "list" | "detail"
export type Cols = { name: boolean; pid: boolean; mfa: boolean; info: boolean }

export const ALL_COLS: Cols = { name: true, pid: true, mfa: true, info: true }

export type DRow =
  | { type: "header"; key: string; label: string; count: number }
  // `ret` is set only in fold mode on a call row: the return value of the paired
  // retn (which is then hidden), so the row can render "args → ret".
  | { type: "event"; key: string; ev: TraceEvent; sidx: number; ret?: string }

export const kindSym: Record<string, string> = {
  call: "→",
  retn: "←",
  send: "↑",
  recv: "↓",
  restart: "·"
}

export const SORT_OPTS: Sort[] = [
  { key: "ts", dir: "desc" },
  { key: "ts", dir: "asc" },
  { key: "kind", dir: "asc" },
  { key: "kind", dir: "desc" },
  { key: "pid", dir: "asc" },
  { key: "mfa", dir: "asc" }
]

export const FILTER_SCOPES: FilterScope[] = ["all", "mfa", "pid", "info"]
export const GROUP_CYCLE: GroupKey[] = ["none", "pid", "mfa", "kind"]

export const RTP_EXAMPLES: [string, string][] = [
  ["Enum.map/2 -> return", "call args + return value"],
  ["MyMod.func -> return;stack", "+ call stack"],
  ["Demo.tick when '$1' > 100 -> return", "guard on 1st arg"],
  ["Enum.map/2 · MyMod._ · MyMod", "arity · any fun · whole module"]
]

export const COL = { pair: 6, ts: 12, k: 3, name: 16, pid: 11, mfa: 22, info: 44 }
export const COLGAP = 2
export const SPARK_N = 12
export const SPARK_RAMP = "▁▂▃▄▅▆▇█"
