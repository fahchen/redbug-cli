// Raw palette a theme defines. Semantic tokens (below) are derived from these so
// every theme only has to specify the base once.
type BaseTheme = {
  bg: string
  fg: string
  dim: string
  border: string
  title: string
  accent: string
  selBg: string
  selFg: string
  overlay: string
  on: string
  off: string
  warn: string
  err: string
  call: string
  retn: string
  send: string
  recv: string
}

// opencode-style semantic tokens layered over the base. New code should use these
// (text/textMuted/background*/border*/primary/error/…); the legacy base keys stay
// during the redesign migration and are dropped once every screen is ported.
export type Theme = BaseTheme & {
  background: string
  backgroundPanel: string
  backgroundElement: string
  backgroundMenu: string
  text: string
  textMuted: string
  primary: string
  error: string
  warning: string
  success: string
  info: string
  borderSubtle: string
  borderActive: string
  selectedForeground: string
}

const base: BaseTheme = {
  bg: "#101418",
  fg: "#d7dde3",
  dim: "#6b7480",
  border: "#3a424c",
  title: "#5eb0ff",
  accent: "#5eb0ff",
  selBg: "#1f3a5f",
  selFg: "#ffffff",
  overlay: "#1a2129",
  on: "#5fd38a",
  off: "#a0664b",
  warn: "#e0b341",
  err: "#e06c75",
  call: "#5eb0ff",
  retn: "#5fd38a",
  send: "#e0b341",
  recv: "#c08af0"
}

// Mix two hex colors (t in 0..1). Used to soften the selection fill so it reads
// as a gentle lift off the background, not a hard block.
function blend(a: string, b: string, t: number): string {
  const p = (h: string, i: number) => parseInt(h.replace("#", "").slice(i, i + 2), 16)
  const mix = (i: number) => Math.round(p(a, i) * (1 - t) + p(b, i) * t)
  const hex = (n: number) => n.toString(16).padStart(2, "0")
  return `#${hex(mix(0))}${hex(mix(2))}${hex(mix(4))}`
}

const semantic = (t: BaseTheme): Theme => ({
  ...t,
  background: t.bg,
  backgroundPanel: t.overlay,
  // selection: a soft ~40% lift toward selBg, not the full (heavy) selBg
  backgroundElement: blend(t.bg, t.selBg, 0.45),
  backgroundMenu: t.overlay,
  text: t.fg,
  textMuted: t.dim,
  primary: t.title,
  error: t.err,
  warning: t.warn,
  success: t.on,
  info: t.call,
  borderSubtle: t.border,
  borderActive: t.title,
  selectedForeground: t.selFg
})

const def = (over: Partial<BaseTheme>): Theme => semantic({ ...base, ...over })

// Border style for framed panels/overlays. "heavy" reads as a chunky 8-bit
// cartridge frame; opentui also offers "single" | "double" | "rounded".
export type PanelBorder = "single" | "double" | "rounded" | "heavy"
export const PANEL_BORDER: PanelBorder = "double"

