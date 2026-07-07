/** @jsxImportSource @opentui/react */
import type { ReactNode } from "react"
import { theme } from "./theme"
import { Overlay } from "./ui"

interface ConfirmOverlayProps {
  question: string
  hint?: string
  /** y/n labels, e.g. "stop & leave / stay". Defaults to "yes / no". */
  labels?: { y: string; n?: string }
  children?: ReactNode
}

/**
 * Standard confirm dialog with y/n keybinding hint.
 * Displays question, optional extra content (children), and hint.
 */
export function ConfirmOverlay({ question, hint, labels, children }: ConfirmOverlayProps) {
  const yLabel = labels?.y ?? "yes"
  const nLabel = labels?.n ?? "no"
  const hintText = hint ?? `y = ${yLabel} · n/Esc = ${nLabel}`

  return (
    <Overlay>
      <text fg={theme.text}>{question}</text>
      {children}
      <text fg={theme.textMuted} marginTop={1}>{hintText}</text>
    </Overlay>
  )
}
