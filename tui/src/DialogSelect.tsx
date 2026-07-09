/** @jsxImportSource @opentui/react */
import { useMemo, useState } from "react"
import { useKeyboard } from "@opentui/react"

import { fuzzyMatch, fuzzyScore } from "./fuzzy"
import { theme } from "./theme"
import { Overlay } from "./ui"

export type DialogItem = {
  id: string
  name: string
  query: string       // searchable text (concatenation of name + description)
  description?: string
  keybinding?: string
}

export function DialogSelect({
  title,
  items,
  selectedIndex,
  onSelect,
  onClose
}: {
  title: string
  items: readonly DialogItem[]
  selectedIndex: number
  onSelect: (item: DialogItem) => void
  onClose: () => void
}) {
  const [query, setQuery] = useState("")
  const [sel, setSel] = useState(selectedIndex)

  const filtered = useMemo(() => {
    if (query === "") return items.slice()
    return items
      .map((item) => ({ item, score: fuzzyScore(query, item.query) }))
      .filter(({ item, score }) => score > 0 || fuzzyMatch(query, item.query))
      .sort((a, b) => b.score - a.score)
      .map(({ item }) => item)
  }, [items, query])

  const idx = Math.min(sel, Math.max(0, filtered.length - 1))

  useKeyboard((key) => {
    const n = key.name
    if (n === "escape") {
      onClose()
      return
    }
    if (n === "enter" || n === "return") {
      const item = filtered[idx]
      if (item) onSelect(item)
      return
    }
    if (n === "j" || n === "down") {
      setSel((i) => (i + 1 >= filtered.length ? 0 : i + 1))
      return
    }
    if (n === "k" || n === "up") {
      setSel((i) => (i <= 0 ? Math.max(0, filtered.length - 1) : i - 1))
      return
    }
  })

  // A filter earns its space only with enough options to sift; under 3 (or none)
  // it's just noise, so drop it and let the short list speak for itself.
  const hasItems = items.length > 0
  const showFilter = items.length >= 3

  return (
    <Overlay title={title}>
      {showFilter && (
        <input
          focused
          value={query}
          onInput={(v: string) => { setQuery(v); setSel(0) }}
          placeholder="filter…"
          backgroundColor={theme.bg}
          textColor={theme.fg}
          focusedBackgroundColor={theme.selBg}
          focusedTextColor={theme.selFg}
        />
      )}
      <box flexDirection="column" marginTop={1} minHeight={Math.min(filtered.length, 10)}>
        {!hasItems ? (
          <text fg={theme.dim}>nothing to pick</text>
        ) : filtered.length === 0 ? (
          <text fg={theme.dim}>no matches</text>
        ) : (
          filtered.slice(0, 20).map((item, i) => {
            const active = i === idx
            const bg = active ? theme.backgroundElement : theme.overlay
            return (
              <box key={item.id} backgroundColor={bg} flexDirection="row" paddingLeft={1} paddingRight={1}>
                <box flexDirection="column" flexGrow={1}>
                  <text bg={bg} fg={active ? theme.text : theme.textMuted}>{item.name}</text>
                  {item.description && (
                    <text bg={bg} fg={theme.dim}>{item.description}</text>
                  )}
                </box>
                {item.keybinding && (
                  <text bg={bg} fg={theme.dim}>{item.keybinding}</text>
                )}
              </box>
            )
          })
        )}
      </box>
      <text fg={theme.dim} marginTop={1}>
        {showFilter ? "type to filter · j/k move · Enter select · Esc cancel"
          : hasItems ? "j/k move · Enter select · Esc cancel"
          : "Esc cancel"}
      </text>
    </Overlay>
  )
}
