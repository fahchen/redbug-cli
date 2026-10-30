defmodule Server.Tui.Ui do
  @moduledoc """
  View parts that the node screen and the session screen share: cell fit, the
  spinner, chips, and the status line hints.
  """

  import Terra.View

  alias Server.Tui.Theme

  @spinner ~w(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

  @doc "The spinner glyph of `tick`."
  def spinner(tick), do: Enum.at(@spinner, rem(tick, length(@spinner)))

  @doc "Pads or cuts `string` to `width` cells. A cut string ends with `…`."
  def fit(string, width) do
    cells = Terra.Width.string(string)

    cond do
      cells <= width -> string <> String.duplicate(" ", width - cells)
      width <= 0 -> ""
      true -> cut(String.graphemes(string), width - 1, []) <> "…"
    end
  end

  # The graphemes that fit in `room` cells, padded to `room` cells (a wide
  # grapheme that does not fit leaves one blank cell).
  defp cut([g | rest], room, acc) do
    w = Terra.Width.grapheme(g)
    if w <= room, do: cut(rest, room - w, [g | acc]), else: cut([], room, acc)
  end

  defp cut([], room, acc),
    do: IO.iodata_to_binary([Enum.reverse(acc), String.duplicate(" ", room)])

  @doc "A label and value chip."
  def chip(label, value, tone \\ :text) do
    hstack([
      text(" #{label} ", fg: Theme.color(:muted), bg: Theme.color(:element)),
      text(" #{value} ", fg: Theme.color(tone), bg: Theme.color(:panel))
    ])
  end

  @doc """
  The hint segments of `hints` (segments joined by ` · `), cut to `room` cells
  with a final `…`. The key of each segment (its first word) takes the title
  color.
  """
  def hints(hints, room) do
    hints =
      if String.length(hints) > room,
        do: String.slice(hints, 0, max(room - 1, 0)) <> "…",
        else: hints

    hints
    |> String.split(" · ")
    |> Enum.map(fn segment ->
      case String.split(segment, " ", parts: 2) do
        [key, rest] ->
          [text(key, fg: Theme.color(:title)), text(" " <> rest, fg: Theme.color(:muted))]

        [key] ->
          [text(key, fg: Theme.color(:title))]
      end
    end)
    |> Enum.intersperse([text(" · ", fg: Theme.color(:muted))])
    |> List.flatten()
  end

  @doc "A full-screen page with a border and a title."
  def page(width, height, title, lines) do
    box(vstack(lines),
      title: title,
      width: width,
      height: height,
      padding: [top: 0, right: 2, bottom: 0, left: 2]
    )
  end

  @doc "A full-screen yes or no question."
  def confirm(width, height, question, notes \\ [], labels \\ "y = yes · n/Esc = no") do
    box(
      vstack(
        [text(question, fg: Theme.color(:text))] ++
          Enum.map(notes, &text(&1, fg: Theme.color(:warning))) ++
          [text(""), text(labels, fg: Theme.color(:muted))]
      ),
      width: width,
      height: height,
      align: :center,
      valign: :center
    )
  end

  @doc "Help lines: a key column and an action column."
  def help_lines(rows) do
    Enum.map(rows, fn
      {:section, title} ->
        text(title, fg: Theme.color(:title), bold: true)

      {key, action} ->
        hstack([
          text(String.pad_trailing(key, 12), fg: Theme.color(:title)),
          text(action, fg: Theme.color(:text))
        ])
    end) ++ [text(""), text("press any key to close", fg: Theme.color(:muted))]
  end
end
