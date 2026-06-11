/** @jsxImportSource @opentui/react */
import { useState } from "react"
import { useKeyboard } from "@opentui/react"
import type { StoreProxy } from "@musubi/react"

import { SETTINGS_ROOT, useMusubiRoot, useMusubiSnapshot } from "./musubi"
import { theme, themeNames } from "./theme"
import { Footer, Header, Overlay, TextField } from "./ui"

type SettingsStore = StoreProxy<"Server.Stores.SettingsRoot", Musubi.Stores>
type Settings = Server.Schema.Settings

type ColKey = "name" | "pid" | "mfa" | "info"
const COL_KEYS: ColKey[] = ["name", "pid", "mfa", "info"]
const SORT_VALUES = ["ts_desc", "ts_asc", "kind_asc", "kind_desc", "pid_asc", "mfa_asc"]

declare const process: { env: Record<string, string | undefined> }

export function SettingsScreen({ onBack }: { onBack: () => void }) {
  const root = useMusubiRoot(SETTINGS_ROOT)

  if (root.status === "loading")
    return (
      <box backgroundColor={theme.bg} flexGrow={1} padding={1}>
        <text fg={theme.fg}>Loading settings…</text>
      </box>
    )
  if (root.status === "error")
    return (
      <box backgroundColor={theme.bg} flexGrow={1} padding={1}>
        <text fg={theme.off}>{`Settings error: ${root.error.message}`}</text>
      </box>
    )

  return <SettingsView store={root.store} onBack={onBack} />
}

function SettingsView({ store, onBack }: { store: SettingsStore; onBack: () => void }) {
  const snap = useMusubiSnapshot(store)
  const s = snap.settings as Settings | undefined
  const cols = s?.columns ?? { name: true, pid: true, mfa: true, info: true }
  const limits = s?.default_limits ?? { keep: 500, time: 900, msgs: 10000 }
  const curTheme = s?.theme ?? "dark"
  const curSort = s?.default_sort ?? "ts_desc"
  const editor = process.env.EDITOR || process.env.VISUAL || "vi"

  const [sel, setSel] = useState(0)
  const [limitsDraft, setLimitsDraft] = useState<string | null>(null)

  const rowCount = 7 // theme, sort, 4 columns, limits

  const dispatch = (payload: any) =>
    void store.dispatchCommand("updateSettings" as any, payload).catch(() => {})

  const cycle = (arr: string[], cur: string) => {
    const i = arr.indexOf(cur)
    return arr[(i + 1) % arr.length]
  }

  const act = () => {
    if (sel === 0) dispatch({ theme: cycle(themeNames, curTheme) })
    else if (sel === 1) dispatch({ default_sort: cycle(SORT_VALUES, curSort) })
    else if (sel >= 2 && sel <= 5) {
      const key = COL_KEYS[sel - 2]
      dispatch({ columns: { [key]: !cols[key] } })
    } else if (sel === 6) {
      setLimitsDraft(`${limits.keep} ${limits.time} ${limits.msgs}`)
    }
  }

  useKeyboard((key) => {
    const n = key.name
    if (limitsDraft !== null) {
      if (n === "escape") setLimitsDraft(null)
      return
    }
    switch (n) {
      case "escape":
        onBack()
        break
      case "j":
      case "down":
        setSel((i) => Math.min(i + 1, rowCount - 1))
        break
      case "k":
      case "up":
        setSel((i) => Math.max(i - 1, 0))
        break
      case "space":
      case "return":
      case "right":
      case "l":
        act()
        break
    }
  })

  return (
    <box flexDirection="column" flexGrow={1} backgroundColor={theme.bg}>
      <Header title="Settings" />

      <box
        border
        borderColor={theme.border}
        backgroundColor={theme.bg}
        flexGrow={1}
        flexDirection="column"
        padding={1}
      >
        <SettingRow label="theme" value={curTheme} active={sel === 0} />
        <SettingRow label="default sort" value={curSort} active={sel === 1} />
        <SettingRow label="col · name" value={cols.name ? "[x]" : "[ ]"} active={sel === 2} />
        <SettingRow label="col · pid" value={cols.pid ? "[x]" : "[ ]"} active={sel === 3} />
        <SettingRow label="col · mfa" value={cols.mfa ? "[x]" : "[ ]"} active={sel === 4} />
        <SettingRow label="col · info" value={cols.info ? "[x]" : "[ ]"} active={sel === 5} />
        <SettingRow
          label="default limits"
          value={`keep ${limits.keep} · time ${limits.time}s · msgs ${limits.msgs}`}
          active={sel === 6}
        />
        <box flexDirection="row">
          <text fg={theme.dim}>{fit("$EDITOR", 16)}</text>
          <text fg={theme.dim}>{`${editor} (read-only · set via env)`}</text>
        </box>
        <text fg={theme.dim}>ts and k columns are always shown.</text>
      </box>

      <Footer text="j/k move · space/enter toggle or cycle · esc back" />

      {limitsDraft !== null && (
        <Overlay>
          <TextField
            label="Default limits — keep time msgs (space-separated):"
            initial={limitsDraft}
            onSubmit={(v) => {
              const p = parseLimits(v)
              if (p) dispatch({ default_limits: p })
              setLimitsDraft(null)
            }}
          />
        </Overlay>
      )}
    </box>
  )
}

function SettingRow({ label, value, active }: { label: string; value: string; active: boolean }) {
  const bg = active ? theme.selBg : theme.bg
  const fg = active ? theme.selFg : theme.fg
  return (
    <box backgroundColor={bg} flexDirection="row">
      <text bg={bg} fg={theme.dim}>{fit(label, 16)}</text>
      <text bg={bg} fg={fg}>{value}</text>
    </box>
  )
}

function fit(s: string, n: number): string {
  if (s.length > n) return s.slice(0, Math.max(0, n - 1)) + "…"
  return s.padEnd(n)
}

function parseLimits(s: string): { keep: number; time: number; msgs: number } | null {
  const parts = s.trim().split(/\s+/).map(Number)
  if (parts.length !== 3 || parts.some((x) => !Number.isFinite(x) || x < 0)) return null
  return { keep: parts[0], time: parts[1], msgs: parts[2] }
}
