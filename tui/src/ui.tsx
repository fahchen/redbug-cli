/** @jsxImportSource @opentui/react */
import { createContext, useContext, useEffect, useState } from "react"
import type { ReactNode } from "react"
import { useTerminalDimensions } from "@opentui/react"
import { RGBA } from "@opentui/core"

import { theme, type Theme, PANEL_BORDER } from "./theme"

// Translucent scrim drawn behind every modal so the content underneath dims and
// stops competing for focus (opentui alpha-composites this over the buffer below).
const SCRIM = RGBA.fromValues(0, 0, 0, 0.78)

// opencode's braille spinner: smooth, 1-wide, not a round glyph.
const SPIN_FRAMES = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
const SPIN_INTERVAL = 80

// Advance a spinner while `active`; returns the current frame ("" when idle).
export function useSpinner(active: boolean): string {
  const [i, setI] = useState(0)
  useEffect(() => {
    if (!active) return
    const id = setInterval(() => setI((n) => n + 1), SPIN_INTERVAL)
    return () => clearInterval(id)
  }, [active])
  return active ? SPIN_FRAMES[i % SPIN_FRAMES.length] : ""
}

// Whether keybind hint footers are shown (driven by the `show_hints` setting).
// Defaults to true so screens render hints even without an enclosing provider.
const HintContext = createContext(true)

export function HintProvider({ show, children }: { show: boolean; children: ReactNode }) {
  return <HintContext.Provider value={show}>{children}</HintContext.Provider>
}

// Single bottom statusline shared by every screen. The status segment (left) is
// always shown; the keybind hints (right) are gated by `show_hints` and
// truncated so the row never wraps. Sits on the overlay tone so it reads as a
// statusline distinct from page content. Keep `hints` short — the full keymap
// lives in each screen's `?` overlay.
export function StatusBar({
  statusText,
  statChip,
  tone = "dim",
  hints
}: {
  statusText?: string
  statChip?: ReactNode
  tone?: keyof Theme
  hints?: string
}) {
  const showHints = useContext(HintContext)
  const { width } = useTerminalDimensions()
  const left = statusText ?? ""
  const budget = Math.max(0, width - left.length - 4)
  const hintText = showHints && hints ? truncate(hints, budget) : ""
  // arcade HUD: each hint reads as a button prompt — the leading key token pops
  // in the title hue, the rest stays dim. Segments split on " · ".
  const segs = hintText === "" ? [] : hintText.split(" · ")
  return (
    <box backgroundColor={theme.background} paddingLeft={1} paddingRight={1} flexDirection="row">
      {statChip}
      {left !== "" && (
        <text bg={theme.background} fg={theme[tone]}>
          {left}
        </text>
      )}
      {segs.length > 0 && <text bg={theme.background} fg={theme.dim}>{left !== "" ? "   " : ""}</text>}
      {segs.map((seg, i) => {
        const sp = seg.indexOf(" ")
        const key = sp < 0 ? seg : seg.slice(0, sp)
        const label = sp < 0 ? "" : seg.slice(sp)
        return (
          <box key={i} flexDirection="row" backgroundColor={theme.background}>
            <text bg={theme.background} fg={theme.title}>{key}</text>
            <text bg={theme.background} fg={theme.dim}>{label}{i < segs.length - 1 ? " · " : ""}</text>
          </box>
        )
      })}
    </box>
  )
}


// Framed pane: a bordered box whose `heading` rides the top border line (opentui
// box title). Focus brightens both the title and the border (primary/borderActive
// vs textMuted/borderSubtle).
export function Panel({
  heading,
  active = false,
  width,
  grow = false,
  children
}: {
  heading?: string
  active?: boolean
  width?: number
  grow?: boolean
  children: ReactNode
}) {
  return (
    <box
      border
      borderStyle={PANEL_BORDER}
      borderColor={active ? theme.borderActive : theme.borderSubtle}
      title={heading !== undefined ? ` ${heading} ` : undefined}
      titleColor={active ? theme.primary : theme.textMuted}
      backgroundColor={theme.background}
      width={width}
      flexGrow={grow ? 1 : undefined}
      flexBasis={grow ? 0 : undefined}
      flexDirection="column"
      padding={1}
    >
      {children}
    </box>
  )
}

// A key–value chip: two adjoining background blocks — a brighter label block and
// a dimmer value block — reading as one pill. Used wherever compact labeled
// metadata appears in a row (node detail, event detail, panel meta).
export function Chip({
  label,
  value,
  tone = "default"
}: {
  label: string
  value: string
  tone?: "default" | "error"
}) {
  const valueFg = tone === "error" ? theme.error : theme.text
  return (
    <box flexDirection="row" marginRight={1}>
      <text bg={theme.backgroundElement} fg={theme.textMuted}>{` ${label} `}</text>
      <text bg={theme.backgroundPanel} fg={valueFg}>{` ${value} `}</text>
    </box>
  )
}

// Full-screen centered modal. With `title` set, the title sits above a spaced
// body; without it, children render flush (callers that own their own heading).
export function Overlay({
  title,
  minWidth = 60,
  width,
  height,
  children
}: {
  title?: string
  minWidth?: number
  width?: number
  height?: number
  children: ReactNode
}) {
  // Modals are frameless: a filled panel floating on the dimmed scrim, no border
  // (the scrim + panel bg carry the separation).
  return (
    <box
      position="absolute"
      top={0}
      left={0}
      right={0}
      bottom={0}
      backgroundColor={SCRIM}
      justifyContent="center"
      alignItems="center"
    >
      <box
        backgroundColor={theme.overlay}
        flexDirection="column"
        paddingTop={1}
        paddingBottom={1}
        paddingLeft={3}
        paddingRight={3}
        minWidth={minWidth}
        width={width}
        height={height}
      >
        {title && <text fg={theme.title}>{title}</text>}
        {title ? (
          <box flexDirection="column" marginTop={1}>
            {children}
          </box>
        ) : (
          children
        )}
      </box>
    </box>
  )
}

