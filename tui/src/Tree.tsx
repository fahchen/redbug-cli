/** @jsxImportSource @opentui/react */
import type { ReactNode } from "react"

import { theme } from "./theme"
import { Chip, truncate, useSpinner } from "./ui"

type Node = Server.Schema.Node
type Session = Server.Schema.Session

// A directly-dialed node's host must be a real hostname or IP.
export function isValidHost(h: string): boolean {
  const s = h.trim()
  if (s === "") return false
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(s)) return true
  if (!/^[a-zA-Z0-9.\-]+$/.test(s)) return false
  return /[a-zA-Z]/.test(s) || s.includes(".")
}

export function EmptyTree() {
  return (
    <box flexDirection="column">
      <text fg={theme.fg}>No nodes yet</text>
      <text fg={theme.dim} marginTop={1}>Node ▸ Session ▸ Trace</text>
      <text fg={theme.dim}>{"                └ → Events"}</text>
      <text fg={theme.dim} marginTop={1}>a target, a run, a pattern,</text>
      <text fg={theme.dim}>the calls it catches, live.</text>
      <box flexDirection="row" marginTop={1}>
        <text fg={theme.accent}>n</text>
        <text fg={theme.dim}>{"  add your first node"}</text>
      </box>
    </box>
  )
}

export function NodeRow({ node, active }: { node: Node; active: boolean }) {
  const bg = active ? theme.backgroundElement : theme.background
  const spin = useSpinner(node.status === "connecting", "braille")
  const dot =
    node.status === "connected" ? "●"
    : node.status === "connecting" ? spin
    : node.status === "error" ? "✖"
    : " "
  const dotColor =
    node.status === "connected" ? theme.success
    : node.status === "connecting" ? theme.warning
    : node.status === "error" ? theme.error
    : theme.textMuted
  const nameColor = active || node.status === "connected" ? theme.text : theme.textMuted
  const displayName = node.label || node.name
  return (
    <box backgroundColor={bg} flexDirection="row" paddingLeft={1} paddingRight={1}>
      <text bg={bg} fg={dotColor}>{`${dot} `}</text>
      <text bg={bg} fg={nameColor}>{displayName}</text>
      {node.source === "env" && <text bg={bg} fg={theme.textMuted}>{"  env"}</text>}
      <box flexGrow={1} backgroundColor={bg} />
      <text bg={bg} fg={theme.textMuted}>{`${node.sessions.length}`}</text>
    </box>
  )
}

export function SessionRow({
  session,
  index,
  nameWidth,
  active
}: {
  session: Session
  index: number
  nameWidth: number
  active: boolean
}) {
  const bg = active ? theme.backgroundElement : theme.background
  const num = `${index} ·`
  const numFg = active ? theme.accent : theme.textMuted
  const nameFg = active ? theme.text : theme.textMuted
  return (
    <box backgroundColor={bg} flexDirection="row" paddingLeft={1} paddingRight={1}>
      <text bg={bg} fg={numFg}>{num.padStart(4)}</text>
      <text bg={bg} fg={nameFg}>{`  ${truncate(session.name, nameWidth)}`}</text>
    </box>
  )
}

// Redact a cookie to first-2 + last-2, masking the middle.
function redactCookie(c: string | null | undefined): string {
  if (!c) return "—"
  if (c.length <= 4) return "•".repeat(c.length)
  return `${c.slice(0, 2)}••••${c.slice(-2)}`
}

export function NodeDetailBand({ node, error }: { node: Node; error: Server.Schema.AppError | null }) {
  const host = node.ssh_host || (node.name.includes("@") ? node.name.split("@")[1] : node.name)
  const rows: [string, string][] = [
    ["Host", host],
    ["Cookie", redactCookie(node.cookie)]
  ]
  if (node.label) rows.unshift(["Label", node.label])
  if (node.ssh_host) {
    rows.push(["SSH", `${node.ssh_user ? `${node.ssh_user}@` : ""}${node.ssh_host}`])
  }
  if (node.container) rows.push(["Container", node.container])
  if (node.source === "env") rows.push(["Source", "env (read-only)"])
  return (
    <box flexDirection="row" flexWrap="wrap" marginBottom={1}>
      {rows.map(([k, v]) => (
        <Chip key={k} label={k} value={v} />
      ))}
      {error && <Chip label="Error" value={`${error.message} · c retry`} tone="error" />}
    </box>
  )
}
