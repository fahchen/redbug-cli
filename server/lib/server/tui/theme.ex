defmodule Server.Tui.Theme do
  @moduledoc """
  The colours of the Terra TUI: the tokyo-night roles of `tui/src/theme.ts`,
  each mapped to the nearest colour of the 256-colour palette, because Terra
  has no truecolor (see `docs/terra-gaps.md`).
  """

  # tokyo-night hex value -> nearest 256-colour index
  @colors %{
    # #c0caf5
    text: 153,
    # #565f89
    muted: 60,
    # #7aa2f7
    title: 111,
    # #3b4261
    border: 239,
    # #20263c, the selected row and the chip label
    element: 236,
    # #1f2335, the chip value
    panel: 235,
    # #9ece6a
    success: 149,
    # #e0af68
    warning: 179,
    # #f7768e
    error: 210
  }

  @spec color(atom()) :: 0..255
  def color(role), do: Map.fetch!(@colors, role)

  @doc "The `Terra.Theme` of the runtime: box borders and the accent."
  @spec terra() :: map()
  def terra, do: %{accent: color(:title), border: color(:border)}
end
