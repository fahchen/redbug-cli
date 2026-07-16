/** @jsxImportSource @opentui/react */
import { useEffect, useState } from "react"
import { createTextAttributes } from "@opentui/core"
import { createHighlighter } from "@lumis-sh/lumis"
import type { Highlighter, Theme } from "@lumis-sh/lumis"
import elixir from "@lumis-sh/lumis/langs/elixir"

import tokyonight_night from "@lumis-sh/themes/tokyonight_night"
import tokyonight_storm from "@lumis-sh/themes/tokyonight_storm"
import tokyonight_moon from "@lumis-sh/themes/tokyonight_moon"
import tokyonight_day from "@lumis-sh/themes/tokyonight_day"
import catppuccin_mocha from "@lumis-sh/themes/catppuccin_mocha"
import catppuccin_latte from "@lumis-sh/themes/catppuccin_latte"
import catppuccin_frappe from "@lumis-sh/themes/catppuccin_frappe"
import catppuccin_macchiato from "@lumis-sh/themes/catppuccin_macchiato"
import gruvbox_dark from "@lumis-sh/themes/gruvbox_dark"
import rosepine_dark from "@lumis-sh/themes/rosepine_dark"
import onedark from "@lumis-sh/themes/onedark"

import { currentThemeName, theme } from "./theme"

// App theme name → lumis (Neovim) theme. pico-8 and any unknown fall back to a
// dark default so code still highlights sensibly.
const THEMES: Record<string, Theme> = {
  "tokyo-night": tokyonight_night,
  "tokyo-storm": tokyonight_storm,
  "tokyo-moon": tokyonight_moon,
  "tokyo-day": tokyonight_day,
  "catppuccin-mocha": catppuccin_mocha,
  "catppuccin-latte": catppuccin_latte,
  "catppuccin-frappe": catppuccin_frappe,
  "catppuccin-macchiato": catppuccin_macchiato,
  "gruvbox-dark": gruvbox_dark,
  "rose-pine": rosepine_dark,
  "one-dark": onedark
}
const FALLBACK = tokyonight_night

type Chunk = { text: string; fg?: string; attributes: number }

// Loading the Elixir grammar WASM is async; do it once and reuse the highlighter
// (its `highlightIter` is then synchronous). Call `warmHighlighter()` at startup
// so the first code block paints highlighted.
let hlPromise: Promise<Highlighter> | null = null
export function warmHighlighter(): Promise<Highlighter> {
  return (hlPromise ??= createHighlighter({ languages: [elixir] }))
}

async function highlightElixir(code: string, nvimTheme: Theme): Promise<Chunk[]> {
  const hl = await warmHighlighter()
  const chunks: Chunk[] = []
  hl.highlightIter(code, "elixir", nvimTheme, (text, _lang, _range, _scope, style) => {
    chunks.push({
      text,
      fg: style?.fg,
      attributes: createTextAttributes({
        bold: !!style?.bold,
        italic: !!style?.italic,
        underline: !!style?.underline
      })
    })
  })
  return chunks
}

// Syntax-highlighted Elixir via lumis. Highlighting is async (WASM), so render
// plain text until the chunks resolve; a failure also falls back to plain text
// rather than blanking the block.
export function CodeBlock({ content }: { content: string }) {
  const [chunks, setChunks] = useState<Chunk[] | null>(null)
  const nvimName = currentThemeName

  useEffect(() => {
    let alive = true
    highlightElixir(content, THEMES[nvimName] ?? FALLBACK)
      .then((c) => alive && setChunks(c))
      .catch(() => alive && setChunks(null))
    return () => {
      alive = false
    }
  }, [content, nvimName])

  if (!chunks) return <text fg={theme.text}>{content}</text>
  return (
    <text>
      {chunks.map((c, i) => (
        <span key={i} fg={c.fg} attributes={c.attributes}>
          {c.text}
        </span>
      ))}
    </text>
  )
}
