defmodule Server.Tui.Presets do
  @moduledoc """
  The presets screen of the Terra TUI: the preset list and the trace patterns
  and limits of the selected preset. The keys follow
  `tui/src/PresetManager.tsx@8b4cec82`. The screen calls `Server.Config` directly, as
  the removed `Server.Stores.PresetsRoot` and `Server.Stores.PresetStore` did
  (`server/lib/server/stores/@8b4cec82`), and reads
  the presets in `view/3`, so it always shows the current data. The overlays
  of the Bun screen are full-screen pages (`docs/terra-gaps.md`).
  """

  import Terra.View

  alias Server.Config
  alias Server.Tui.{Theme, Ui}
  alias Terra.Widget

  @list_width 40

  @doc "The screen state."
  def new, do: %{sel: 0, focus: :list, trace_sel: 0, page: :main}

  # --- keys ---

  @doc "Handles a key. `:close` goes back; `{:settings, s}` opens the settings."
  def key(_key, %{page: :help} = s), do: {:ok, %{s | page: :main}}
  def key(key, %{page: {:confirm, _, action}} = s), do: confirm_key(key, action, s)
  def key(key, %{page: {:input, _, _, _}} = s), do: input_key(key, s)
  def key({:char, "?"}, s), do: {:ok, %{s | page: :help}}
  def key({:char, ","}, s), do: {:settings, s}
  def key(key, %{focus: :detail} = s), do: detail_key(key, s, current(s))
  def key(key, s), do: list_key(key, s, current(s))

  # tui/src/PresetManager.tsx@8b4cec82:156-189
  defp list_key(:esc, _s, _cur), do: :close
  defp list_key(k, s, _cur) when k in [:down, {:char, "j"}], do: {:ok, move(s, :sel, 1)}
  defp list_key(k, s, _cur) when k in [:up, {:char, "k"}], do: {:ok, move(s, :sel, -1)}
  defp list_key({:char, "n"}, s, _cur), do: {:ok, input(s, :new, "")}
  defp list_key(_key, s, nil), do: {:ok, s}

  defp list_key(k, s, _cur) when k in [:enter, :tab],
    do: {:ok, %{s | focus: :detail, trace_sel: 0}}

  defp list_key({:char, "r"}, s, cur), do: {:ok, input(s, {:rename, cur.id}, cur.name)}

  defp list_key({:char, "d"}, s, cur),
    do: {:ok, %{s | page: {:confirm, ~s(Delete preset "#{cur.name}"?), {:delete, cur.id}}}}

  defp list_key({:ctrl, :d}, s, cur), do: {:ok, run({:delete, cur.id}, s)}
  defp list_key(_key, s, _cur), do: {:ok, s}

  # tui/src/PresetManager.tsx@8b4cec82:125-154
  defp detail_key(k, s, _cur) when k in [:esc, :tab], do: {:ok, %{s | focus: :list}}
  defp detail_key(_key, s, nil), do: {:ok, %{s | focus: :list}}

  defp detail_key(k, s, cur) when k in [:down, {:char, "j"}],
    do: {:ok, move(s, :trace_sel, 1, length(cur.traces))}

  defp detail_key(k, s, cur) when k in [:up, {:char, "k"}],
    do: {:ok, move(s, :trace_sel, -1, length(cur.traces))}

  defp detail_key({:char, "n"}, s, cur), do: {:ok, input(s, {:add_trace, cur.id}, "")}

  defp detail_key({:char, "l"}, s, cur) do
    l = cur.limits
    {:ok, input(s, {:limits, cur.id}, "#{l.keep} #{l.time} #{l.msgs}")}
  end

  defp detail_key(key, s, cur) do
    case {key, trace(s, cur)} do
      {_key, nil} ->
        {:ok, s}

      {{:char, "e"}, t} ->
        {:ok, input(s, {:edit_trace, cur.id, t.id}, t.text)}

      {{:char, "d"}, t} ->
        {:ok, %{s | page: {:confirm, "Delete this pattern?", {:delete_trace, cur.id, t.id}}}}

      {{:ctrl, :d}, t} ->
        {:ok, run({:delete_trace, cur.id, t.id}, s)}

      _ ->
        {:ok, s}
    end
  end

  # tui/src/PresetManager.tsx@8b4cec82:72-91
  defp confirm_key({:char, "y"}, action, s), do: {:ok, run(action, %{s | page: :main})}

  defp confirm_key(k, _action, s) when k in [:esc, {:char, "n"}],
    do: {:ok, %{s | page: :main}}

  defp confirm_key(_key, _action, s), do: {:ok, s}

  defp run({:delete, id}, s) do
    Config.delete_preset(id)
    %{s | sel: max(s.sel - 1, 0)}
  end

  defp run({:delete_trace, id, trace_id}, s) do
    update_traces(id, &Enum.reject(&1, fn t -> t.id == trace_id end))
    %{s | trace_sel: max(s.trace_sel - 1, 0)}
  end

  defp input(s, kind, value), do: %{s | page: {:input, kind, value, String.length(value)}}

  defp input_key(key, %{page: {:input, kind, value, cursor}} = s) do
    case Widget.input_event(key, value, cursor) do
      {:edit, value, cursor} -> {:ok, %{s | page: {:input, kind, value, cursor}}}
      {:submit, value} -> {:ok, submit(kind, value, %{s | page: :main})}
      :cancel -> {:ok, %{s | page: :main}}
      :ignore -> {:ok, s}
    end
  end

  # tui/src/PresetManager.tsx@8b4cec82:278-345. The edit of a pattern saves an empty
  # text too, as the Bun screen does.
  defp submit({:edit_trace, id, trace_id}, text, s) do
    update_traces(
      id,
      &Enum.map(&1, fn t -> if t.id == trace_id, do: %{t | text: text}, else: t end)
    )

    s
  end

  defp submit(kind, text, s) do
    if String.trim(text) != "", do: save(kind, text)
    s
  end

  defp save(:new, name), do: Config.add_preset(%{name: name})
  defp save({:rename, id}, name), do: Config.update_preset(id, %{name: name})

  defp save({:add_trace, id}, text),
    do: update_traces(id, &(&1 ++ [%{id: Config.gen_id(), text: text, enabled: true}]))

  # tui/src/limits.ts@8b4cec82: "keep time msgs"; a bad text changes nothing.
  defp save({:limits, id}, text) do
    with [{keep, ""}, {time, ""}, {msgs, ""}] when keep >= 0 and time >= 0 and msgs >= 0 <-
           text |> String.split() |> Enum.map(&Integer.parse/1),
         %{} = preset <- find(id) do
      limits = Map.merge(preset.limits, %{keep: keep, time: time, msgs: msgs})
      Config.update_preset(id, %{limits: limits})
    end
  end

  defp update_traces(id, fun) do
    case find(id) do
      nil -> :ok
      preset -> Config.update_preset(id, %{traces: fun.(preset.traces)})
    end
  end

  defp find(id), do: Enum.find(Config.presets(), &(&1.id == id))

  defp current(s) do
    case Config.presets() do
      [] -> nil
      presets -> Enum.at(presets, min(s.sel, length(presets) - 1))
    end
  end

  defp trace(_s, %{traces: []}), do: nil
  defp trace(s, %{traces: traces}), do: Enum.at(traces, min(s.trace_sel, length(traces) - 1))

  defp move(s, field, delta), do: move(s, field, delta, length(Config.presets()))
  defp move(s, _field, _delta, 0), do: s

  defp move(s, field, delta, n),
    do: Map.put(s, field, Integer.mod(Map.fetch!(s, field) + delta, n))

  # --- views ---

  @doc "The view of the screen."
  def view(%{page: :help}, width, height),
    do: Ui.page(width, height, "Help · presets", Ui.help_lines(help_rows()))

  def view(%{page: {:confirm, question, _}}, width, height),
    do: Ui.confirm(width, height, question)

  def view(%{page: {:input, kind, value, cursor}}, width, height),
    do: input_view(kind, value, cursor, width, height)

  def view(s, width, height) do
    presets = Config.presets()
    cur = current(s)
    # the rows between the top and the status line, inside the borders
    rows = max(height - 4, 1)
    detail_width = max(width - @list_width + 1, 10)

    panels =
      hstack(
        [
          box(list_view(s, presets, rows),
            title: panel_title("Presets", s.focus == :list),
            width: @list_width - 1
          ),
          box(detail_view(s, cur, rows, detail_width - 4),
            title: panel_title("Traces", s.focus == :detail),
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
      status_line(s, presets, width)
    ])
  end

  # Terra has one border color for all boxes, so `▸` marks the focused panel.
  defp panel_title(title, true), do: "▸ " <> title
  defp panel_title(title, false), do: title

  defp list_view(_s, [], _rows), do: text("No presets yet · n to add", fg: Theme.color(:muted))

  defp list_view(s, presets, rows) do
    sel = min(s.sel, length(presets) - 1)
    offset = max(sel - rows + 1, 0)
    width = @list_width - 4

    presets
    |> Enum.with_index()
    |> Enum.slice(offset, rows)
    |> Enum.map(fn {p, i} ->
      count = Integer.to_string(length(p.traces))
      active? = i == sel

      style =
        if active?,
          do: [fg: Theme.color(:text), bg: Theme.color(:element)],
          else: [fg: Theme.color(:muted)]

      bg = Keyword.take(style, [:bg])

      hstack([
        text(" " <> Ui.fit(p.name, max(width - String.length(count) - 3, 1)) <> " ", style),
        text(count <> " ", [fg: Theme.color(:muted)] ++ bg)
      ])
    end)
    |> vstack()
  end

  defp detail_view(_s, nil, _rows, _width), do: text("Select a preset", fg: Theme.color(:muted))

  defp detail_view(s, cur, rows, width) do
    l = cur.limits

    chips =
      hstack([
        Ui.chip("keep", l.keep),
        text(" "),
        Ui.chip("time", "#{l.time}s"),
        text(" "),
        Ui.chip("msgs", l.msgs)
      ])

    traces =
      case cur.traces do
        [] ->
          [text("No patterns yet · enter, then n to add", fg: Theme.color(:muted))]

        traces ->
          sel = min(s.trace_sel, length(traces) - 1)
          room = max(rows - 2, 1)
          offset = max(sel - room + 1, 0)

          traces
          |> Enum.with_index()
          |> Enum.slice(offset, room)
          |> Enum.map(fn {t, i} ->
            active? = s.focus == :detail and i == sel

            style =
              if active?,
                do: [fg: Theme.color(:text), bg: Theme.color(:element)],
                else: [fg: Theme.color(:muted)]

            text(" " <> Ui.fit(t.text, max(width - 2, 1)) <> " ", style)
          end)
      end

    vstack([chips, text("") | traces])
  end

  defp status_line(s, presets, width) do
    left = "#{length(presets)} presets"

    hints =
      if Map.get(Config.settings(), :show_hints, true),
        do: Ui.hints(hints(s), width - String.length(left) - 4),
        else: []

    hstack([text(left, fg: Theme.color(:muted)), text("   ") | hints])
  end

  defp hints(%{focus: :list}),
    do: "j/k move · enter traces · n new · r rename · d del · , settings · ? help · esc back"

  defp hints(_s),
    do: "j/k move · n add · e edit · l limits · d del · , settings · ? help · tab/esc back"

  defp input_view(kind, value, cursor, width, height) do
    {title, placeholder, notes} =
      case kind do
        :new ->
          {"New preset — name", "preset name", []}

        {:rename, _} ->
          {"Rename preset", "preset name", []}

        {:add_trace, _} ->
          {"New RTP", "redbug spec, e.g. lists:seq/2 -> return", Ui.rtp_cheat_sheet()}

        {:edit_trace, _, _} ->
          {"Edit RTP", "redbug spec, e.g. lists:seq/2 -> return", Ui.rtp_cheat_sheet()}

        {:limits, _} ->
          {"Limits — keep time msgs (space-separated)", "500 900 10000", []}
      end

    Ui.page(
      width,
      height,
      title,
      [
        Widget.input(value, cursor: cursor, placeholder: placeholder),
        text(""),
        text("Enter save · Esc cancel", fg: Theme.color(:muted))
      ] ++ notes
    )
  end

  # tui/src/PresetManager.tsx@8b4cec82:246-273
  defp help_rows do
    [
      {:section, "list"},
      {"j / k", "move"},
      {"enter / tab", "focus traces"},
      {"n", "new preset"},
      {"r", "rename"},
      {"d / ^D", "delete / delete (no confirm)"},
      {"esc", "back"},
      {:section, "traces (detail focus)"},
      {"j / k", "move"},
      {"n", "add pattern"},
      {"e", "edit pattern"},
      {"l", "limits"},
      {"d / ^D", "delete / delete (no confirm)"},
      {"tab / esc", "back to list"},
      {:section, "both"},
      {",", "settings"}
    ]
  end
end
