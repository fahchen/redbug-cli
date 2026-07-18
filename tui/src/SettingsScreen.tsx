/** @jsxImportSource @opentui/react */
import { useState } from "react"
import { useKeyboard } from "@opentui/react"
import type { StoreProxy } from "@musubi/react"

import { SETTINGS_ROOT, dispatcher, useMusubiRoot, useMusubiSnapshot } from "./musubi"
import { DEFAULT_LIMITS, formatLimits, parseLimits } from "./limits"
import { editorArgv } from "./editor"
import { theme, themeNames } from "./theme"
import { HelpOverlay, Overlay, RootGate, TextField, fit } from "./ui"

type SettingsStore = StoreProxy<"Server.Stores.SettingsRoot", Musubi.Stores>
type Settings = Server.Schema.Settings

type ColKey = "name" | "pid" | "mfa" | "info"
const COL_KEYS: ColKey[] = ["name", "pid", "mfa", "info"]
const SORT_VALUES = ["ts_desc", "ts_asc", "kind_asc", "kind_desc", "pid_asc", "mfa_asc"]

// Settings is a centered modal opened from the tree (`,`), not a full page.
export function SettingsOverlay({ onClose }: { onClose: () => void }) {
  const root = useMusubiRoot(SETTINGS_ROOT)
  return (
    <RootGate root={root} loading="Loading settings…" errorLabel="Settings">
      {(store) => <SettingsView store={store} onClose={onClose} />}
    </RootGate>
  )
}

function SettingsView({ store, onClose }: { store: SettingsStore; onClose: () => void }) {
  const snap = useMusubiSnapshot(store)
  const s = snap?.settings as Settings | undefined
  const cols = s?.columns ?? { name: true, pid: true, mfa: true, info: true }
  const limits = s?.default_limits ?? DEFAULT_LIMITS
  const curTheme = s?.theme ?? "dark"
  const curSort = s?.default_sort ?? "ts_desc"
  const showHints = s?.show_hints ?? true
  const consoleTimeout = s?.console_timeout ?? 15000
  const editor = editorArgv().join(" ")

  const [sel, setSel] = useState(0)
  const [limitsDraft, setLimitsDraft] = useState<string | null>(null)
  const [timeoutDraft, setTimeoutDraft] = useState<string | null>(null)
  const [help, setHelp] = useState(false)

  const rowCount = 9 // theme, sort, 4 columns, limits, show hints, console timeout

  const send = dispatcher(store)
  const dispatch = (payload: any) => send("updateSettings", payload)

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
      setLimitsDraft(formatLimits(limits))
    } else if (sel === 7) {
      dispatch({ show_hints: !showHints })
    } else if (sel === 8) {
      // open empty (current shown as placeholder) so typing replaces, not appends
      setTimeoutDraft("")
    }
  }

  useKeyboard((key) => {
    const n = key.name
    if (help) {
      setHelp(false)
      return
    }
    if (limitsDraft !== null) {
      if (n === "escape") setLimitsDraft(null)
      return
    }
    if (timeoutDraft !== null) {
      if (n === "escape") setTimeoutDraft(null)
      return
    }
    if (n === "?") {
      setHelp(true)
      return
    }
    switch (n) {
      case "escape":
        onClose()
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
    <>
      <Overlay title="Settings" minWidth={66}>
        <SettingRow label="Theme" value={curTheme} active={sel === 0} />
        <SettingRow label="Default sort" value={curSort} active={sel === 1} />
        <SettingRow label="Col · name" value={cols.name ? "[x]" : "[ ]"} active={sel === 2} spacedAbove />
        <SettingRow label="Col · pid" value={cols.pid ? "[x]" : "[ ]"} active={sel === 3} />
        <SettingRow label="Col · mfa" value={cols.mfa ? "[x]" : "[ ]"} active={sel === 4} />
        <SettingRow label="Col · info" value={cols.info ? "[x]" : "[ ]"} active={sel === 5} />
        <SettingRow
          label="Default limits"
          value={`keep ${limits.keep} · time ${limits.time}s · msgs ${limits.msgs}`}
          active={sel === 6}
          spacedAbove
        />
        <SettingRow label="Show hints" value={showHints ? "[x]" : "[ ]"} active={sel === 7} spacedAbove />
        <SettingRow
          label="Console timeout"
          value={`${Math.round(consoleTimeout / 1000)}s`}
          active={sel === 8}
          spacedAbove
        />
        <box flexDirection="row" marginTop={1}>
          <text fg={theme.dim}>{fit("$EDITOR", 16)}</text>
          <text fg={theme.dim}>{`${editor} (read-only · set via env)`}</text>
        </box>
        <text fg={theme.dim}>ts and k columns are always shown.</text>
        <text fg={theme.dim} marginTop={1}>j/k move · space toggle · ? help · esc close</text>
      </Overlay>

      {help && (
        <HelpOverlay
          title="settings"
          sections={[
            {
              lines: [
                ["j / k", "move"],
                ["space / enter / right / l", "toggle or cycle value"],
                ["esc", "close"]
              ]
            },
            {
              lines: [
                ["$EDITOR", "read-only; set via the env var"]
              ]
            }
          ]}
        />
      )}

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

      {timeoutDraft !== null && (
        <Overlay>
          <TextField
            label={`Console timeout — seconds (current ${Math.round(consoleTimeout / 1000)}s · blank = keep):`}
            hint={String(Math.round(consoleTimeout / 1000))}
            onSubmit={(v) => {
              const t = v.trim()
              if (t !== "") {
                const secs = parseInt(t, 10)
                if (Number.isFinite(secs) && secs > 0) dispatch({ console_timeout: secs * 1000 })
              }
              setTimeoutDraft(null)
            }}
          />
        </Overlay>
      )}
    </>
  )
}

function SettingRow({
  label,
  value,
  active,
  spacedAbove
}: {
  label: string
  value: string
  active: boolean
  spacedAbove?: boolean
}) {
  const bg = active ? theme.selBg : theme.overlay
  const fg = active ? theme.selFg : theme.fg
  return (
    <box backgroundColor={bg} flexDirection="row" marginTop={spacedAbove ? 1 : 0}>
      <text bg={bg} fg={theme.dim}>{fit(label, 16)}</text>
      <text bg={bg} fg={fg}>{value}</text>
    </box>
  )
}
