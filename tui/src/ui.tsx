/** @jsxImportSource @opentui/react */
import { useState } from "react"
import type { ReactNode } from "react"
import { useTerminalDimensions } from "@opentui/react"

import { theme } from "./theme"

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

// Single dim keybind/status line, truncated to the terminal width so it never
// wraps and breaks the layout on narrow terminals.
export function Footer({ text }: { text: string }) {
  const { width } = useTerminalDimensions()
  return (
    <box backgroundColor={theme.bg} paddingLeft={1}>
      <text fg={theme.dim}>{truncate(text, Math.max(0, width - 2))}</text>
    </box>
  )
}

// Full-screen centered modal. With `title` set, the title sits above a spaced
// body; without it, children render flush (callers that own their own heading).
export function Overlay({
  title,
  minWidth = 58,
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
        paddingLeft={2}
        paddingRight={2}
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

export function truncate(s: string, n: number): string {
  if (s.length <= n) return s
  return s.slice(0, Math.max(0, n - 1)) + "…"
}
