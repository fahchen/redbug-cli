/** @jsxImportSource @opentui/react */
import { RTP_EXAMPLES } from "./sessionTypes"
import { theme } from "./theme"

/** RTP cheat-sheet shown below add/edit trace forms. */
export function RtpCheatSheet() {
  return (
    <box flexDirection="column" marginTop={1}>
      <text fg={theme.textMuted}>Common RTP rules (Elixir)</text>
      {RTP_EXAMPLES.map(([pat, desc]) => (
        <box key={pat} flexDirection="row">
          <text fg={theme.dim}>{pat.padEnd(38)}</text>
          <text fg={theme.dim}>{desc}</text>
        </box>
      ))}
    </box>
  )
}
