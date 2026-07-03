/** @jsxImportSource @opentui/react */
import { createContext, useContext, useState } from "react"
import type { ReactNode } from "react"
import { useTerminalDimensions } from "@opentui/react"

import { theme, type Theme } from "./theme"
import { colorizeTerm, type TermRole } from "./term"

// Semantic hue per term role, drawn from the active theme so it re-tints with
// the palette. Detail/console payloads are data-viz, so a full-palette read is
// warranted here (unlike the restrained event stream).
const termColor = (role: TermRole): keyof Theme =>
  role === "str" ? "on"
  : role === "num" ? "send"
  : role === "atom" ? "recv"
  : role === "key" ? "title"
  : role === "ref" ? "dim"
  : "fg"

// Render one already-wrapped line of an Elixir/Erlang term with semantic color.
export function TermLine({ line, bg }: { line: string; bg?: string }) {
  const segs = colorizeTerm(line)
  return (
    <box backgroundColor={bg ?? theme.bg} flexDirection="row">
      {segs.map((s, i) => (
        <text key={i} bg={bg ?? theme.bg} fg={theme[termColor(s.role)]}>{s.t}</text>
      ))}
    </box>
  )
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
  tone = "dim",
  hints
}: {
  statusText?: string
  tone?: keyof Theme
  hints?: string
}) {
  const showHints = useContext(HintContext)
  const { width } = useTerminalDimensions()
  const left = statusText ?? ""
  const budget = Math.max(0, width - left.length - 4)
  const hintText = showHints && hints ? truncate(hints, budget) : ""
  return (
    <box backgroundColor={theme.overlay} paddingLeft={1} paddingRight={1} flexDirection="row">
      {left !== "" && (
        <text bg={theme.overlay} fg={theme[tone]}>
          {left}
        </text>
      )}
      {hintText !== "" && (
        <text bg={theme.overlay} fg={theme.dim}>
          {(left !== "" ? "   " : "") + hintText}
        </text>
      )}
    </box>
  )
}

// One-line peek of the selected row's full value, shown above the StatusBar when
// the list column truncated it. Cheap progressive disclosure: read the whole
// payload without opening (and later closing) the Detail pane.
export function InfoPeek({ text }: { text: string }) {
  const { width } = useTerminalDimensions()
  return (
    <box backgroundColor={theme.overlay} paddingLeft={1} paddingRight={1} flexDirection="row">
      <text bg={theme.overlay} fg={theme.dim}>{truncate(`▸ ${text}`, Math.max(0, width - 2))}</text>
    </box>
  )
}

// Top title bar shared by every screen. `children` carry per-screen status/info
// chips that sit to the right of the title.
export function Header({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <box backgroundColor={theme.bg} paddingLeft={1} flexDirection="row">
      <text fg={theme.title}>{title}</text>
      {children}
    </box>
  )
}

// Full-screen centered modal. With `title` set, the title sits above a spaced
// body; without it, children render flush (callers that own their own heading).
export function Overlay({
  title,
  minWidth = 60,
  children
}: {
  title?: string
  minWidth?: number
  children: ReactNode
}) {
  return (
    <box
      position="absolute"
      top={0}
      left={0}
      right={0}
      bottom={0}
      justifyContent="center"
      alignItems="center"
    >
      <box
        border
        borderColor={theme.title}
        backgroundColor={theme.overlay}
        flexDirection="column"
        paddingTop={1}
        paddingBottom={1}
        paddingLeft={3}
        paddingRight={3}
        minWidth={minWidth}
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

export function PickRow({ label, active }: { label: string; active: boolean }) {
  const bg = active ? theme.selBg : theme.overlay
  const fg = active ? theme.selFg : theme.fg
  return (
    <box backgroundColor={bg}>
      <text bg={bg} fg={fg}>{`${active ? "›" : " "} ${label}`}</text>
    </box>
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
      <text fg={theme.title}>{`› ${label}`}</text>
      {hint && <text fg={theme.dim}>{`  ${hint}`}</text>}
      <input
        focused
        value={value}
        onInput={(v: string) => setValue(v)}
        onSubmit={() => onSubmit(value)}
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

function wrapText(s: string, width: number): string[] {
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
