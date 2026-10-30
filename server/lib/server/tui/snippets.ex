defmodule Server.Tui.Snippets do
  @moduledoc """
  The snippets screen of the Terra TUI: the snippet list and the code of the
  selected snippet. The keys follow `tui/src/SnippetManager.tsx`. The screen
  calls `Server.Config` directly, as `Server.Stores.SnippetsRoot` and
  `Server.Stores.SnippetStore` do, and formats the code with
  `Server.Code.Format` when it saves the code. It reads the snippets in
  `view/3`, so it always shows the current data.

  The code edits in a single-line input, not in `$EDITOR`: each line break of
  the code shows as `↵` in the input, and each `↵` becomes a line break again
  on save (`docs/terra-gaps.md`).
  """

  import Terra.View

  alias Server.Code.Format
  alias Server.Config
  alias Server.Tui.{Highlight, Theme, Ui}
  alias Terra.Widget

  @list_width 40
  @newline "↵"

  @doc "The screen state."
  def new, do: %{sel: 0, code_page: 0, digits: "", page: :main}

  # --- keys ---

  @doc "Handles a key. `:close` goes back; `{:settings, s}` opens the settings."
  def key(_key, %{page: :help} = s), do: {:ok, %{s | page: :main}}
  def key(key, %{page: {:confirm, _, id}} = s), do: confirm_key(key, id, s)
  def key(key, %{page: {:input, _, _, _}} = s), do: input_key(key, s)
  def key(key, s), do: main_key(key, %{s | digits: ""}, s.digits, current(s))

  # tui/src/SnippetManager.tsx:84-169
  defp main_key(:esc, _s, _digits, _cur), do: :close
  defp main_key({:char, ","}, s, _digits, _cur), do: {:settings, s}
  defp main_key({:char, "?"}, s, _digits, _cur), do: {:ok, %{s | page: :help}}
  defp main_key({:char, "n"}, s, _digits, _cur), do: {:ok, input(s, :new, "")}
  defp main_key(k, s, _digits, _cur) when k in [:down, {:char, "j"}], do: {:ok, move(s, 1)}
  defp main_key(k, s, _digits, _cur) when k in [:up, {:char, "k"}], do: {:ok, move(s, -1)}

  # `<number>g` jumps to the snippet of that number.
  defp main_key({:char, "g"}, s, digits, cur) when digits != "" and cur != nil do
    n = String.to_integer(digits)
    count = length(Config.snippets())
    {:ok, if(n >= 1, do: %{s | sel: min(n - 1, count - 1), code_page: 0}, else: s)}
  end

  defp main_key({:char, d}, s, digits, cur) when d in ~w(0 1 2 3 4 5 6 7 8 9) and cur != nil,
    do: {:ok, %{s | digits: digits <> d}}

  defp main_key(_key, s, _digits, nil), do: {:ok, s}

  # Ctrl+F and Ctrl+B scroll the code by a page. The page count stops at the
  # last line of the code; the view stops at the last full page.
  defp main_key({:ctrl, :f}, s, _digits, cur),
    do: {:ok, %{s | code_page: min(s.code_page + 1, max(line_count(cur.code) - 1, 0))}}

  defp main_key({:ctrl, :b}, s, _digits, _cur),
    do: {:ok, %{s | code_page: max(s.code_page - 1, 0)}}

  defp main_key({:char, "e"}, s, _digits, cur), do: {:ok, code_input(s, cur)}
  defp main_key({:char, "r"}, s, _digits, cur), do: {:ok, input(s, {:rename, cur.id}, cur.name)}

  defp main_key({:char, "f"}, s, _digits, cur) do
    save_formatted(cur.id, cur.code)
    {:ok, s}
  end

  defp main_key({:char, "d"}, s, _digits, cur),
    do: {:ok, %{s | page: {:confirm, ~s(Delete snippet "#{cur.name}"?), cur.id}}}

  defp main_key({:ctrl, :d}, s, _digits, cur), do: {:ok, delete(cur.id, s)}
  defp main_key(_key, s, _digits, _cur), do: {:ok, s}

  # tui/src/SnippetManager.tsx:84-98
  defp confirm_key({:char, "y"}, id, s), do: {:ok, delete(id, %{s | page: :main})}
  defp confirm_key(k, _id, s) when k in [:esc, {:char, "n"}], do: {:ok, %{s | page: :main}}
  defp confirm_key(_key, _id, s), do: {:ok, s}

  defp delete(id, s) do
    Config.delete_snippet(id)
    %{s | sel: max(s.sel - 1, 0), code_page: 0}
  end

  defp input(s, kind, value), do: %{s | page: {:input, kind, value, String.length(value)}}

  defp code_input(s, snippet),
    do: input(s, {:code, snippet.id}, String.replace(snippet.code, "\n", @newline))

  defp input_key(key, %{page: {:input, kind, value, cursor}} = s) do
    case Widget.input_event(key, value, cursor) do
      {:edit, value, cursor} -> {:ok, %{s | page: {:input, kind, value, cursor}}}
      {:submit, value} -> {:ok, submit(kind, value, %{s | page: :main})}
      :cancel -> {:ok, %{s | page: :main}}
      :ignore -> {:ok, s}
    end
  end

  # tui/src/SnippetManager.tsx:49-79 and 229-243: a new snippet gets the
  # selection, and its code input opens.
  defp submit(:new, text, s) do
    case String.trim(text) do
      "" ->
        s

      name ->
        {:ok, id} = Config.add_snippet(%{name: name})
        sel = Enum.find_index(Config.snippets(), &(&1.id == id))
        code_input(%{s | sel: sel, code_page: 0}, %{id: id, code: ""})
    end
  end

  defp submit({:rename, id}, text, s) do
    if String.trim(text) != "", do: Config.update_snippet(id, %{name: text})
    s
  end

  # SnippetStore.updateSnippet: the code is saved formatted.
  defp submit({:code, id}, text, s) do
    save_formatted(id, String.replace(text, @newline, "\n"))
    %{s | code_page: 0}
  end

  defp save_formatted(id, code), do: Config.update_snippet(id, %{code: Format.run(code)})

  defp current(s) do
    case Config.snippets() do
      [] -> nil
      snippets -> Enum.at(snippets, min(s.sel, length(snippets) - 1))
    end
  end

  defp move(s, delta) do
    case length(Config.snippets()) do
      0 -> s
      n -> %{s | sel: Integer.mod(s.sel + delta, n), code_page: 0}
    end
  end

  defp line_count(code), do: code |> String.split("\n") |> length()

  # --- views ---

  @doc "The view of the screen."
  def view(%{page: :help}, width, height),
    do: Ui.page(width, height, "Help · snippets", Ui.help_lines(help_rows()))

  def view(%{page: {:confirm, question, _}}, width, height),
    do: Ui.confirm(width, height, question)

  def view(%{page: {:input, kind, value, cursor}}, width, height),
    do: input_view(kind, value, cursor, width, height)

  def view(s, width, height) do
    snippets = Config.snippets()
    cur = current(s)
    # the rows between the top and the status line, inside the borders
    rows = max(height - 4, 1)
    detail_width = max(width - @list_width + 1, 10)

    panels =
      hstack(
        [
          box(list_view(s, snippets, rows),
            title: "Snippets (#{length(snippets)})",
            width: @list_width - 1
          ),
          box(code_view(s, cur, rows, detail_width - 4),
            title: if(cur, do: cur.name, else: "—"),
            width: detail_width,
            padding: [top: 0, right: 1, bottom: 0, left: 1]
          )
        ],
        height: height - 2
      )

    # A Terra box fills all the rows below it, so a box of no border with one
    # row of bottom padding keeps the last row free for the status line.
    vstack([
      box(panels, border: false, padding: [top: 0, right: 0, bottom: 1, left: 0]),
      status_line(snippets, width)
    ])
  end

  defp list_view(_s, [], _rows), do: text("No snippets yet · n to add", fg: Theme.color(:muted))

  defp list_view(s, snippets, rows) do
    sel = min(s.sel, length(snippets) - 1)
    offset = max(sel - rows + 1, 0)

    snippets
    |> Enum.with_index()
    |> Enum.slice(offset, rows)
    |> Enum.map(fn {snippet, i} ->
      active? = i == sel
      bg = if active?, do: [bg: Theme.color(:element)], else: []
      number = String.pad_leading(Integer.to_string(i + 1), 2)

      hstack([
        text(" #{number} · ", [fg: Theme.color(if active?, do: :title, else: :muted)] ++ bg),
        text(
          Ui.fit(snippet.name, max(@list_width - 12, 1)) <> " ",
          [fg: Theme.color(if active?, do: :text, else: :muted)] ++ bg
        )
      ])
    end)
    |> vstack()
  end

  defp code_view(_s, nil, _rows, _width), do: text("Select a snippet", fg: Theme.color(:muted))

  defp code_view(s, cur, rows, width) do
    if String.trim(cur.code) == "" do
      text("Empty · e to edit", fg: Theme.color(:muted))
    else
      lines = cur.code |> Highlight.lex() |> Highlight.wrap_lines(max(width, 1))
      last = div(max(length(lines) - 1, 0), rows)

      lines
      |> Enum.drop(min(s.code_page, last) * rows)
      |> Enum.take(rows)
      |> Enum.map(fn
        [] -> text("")
        parts -> hstack(Enum.map(parts, fn {t, c} -> text(t, fg: c) end))
      end)
      |> vstack()
    end
  end

  defp status_line(snippets, width) do
    left = "#{length(snippets)} snippets"

    hints =
      if Map.get(Config.settings(), :show_hints, true),
        do: Ui.hints(hints(), width - String.length(left) - 4),
        else: []

    hstack([text(left, fg: Theme.color(:muted)), text("   ") | hints])
  end

  defp hints,
    do:
      "j/k move · ^F/^B scroll · e edit · n new · r rename · f format · d del · #g jump · , settings · ? help · esc back"

  defp input_view(kind, value, cursor, width, height) do
    {title, placeholder, notes} =
      case kind do
        :new ->
          {"New snippet — name", "snippet name", []}

        {:rename, _} ->
          {"Rename snippet", "snippet name", []}

        {:code, _} ->
          {"Edit code", "Enum.map([1, 2, 3], &(&1 * 2))",
           [
             "One line: #{@newline} marks a line break of the code.",
             "Separate expressions with ; to add lines. Save formats the code."
           ]}
      end

    Ui.page(
      width,
      height,
      title,
      Enum.map(notes, &text(&1, fg: Theme.color(:muted))) ++
        [
          Widget.input(value, cursor: cursor, placeholder: placeholder),
          text(""),
          text("Enter save · Esc cancel", fg: Theme.color(:muted))
        ]
    )
  end

  # tui/src/SnippetManager.tsx:207-225
  defp help_rows do
    [
      {"j / k", "move"},
      {"^F / ^B", "scroll the code by a page"},
      {"e", "edit code"},
      {"n", "new snippet"},
      {"r", "rename"},
      {"f", "format code"},
      {"d / ^D", "delete / delete (no confirm)"},
      {"#g", "jump to snippet #"},
      {",", "settings"},
      {"esc", "back"}
    ]
  end
end
