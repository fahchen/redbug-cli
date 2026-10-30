defmodule Server.Tui.Highlight do
  @moduledoc """
  Colors a term text with the `makeup_elixir` lexer for the event detail page.
  `lex/1` gives a list of lines; each line is a list of `{text, color}` parts.
  The session screen keeps the result for each event, so the lexer runs once
  for each event, and cuts it with `wrap_lines/2` to the width of the screen
  (Terra has no wrap).
  """

  alias Server.Tui.Theme

  @doc "The colored lines of `text`, not cut to a width. The lexer runs here."
  @spec lex(String.t()) :: [[{String.t(), 0..255}]]
  def lex(text) do
    text
    |> tokens()
    |> Enum.flat_map(fn {color, value} -> split_lines(value, color) end)
    |> Enum.reduce([[]], fn
      :newline, lines -> [[] | lines]
      part, [line | lines] -> [[part | line] | lines]
    end)
    |> Enum.reverse()
    |> Enum.map(&Enum.reverse/1)
  end

  @doc "Cuts each line of parts into lines of `width` cells."
  @spec wrap_lines([[{String.t(), 0..255}]], pos_integer()) :: [[{String.t(), 0..255}]]
  def wrap_lines(lines, width), do: Enum.flat_map(lines, &wrap(&1, max(width, 1)))

  defp tokens(text) do
    Makeup.Lexers.ElixirLexer.lex(text)
    |> Enum.map(fn {type, _meta, value} ->
      {color(type), IO.iodata_to_binary(List.wrap(value))}
    end)
  rescue
    # The lexer gives up on some texts; show them plain.
    _ -> [{Theme.color(:text), text}]
  end

  # :newline marks a line end between parts.
  defp split_lines(value, color) do
    value
    |> String.split("\n")
    |> Enum.map(&{&1, color})
    |> Enum.intersperse(:newline)
    |> Enum.reject(&match?({"", _}, &1))
  end

  # Cut a line of parts into lines of `width` cells.
  defp wrap(parts, width) do
    {lines, current, _used} =
      parts
      |> Enum.flat_map(fn {value, color} -> Enum.map(String.graphemes(value), &{&1, color}) end)
      |> Enum.reduce({[], [], 0}, fn {g, color}, {lines, current, used} ->
        w = Terra.Width.grapheme(g)

        if used + w > width,
          do: {[Enum.reverse(current) | lines], [{g, color}], w},
          else: {lines, [{g, color} | current], used + w}
      end)

    [Enum.reverse(current) | lines]
    |> Enum.reverse()
    |> Enum.map(&merge/1)
  end

  # Join the graphemes of one color into one part.
  defp merge(graphemes) do
    graphemes
    |> Enum.chunk_by(&elem(&1, 1))
    |> Enum.map(fn [{_, color} | _] = run -> {Enum.map_join(run, &elem(&1, 0)), color} end)
  end

  defp color(type) do
    cond do
      type in [:string, :string_double, :string_single, :string_char] -> 149
      type in [:string_symbol, :name_constant] -> 179
      type in [:number_integer, :number_float, :number_bin, :number_oct, :number_hex] -> 210
      type in [:name_class, :name_builtin_pseudo] -> 117
      type in [:keyword, :keyword_constant, :operator_word] -> 176
      type in [:punctuation, :operator] -> Theme.color(:muted)
      type in [:comment, :comment_single] -> Theme.color(:muted)
      true -> Theme.color(:text)
    end
  end
end
