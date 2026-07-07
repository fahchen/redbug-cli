/** @jsxImportSource @opentui/react */
import { theme } from "./theme"

export function SessionStat({
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