export const themes: Record<string, Theme> = {
  // 8-bit / PICO-8 arcade palette: dark blue-black base, saturated status hues.
  // Kept first + used as the default so the whole TUI reads retro out of the box.
  "pico-8": def({
    bg: "#100f1c",
    fg: "#fff1e8",
    dim: "#5f574f",
    border: "#29adff",
    title: "#ffec27",
    accent: "#ff77a8",
    selBg: "#7e2553",
    selFg: "#fff1e8",
    overlay: "#1d2b53",
    on: "#00e436",
    off: "#5f574f",
    warn: "#ffa300",
    err: "#ff004d",
    call: "#29adff",
    retn: "#00e436",
    send: "#ffec27",
    recv: "#83769c"
  }),
  dark: def({}),
  light: def({
    bg: "#fafafa",
    fg: "#1f2328",
    dim: "#8a9099",
    border: "#c4cad1",
    title: "#0969da",
    accent: "#0969da",
    selBg: "#cfe3ff",
    selFg: "#0a0c10",
    overlay: "#eef1f4",
    on: "#1a7f37",
    off: "#bc4c00",
    warn: "#9a6700",
    err: "#cf222e",
    call: "#0969da",
    retn: "#1a7f37",
    send: "#9a6700",
    recv: "#8250df"
  }),
  "tokyo-night": def({
    bg: "#1a1b26",
    fg: "#c0caf5",
    dim: "#565f89",
    border: "#3b4261",
    title: "#7aa2f7",
    accent: "#7aa2f7",
    selBg: "#283457",
    selFg: "#c0caf5",
    overlay: "#1f2335",
    on: "#9ece6a",
    off: "#f7768e",
    warn: "#e0af68",
    err: "#f7768e",
    call: "#7aa2f7",
    retn: "#9ece6a",
    send: "#e0af68",
    recv: "#bb9af7"
  }),
  "tokyo-storm": def({
    bg: "#24283b",
    fg: "#c0caf5",
    dim: "#565f89",
    border: "#414868",
    title: "#7aa2f7",
    accent: "#7aa2f7",
    selBg: "#2e3c64",
    selFg: "#c0caf5",
    overlay: "#1f2335",
    on: "#9ece6a",
    off: "#f7768e",
    warn: "#e0af68",
    err: "#f7768e",
    call: "#7aa2f7",
    retn: "#9ece6a",
    send: "#e0af68",
    recv: "#bb9af7"
  }),
  "tokyo-moon": def({
    bg: "#222436",
    fg: "#c8d3f5",
    dim: "#636da6",
    border: "#3b4261",
    title: "#82aaff",
    accent: "#82aaff",
    selBg: "#2f334d",
    selFg: "#c8d3f5",
    overlay: "#1e2030",
    on: "#c3e88d",
    off: "#ff757f",
    warn: "#ffc777",
    err: "#ff757f",
    call: "#82aaff",
    retn: "#c3e88d",
    send: "#ffc777",
    recv: "#c099ff"
  }),
  "tokyo-day": def({
    bg: "#e1e2e7",
    fg: "#3760bf",
    dim: "#848cb5",
    border: "#a8aecb",
    title: "#2e7de9",
    accent: "#2e7de9",
    selBg: "#b6bfe2",
    selFg: "#3760bf",
    overlay: "#d0d5e3",
    on: "#587539",
    off: "#f52a65",
    warn: "#8c6c3e",
    err: "#f52a65",
    call: "#2e7de9",
    retn: "#587539",
    send: "#8c6c3e",
    recv: "#9854f1"
  }),
  "catppuccin-mocha": def({
    bg: "#1e1e2e",
    fg: "#cdd6f4",
    dim: "#6c7086",
    border: "#45475a",
    title: "#89b4fa",
    accent: "#89b4fa",
    selBg: "#313244",
    selFg: "#cdd6f4",
    overlay: "#181825",
    on: "#a6e3a1",
    off: "#f38ba8",
    warn: "#f9e2af",
    err: "#f38ba8",
    call: "#89b4fa",
    retn: "#a6e3a1",
    send: "#f9e2af",
    recv: "#cba6f7"
  }),
  dracula: def({
    bg: "#282a36",
    fg: "#f8f8f2",
    dim: "#6272a4",
    border: "#44475a",
    title: "#bd93f9",
    accent: "#bd93f9",
    selBg: "#44475a",
    selFg: "#f8f8f2",
    overlay: "#21222c",
    on: "#50fa7b",
    off: "#ff5555",
    warn: "#f1fa8c",
    err: "#ff5555",
    call: "#8be9fd",
    retn: "#50fa7b",
    send: "#f1fa8c",
    recv: "#bd93f9"
  }),
  nord: def({
    bg: "#2e3440",
    fg: "#d8dee9",
    dim: "#616e88",
    border: "#434c5e",
    title: "#88c0d0",
    accent: "#88c0d0",
    selBg: "#3b4252",
    selFg: "#eceff4",
    overlay: "#272c36",
    on: "#a3be8c",
    off: "#bf616a",
    warn: "#ebcb8b",
    err: "#bf616a",
    call: "#81a1c1",
    retn: "#a3be8c",
    send: "#ebcb8b",
    recv: "#b48ead"
  }),
  "gruvbox-dark": def({
    bg: "#282828",
    fg: "#ebdbb2",
    dim: "#928374",
    border: "#504945",
    title: "#83a598",
    accent: "#83a598",
    selBg: "#3c3836",
    selFg: "#fbf1c7",
    overlay: "#1d2021",
    on: "#b8bb26",
    off: "#fb4934",
    warn: "#fabd2f",
    err: "#fb4934",
    call: "#83a598",
    retn: "#b8bb26",
    send: "#fabd2f",
    recv: "#d3869b"
  })
}

export const themeNames = Object.keys(themes)

const buildKind = (t: Theme): Record<string, string> => ({
  call: t.call,
  retn: t.retn,
  send: t.send,
  recv: t.recv,
  restart: t.dim
})

export let theme: Theme = themes["tokyo-night"]
export let kindColor: Record<string, string> = buildKind(theme)

export function setTheme(name: string) {
  const next = themes[name] ?? themes["tokyo-night"]
  theme = next
  kindColor = buildKind(next)
}

// Readable foreground for text drawn on an arbitrary background (opencode's
// contrast-aware selected foreground). Relative luminance (sRGB, no gamma — good
// enough for terminal hues) picks the theme's dark vs light text.
export function readableOn(bg: string): string {
  const h = bg.replace("#", "")
  const r = parseInt(h.slice(0, 2), 16)
  const g = parseInt(h.slice(2, 4), 16)
  const b = parseInt(h.slice(4, 6), 16)
  const lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
  return lum > 0.55 ? theme.background : theme.text
}
