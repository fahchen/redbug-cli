defmodule Server.Tui.Console do
  @moduledoc """
  The console tab of the session screen: the execution history and the detail
  of the selected execution. It calls `Server.Remote` and `Server.Config`
  directly, as the removed `Server.Stores.ConsoleRoot` did
  (`server/lib/server/stores/console_root.ex@8b4cec82`), and takes the console
  messages of the bridge. The keys follow `tui/src/ConsoleTab.tsx@8b4cec82:185-250`;
  `docs/terra-gaps.md` records the keys and features that differ.
  """

  import Terra.View

  alias Server.{Config, Remote}
  alias Server.Tui.{Highlight, Theme, Ui}
  alias Terra.Widget

  @list_width 38
  # A code line break in a single-line input.
  @newline "↵"

  # tui/src/ConsoleTab.tsx@8b4cec82:22-46
  @glyphs %{"running" => "⟳", "ok" => "✓", "error" => "✖", "stopped" => "⊘", "timeout" => "⧖"}

  @doc "The console state of a session. The history comes from `{:console_snapshot, snap}`."
  def new(node_id, session_id) do
    %{
      node_id: node_id,
      id: session_id,
      history: [],
      sel: 0,
      offset: 0,
      page: :list,
      highlight: %{}
    }
  end

  # --- console messages (handle_info/2 of the removed Server.Stores.ConsoleRoot) ---

  @doc "Applies a console message of the bridge."
  def message(message, c), do: message |> apply_message(c) |> prune()

  defp apply_message({:console_snapshot, snap}, c), do: clamp(%{c | history: snap.history})
  defp apply_message({:console_insert, entry}, c), do: upsert(c, entry)
  defp apply_message({:console_update, entry}, c), do: upsert(c, entry)
  defp apply_message(:console_reset, c), do: %{c | history: [], sel: 0, offset: 0}

  defp apply_message({:console_delete, id}, c),
    do: clamp(%{c | history: Enum.reject(c.history, &(&1.id == id))})

  # The highlight cache keeps only the executions in the history.
  defp prune(c) do
    ids = MapSet.new(c.history, & &1.id)
    %{c | highlight: Map.filter(c.highlight, fn {{id, _part}, _} -> MapSet.member?(ids, id) end)}
  end

  # A new entry goes on top; an update keeps the place of the entry.
  defp upsert(c, entry) do
    history =
      if Enum.any?(c.history, &(&1.id == entry.id)),
        do: Enum.map(c.history, &if(&1.id == entry.id, do: entry, else: &1)),
        else: Enum.take([entry | c.history], 200)

    %{c | history: history}
  end

  defp clamp(c), do: %{c | sel: c.sel |> min(length(c.history) - 1) |> max(0)}

  defp current(c), do: Enum.at(c.history, c.sel)

  # --- keys ---

  @doc """
  Applies a key. Returns `{:ok, console}`, `:events` to show the events tab,
  `{:settings, console}` to open the settings, or `:close` to leave the session.
  """
  def key(key, %{page: :list} = c, size), do: list_key(key, c, size)
  def key(_key, %{page: :help} = c, _size), do: {:ok, %{c | page: :list}}
  def key(key, %{page: {:pick, _}} = c, _size), do: pick_key(key, c)
  def key(key, %{page: {:confirm, _, _, _}} = c, _size), do: confirm_key(key, c)
  def key(key, %{page: {:input, _, _, _}} = c, _size), do: input_key(key, c)

  defp list_key({:char, t}, _c, _size) when t in ["[", "]"], do: :events
  defp list_key(:esc, _c, _size), do: :close

  defp list_key({:ctrl, :l}, %{history: [_ | _]} = c, _size) do
    question = "Clear the entire execution history?"
    hint = "history is server-held, not just this view · y = yes · n/Esc = no"
    {:ok, %{c | page: {:confirm, question, hint, :clear}}}
  end

  defp list_key({:ctrl, :d}, c, _size) do
    with %{id: id} <- current(c), do: Remote.delete_exec(c.id, id)
    {:ok, %{c | sel: max(c.sel - 1, 0), offset: 0}}
  end

  defp list_key({:ctrl, :f}, c, size), do: {:ok, scroll(c, c.offset + detail_rows(size), size)}
  defp list_key({:ctrl, :b}, c, size), do: {:ok, scroll(c, c.offset - detail_rows(size), size)}
  defp list_key(k, c, _size) when k in [:down, {:char, "j"}], do: {:ok, move(c, 1)}
  defp list_key(k, c, _size) when k in [:up, {:char, "k"}], do: {:ok, move(c, -1)}
  defp list_key({:char, "n"}, c, _size), do: {:ok, %{c | page: {:pick, 0}}}
  defp list_key({:char, ","}, c, _size), do: {:settings, c}
  defp list_key({:char, "?"}, c, _size), do: {:ok, %{c | page: :help}}
  defp list_key(key, c, _size), do: {:ok, exec_key(key, current(c), c)}

  defp exec_key(_key, nil, c), do: c

  defp exec_key({:char, "e"}, exec, c), do: compose(c, exec.code, blank_nil(exec.name))

  defp exec_key({:char, "r"}, exec, c) do
    Remote.run(c.node_id, c.id, exec.code, blank_nil(exec.name))
    %{c | sel: 0, offset: 0}
  end

  defp exec_key({:char, "d"}, exec, c),
    do: %{
      c
      | page: {:confirm, "Delete this execution?", "y = yes · n/Esc = no", {:delete, exec.id}}
    }

  defp exec_key({:char, "s"}, exec, c), do: %{c | page: {:input, {:save, exec.id}, "", 0}}

  defp exec_key({:char, "x"}, %{status: "running"} = exec, c) do
    question = "Force-stop (kill) this running execution?"
    hint = "side effects already run cannot be undone · y = stop · n/Esc = no"
    %{c | page: {:confirm, question, hint, {:stop, exec.id}}}
  end

  defp exec_key(_key, _exec, c), do: c

  defp blank_nil(name) when name in [nil, ""], do: nil
  defp blank_nil(name), do: name

  # tui/src/ConsoleTab.tsx@8b4cec82:207-217: the selection wraps; the detail goes to its top.
  defp move(%{history: []} = c, _delta), do: c

  defp move(c, delta),
    do: %{c | sel: Integer.mod(c.sel + delta, length(c.history)), offset: 0}

  defp scroll(c, offset, size) do
    last = max(length(detail_lines(c, current(c), size)) - detail_rows(size), 0)
    %{c | offset: offset |> max(0) |> min(last)}
  end

  # The new execution starts from a blank page or a snippet (tui/src/ConsoleTab.tsx@8b4cec82:332-348).
  defp pick_key(k, %{page: {:pick, i}} = c) when k in [:down, {:char, "j"}],
    do: {:ok, %{c | page: {:pick, min(i + 1, length(Config.snippets()))}}}

  defp pick_key(k, %{page: {:pick, i}} = c) when k in [:up, {:char, "k"}],
    do: {:ok, %{c | page: {:pick, max(i - 1, 0)}}}

  defp pick_key(:enter, %{page: {:pick, 0}} = c), do: {:ok, compose(c, "", nil)}

  defp pick_key(:enter, %{page: {:pick, i}} = c) do
    case Enum.at(Config.snippets(), i - 1) do
      nil -> {:ok, compose(c, "", nil)}
      snippet -> {:ok, compose(c, snippet.code, snippet.name)}
    end
  end

  defp pick_key(:esc, c), do: {:ok, %{c | page: :list}}
  defp pick_key(_key, c), do: {:ok, c}

  defp compose(c, code, name) do
    value = String.replace(code, "\n", @newline)
    %{c | page: {:input, {:run, name}, value, String.length(value)}}
  end

  defp input_key(:esc, c), do: {:ok, %{c | page: :list}}

  defp input_key(key, %{page: {:input, kind, value, cursor}} = c) do
    case Widget.input_event(key, value, cursor) do
      {:edit, value, cursor} -> {:ok, %{c | page: {:input, kind, value, cursor}}}
      {:submit, value} -> {:ok, submit(kind, value, %{c | page: :list})}
      _ -> {:ok, c}
    end
  end

  # The run command of ConsoleRoot: a blank code runs nothing.
  defp submit({:run, name}, value, c) do
    code = String.replace(value, @newline, "\n")

    if String.trim(code) == "" do
      c
    else
      Remote.run(c.node_id, c.id, code, name)
      %{c | sel: 0, offset: 0}
    end
  end

  # The saveAsSnippet command of ConsoleRoot.
  defp submit({:save, exec_id}, value, c) do
    name = String.trim(value)
    exec = Enum.find(c.history, &(&1.id == exec_id))
    if name != "" and exec, do: Config.add_snippet(%{name: name, code: exec.code})
    c
  end

  defp confirm_key({:char, "y"}, %{page: {:confirm, _, _, action}} = c),
    do: {:ok, confirm(action, %{c | page: :list})}

  defp confirm_key(k, c) when k in [{:char, "n"}, :esc], do: {:ok, %{c | page: :list}}
  defp confirm_key(_key, c), do: {:ok, c}

  defp confirm(:clear, c) do
    Remote.clear(c.id)
    c
  end

  defp confirm({:stop, id}, c) do
    Remote.stop(c.id, id)
    c
  end

  defp confirm({:delete, id}, c) do
    Remote.delete_exec(c.id, id)
    %{c | sel: max(c.sel - 1, 0), offset: 0}
  end

  # --- detail lines ---

  @doc """
  Keeps the lexed code and result of the selected execution, so the lexer
  runs once for each execution (the result once it is final).
  """
  def cache(c) do
    case current(c) do
      nil ->
        c

      exec ->
        keys =
          [{exec.id, :code, exec.code}] ++
            if(exec.status == "running", do: [], else: [{exec.id, :result, exec.result}])

        Enum.reduce(keys, c, fn {id, part, text}, c ->
          if Map.has_key?(c.highlight, {id, part}),
            do: c,
            else: %{c | highlight: Map.put(c.highlight, {id, part}, Highlight.lex(text))}
        end)
    end
  end

  defp lexed(c, exec, part, text),
    do: Map.get_lazy(c.highlight, {exec.id, part}, fn -> Highlight.lex(text) end)

  # tui/src/ConsoleTab.tsx@8b4cec82:409-444: the code, the result, and the stdout.
  defp detail_lines(_c, nil, _size), do: []

  defp detail_lines(c, exec, {width, _height}) do
    muted = Theme.color(:muted)

    result =
      if String.trim(exec.result || "") == "",
        do: [],
        else: [[], [{"Result", muted}] | lexed(c, exec, :result, exec.result)]

    output =
      if String.trim(exec.output || "") == "",
        do: [],
        else: [
          [],
          [{"Stdout", muted}] | for(line <- String.split(exec.output, "\n"), do: [{line, muted}])
        ]

    ([[{"Code", muted}] | lexed(c, exec, :code, exec.code)] ++ result ++ output)
    |> Highlight.wrap_lines(detail_width(width))
  end

  defp detail_width(width), do: max(width - @list_width - 4, 10)
  # the tab row, the borders, the chips and their blank row, the free row, and the status line
  defp detail_rows({_width, height}), do: max(height - 7, 1)

  # --- views ---

  @doc "The view of the console tab. `header` is the tab row of the session screen."
  def view(c, node, header, width, height) do
    case c.page do
      :help -> Ui.page(width, height, "Help · console", Ui.help_lines(help_rows()))
      {:confirm, question, hint, _} -> Ui.confirm(width, height, question, [], hint)
      {:pick, i} -> pick_view(i, width, height)
      {:input, kind, value, cursor} -> input_view(kind, value, cursor, width, height)
      :list -> list_view(c, node, header, width, height)
    end
  end

  defp list_view(c, node, header, width, height) do
    body = max(height - 2, 3)
    rows = max(body - 3, 1)
    offset = max(c.sel - rows + 1, 0)

    list =
      case c.history do
        [] ->
          [text("No executions yet · n to run", fg: Theme.color(:muted))]

        history ->
          history
          |> Enum.with_index()
          |> Enum.slice(offset, rows)
          |> Enum.map(fn {exec, i} -> history_row(exec, i == c.sel) end)
      end

    panels =
      hstack(
        [
          box(vstack(list), title: "Console", width: @list_width - 1),
          box(detail_view(c, {width, height}),
            title: "Detail",
            width: max(width - @list_width + 1, 10),
            padding: [top: 0, right: 1, bottom: 0, left: 1]
          )
        ],
        height: body - 1
      )

    vstack([
      header,
      box(panels, border: false, padding: [top: 0, right: 0, bottom: 1, left: 0]),
      status_line(c, node, width)
    ])
  end

  # tui/src/ConsoleTab.tsx@8b4cec82:376-389
  defp history_row(exec, active?) do
    bg = if active?, do: [bg: Theme.color(:element)], else: []
    label = if exec.name not in [nil, ""], do: exec.name, else: first_line(exec.code)

    hstack([
      text(" #{glyph(exec.status)} ", [fg: Theme.color(status_color(exec.status))] ++ bg),
      text("#{exec.ts} ", [fg: Theme.color(:muted)] ++ bg),
      text(
        Ui.fit(label, max(@list_width - 7 - String.length(exec.ts), 1)),
        [fg: Theme.color(if(active?, do: :text, else: :muted))] ++ bg
      )
    ])
  end

  defp first_line(code), do: code |> String.split("\n") |> Enum.find("", &(String.trim(&1) != ""))

  defp glyph(status), do: Map.get(@glyphs, status, "·")

  defp status_color("ok"), do: :success
  defp status_color(s) when s in ["error", "timeout"], do: :error
  defp status_color("running"), do: :warning
  defp status_color(_status), do: :muted

  defp detail_view(c, size) do
    case current(c) do
      nil ->
        text("No execution selected · n to run", fg: Theme.color(:muted))

      exec ->
        duration = if exec.duration_ms, do: "#{exec.duration_ms}ms", else: "—"
        tone = if exec.status in ["error", "timeout"], do: :error, else: :text

        chips =
          [
            Ui.chip("Status", "#{glyph(exec.status)} #{exec.status}", tone),
            Ui.chip("Duration", duration),
            exec.name not in [nil, ""] && Ui.chip("Name", exec.name),
            Ui.chip("Ts", exec.ts)
          ]
          |> Enum.filter(& &1)
          |> Enum.intersperse(text(" "))

        body =
          c
          |> detail_lines(exec, size)
          |> Enum.drop(c.offset)
          |> Enum.take(detail_rows(size))
          |> Enum.map(fn
            [] -> text("")
            parts -> hstack(Enum.map(parts, fn {t, color} -> text(t, fg: color) end))
          end)

        vstack([hstack(chips), text("") | body])
    end
  end

  # tui/src/ConsoleTab.tsx@8b4cec82:279-286
  defp status_line(c, node, width) do
    running = Enum.count(c.history, &(&1.status == "running"))

    left =
      case node && node.status do
        "connecting" -> "connecting…"
        "error" -> "✖ can't reach node"
        _ -> "#{length(c.history)} runs" <> if(running > 0, do: " · #{running} running", else: "")
      end

    hints =
      "j/k move · ^F/^B scroll · n compose · e edit+run · r run · s save · d del · x stop · ^L clear · [/] tabs · , settings · ? help · esc back"

    hints =
      if Map.get(Config.settings(), :show_hints, true),
        do: Ui.hints(hints, width - String.length(left) - 3),
        else: []

    hstack([text(left, fg: Theme.color(:muted)), text("   ") | hints])
  end

  defp pick_view(index, width, height) do
    options =
      ["(blank)" | Enum.map(Config.snippets(), & &1.name)]
      |> Enum.with_index()
      |> Enum.map(fn {label, i} ->
        style = if i == index, do: [bg: Theme.color(:element)], else: []
        text("  #{label} ", [fg: Theme.color(:text)] ++ style)
      end)

    Ui.page(
      width,
      height,
      "New execution — start from",
      options ++
        [text(""), text("j/k move · Enter compose · Esc cancel", fg: Theme.color(:muted))]
    )
  end

  defp input_view({:run, _name}, value, cursor, width, height) do
    Ui.page(width, height, "Compose", [
      Widget.input(value, cursor: cursor, placeholder: "Enum.map(1..3, &(&1 * 2))"),
      text(""),
      text("#{@newline} marks a line break · Enter run · Esc cancel", fg: Theme.color(:muted))
    ])
  end

  defp input_view({:save, _id}, value, cursor, width, height) do
    Ui.page(width, height, "Save as snippet", [
      hstack([
        text("Name  ", fg: Theme.color(:title)),
        Widget.input(value, cursor: cursor, placeholder: "snippet name")
      ]),
      text(""),
      text("Enter save · Esc cancel", fg: Theme.color(:muted))
    ])
  end

  defp help_rows do
    [
      {"j / k", "move"},
      {"n", "new execution (pick snippet, compose)"},
      {"e", "edit + run selected"},
      {"r", "run selected as-is"},
      {"s", "save as snippet"},
      {"d / Ctrl+D", "delete / delete (no confirm)"},
      {"x", "force-stop running execution"},
      {"Ctrl+L", "clear history"},
      {"Ctrl+F/B", "scroll the detail by page"},
      {:section, "tabs"},
      {"[ / ]", "switch Events ⇄ Console"},
      {"esc", "back"}
    ]
  end
end