// Per-page help overlay: one or more sections of `key  description` lines.
export type HelpSection = { title?: string; lines: [string, string][] }

export function HelpOverlay({ title, sections }: { title: string; sections: HelpSection[] }) {
  const keyWidth = Math.max(
    ...sections.flatMap((sec) => sec.lines.map(([k]) => k.length))
  )
  return (
    <Overlay title={title}>
      {sections.map((sec, i) => (
        <box key={i} flexDirection="column" marginTop={i === 0 ? 0 : 1}>
          {sec.title && <text fg={theme.dim}>{sec.title}</text>}
          {sec.lines.map(([k, desc], j) => (
            <box key={j} flexDirection="row">
              <text fg={theme.title}>{k.padEnd(keyWidth)}</text>
              <text fg={theme.fg}>{`   ${desc}`}</text>
            </box>
          ))}
        </box>
      ))}
      <text fg={theme.dim} marginTop={1}>press ? or Esc to close</text>
    </Overlay>
  )
}

export function TextField({
  label,
  initial,
  hint,
  onSubmit
}: {
  label: string
  initial?: string
  hint?: string
  onSubmit: (value: string) => void
}) {
  const [value, setValue] = useState(initial ?? "")
  return (
    <box flexDirection="column">
      <text fg={theme.title}>{label}</text>
      <input
        focused
        value={value}
        onInput={(v: string) => setValue(v)}
        onSubmit={() => onSubmit(value)}
        placeholder={hint}
        backgroundColor={theme.bg}
        textColor={theme.fg}
        focusedBackgroundColor={theme.selBg}
        focusedTextColor={theme.selFg}
      />
      <text fg={theme.dim} marginTop={1}>Enter ok · Esc cancel</text>
    </box>
  )
}

// Sticky one-line error banner (vim/emacs minibuffer style), sits just above
// the StatusBar. Glyph + semantic color carry the meaning — no side-stripe
// border (banned). Stays until the next action clears it server-side or the
// user dismisses it. `error.detail` (long redbug/exception text) opens via `e`.
// ponytail: error-only for now; add a `warn` level + ⚠ glyph when a producer exists.
export function Flash({
  error,
  hint
}: {
  error: { message: string; detail?: string | null }
  hint?: string
}) {
  const { width } = useTerminalDimensions()
  const tail = hint ?? (error.detail ? "e detail · d dismiss" : "d dismiss")
  const suffix = tail === "" ? "" : `  · ${tail}`
  const budget = Math.max(0, width - 4 - suffix.length)
  return (
    <box backgroundColor={theme.overlay} paddingLeft={1} paddingRight={1} flexDirection="row">
      <text bg={theme.overlay} fg={theme.err}>{`✗ ${truncate(error.message, budget)}`}</text>
      <text bg={theme.overlay} fg={theme.dim}>{suffix}</text>
    </box>
  )
}

// Full-text error overlay for long redbug/exception output that the Flash line
// truncates. Reuses Overlay; wraps the body so it never overflows the box.
export function ErrorDetailOverlay({ title = "Error", body }: { title?: string; body: string }) {
  const lines = body.split("\n").flatMap((l) => wrapText(l, 72))
  return (
    <Overlay title={title} minWidth={76}>
      <box flexDirection="column">
        {lines.map((l, i) => (
          <text key={i} fg={theme.fg}>{l}</text>
        ))}
      </box>
      <text fg={theme.dim} marginTop={1}>press e or Esc to close</text>
    </Overlay>
  )
}

export function wrapText(s: string, width: number): string[] {
  if (s.length <= width) return [s === "" ? " " : s]
  const out: string[] = []
  for (let i = 0; i < s.length; i += width) out.push(s.slice(i, i + width))
  return out
}

export function truncate(s: string, n: number): string {
  if (s.length <= n) return s
  return s.slice(0, Math.max(0, n - 1)) + "…"
}

// Truncate to `n` (with ellipsis) and pad to a fixed width — for table columns.
export function fit(s: string, n: number): string {
  if (s.length > n) return s.slice(0, Math.max(0, n - 1)) + "…"
  return s.padEnd(n)
}

// Full-screen single-line message (loading / error states).
export function Notice({ text, tone = "info" }: { text: string; tone?: "info" | "error" }) {
  return (
    <box backgroundColor={theme.bg} flexGrow={1} padding={1}>
      <text fg={tone === "error" ? theme.off : theme.fg}>{text}</text>
    </box>
  )
}

type RootState<S> =
  | { status: "loading" }
  | { status: "error"; error: { message: string } }
  | { status: string; store: S }

// Gate a single musubi root: render loading/error notices, else hand the store
// to `children`. Collapses the boilerplate every screen used to repeat.
export function RootGate<S>({
  root,
  loading,
  errorLabel,
  children
}: {
  root: RootState<S>
  loading: string
  errorLabel: string
  children: (store: NonNullable<S>) => ReactNode
}): ReactNode {
  if (root.status === "loading") return <Notice text={loading} />
  if (root.status === "error")
    return <Notice tone="error" text={`${errorLabel} error: ${(root as { error: { message: string } }).error.message}`} />
  return children((root as { store: S }).store as NonNullable<S>)
}
