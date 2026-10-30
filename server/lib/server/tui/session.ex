defmodule Server.Tui.Session do
  @moduledoc """
  The session screen of the Terra TUI: the live event list, the session editor
  (trace patterns and limits), and the event detail page. `Server.Tui.App`
  keeps the screen state (a map from `open/2`) and gives it the keys and the
  trace messages of the bridge. The screen calls `Server.Trace` and
  `Server.Config` directly, as `Server.Stores.SessionRoot` does.
  """

  import Terra.View

  alias Server.{Config, Trace}
  alias Server.Tui.{Highlight, Theme}
  alias Terra.Widget

  @doc "Opens the session: connects its node and reads the trace snapshot."
  def open(node_id, session_id) do
    # Entering a session connects its node, as SessionRoot.mount/2 does.
    if Config.node_connection(node_id).status != "connected", do: Config.request_connect(node_id)
    snap = Trace.snapshot(session_id)

    %{
      node_id: node_id,
      id: session_id,
      events: snap.events,
      status: snap.status,
      applied_sig: snap.applied_sig,
      ended: nil,
      error: nil,
      sel: 0,
      fold: false,
      page: :events,
      editor_sel: 0,
      highlight: %{}
    }
  end

  @doc "Closes the session: stops its trace, as SessionRoot.terminate/2 does."
  def close(session), do: Trace.stop(session.id)

  # --- trace messages ---

  def trace({:trace_events, events}, session, keep) do
    events = Enum.take(events ++ session.events, keep)
    # Keep the selection on the same event when new events come on top.
    sel =
      if session.sel == 0,
        do: 0,
        else: min(session.sel + length(events) - length(session.events), length(events) - 1)

    %{session | events: events, sel: max(sel, 0)}
  end

  def trace({:trace_status, payload}, session, _keep),
    do: %{
      session
      | status: payload.status,
        applied_sig: payload.applied_sig,
        ended: Map.get(payload, :ended)
    }

  def trace({:trace_error, error}, session, _keep),
    do: %{session | error: error, status: "stopped"}

  def trace(:trace_reset, session, _keep), do: %{session | events: [], sel: 0, highlight: %{}}

  # --- keys ---

  @doc """
  Applies a key. Returns `{:ok, session}`, or `:close` when the user leaves
  the session screen.
  """
  def key(key, %{page: {:detail, _event, _offset}} = s, _node, size), do: detail_key(key, s, size)
  def key(key, %{page: :editor} = s, node, _size), do: editor_key(key, s, node)
  def key(key, %{page: {:input, _, _, _}} = s, node, _size), do: input_key(key, s, node)

  def key(:enter, %{page: :events} = s, _node, {width, _height}) do
    case Enum.at(rows(s), s.sel) do
      nil -> {:ok, s}
      {event, _ret} -> {:ok, %{cache(s, event, detail_width(width)) | page: {:detail, event, 0}}}
    end
  end

  def key(key, %{page: :events} = s, node, _size), do: events_key(key, s, node)

  defp events_key(:esc, _s, _node), do: :close
  defp events_key(k, s, _node) when k in [:down, {:char, "j"}], do: {:ok, move(s, 1)}
  defp events_key(k, s, _node) when k in [:up, {:char, "k"}], do: {:ok, move(s, -1)}

  defp events_key({:char, " "}, s, node), do: {:ok, start_stop(s, node)}

  defp events_key({:char, "a"}, s, _node) do
    result = Trace.apply_restart(s.id)
    {:ok, put_error(s, result)}
  end

  defp events_key({:char, "c"}, s, _node) do
    Trace.clear(s.id)
    {:ok, %{s | error: nil, events: [], sel: 0, highlight: %{}}}
  end

  defp events_key({:char, "f"}, s, _node), do: {:ok, %{s | fold: not s.fold, sel: 0}}
  defp events_key({:char, "e"}, s, _node), do: {:ok, %{s | page: :editor, editor_sel: 0}}

  defp events_key({:char, "r"}, s, _node),
    do: {:ok, tap(s, fn _ -> Config.request_connect(s.node_id) end)}

  defp events_key(_key, s, _node), do: {:ok, s}

  defp start_stop(%{status: "running"} = s, _node) do
    Trace.stop(s.id)
    %{s | error: nil}
  end

  defp start_stop(s, _node), do: put_error(s, Trace.start(s.node_id, s.id))

  defp put_error(s, :ok), do: %{s | error: nil}
  defp put_error(s, {:error, reason}), do: %{s | error: Server.Errors.humanize(reason)}

  defp move(s, delta) do
    case length(rows(s)) do
      0 -> s
      n -> %{s | sel: Integer.mod(s.sel + delta, n)}
    end
  end

  # --- event rows ---

  # The rows of the event list, newest first: `{event, return}`. With fold, a
  # call and its return (same `pair`) make one row; the return goes with the call.
  defp rows(%{fold: false} = s), do: Enum.map(s.events, &{&1, nil})

  defp rows(s) do
    returns =
      for %{kind: "retn", pair: pair} = e <- s.events, pair != "", into: %{}, do: {pair, e}

    s.events
    |> Enum.reject(
      &(&1.kind == "retn" and Map.has_key?(returns, &1.pair) and paired_call?(s.events, &1.pair))
    )
    |> Enum.map(fn
      %{kind: "call", pair: pair} = e when pair != "" -> {e, Map.get(returns, pair)}
      e -> {e, nil}
    end)
  end

  defp paired_call?(events, pair), do: Enum.any?(events, &(&1.kind == "call" and &1.pair == pair))

  # --- editor: trace patterns and limits ---

  @limits [keep: "Keep events", time: "Time (s)", msgs: "Messages"]

  defp editor_key(:esc, s, _node), do: {:ok, %{s | page: :events}}
  defp editor_key(k, s, node) when k in [:down, {:char, "j"}], do: {:ok, editor_move(s, node, 1)}
  defp editor_key(k, s, node) when k in [:up, {:char, "k"}], do: {:ok, editor_move(s, node, -1)}
  defp editor_key({:char, "n"}, s, _node), do: {:ok, %{s | page: {:input, :add, "", 0}}}

  defp editor_key(k, s, node) when k in [:enter, {:char, "e"}] do
    traces = traces(node, s)

    case editor_item(s, traces) do
      {:trace, t} -> {:ok, %{s | page: {:input, {:edit, t.id}, t.text, String.length(t.text)}}}
      {:limit, key} -> limit_input(s, node, key)
    end
  end

  defp editor_key({:char, " "}, s, node) do
    with {:trace, t} <- editor_item(s, traces(node, s)) do
      update_traces(
        node,
        s,
        &Enum.map(&1, fn x -> if x.id == t.id, do: %{x | enabled: not x.enabled}, else: x end)
      )
    end

    {:ok, s}
  end

  defp editor_key({:char, "d"}, s, node) do
    with {:trace, t} <- editor_item(s, traces(node, s)) do
      update_traces(node, s, &Enum.reject(&1, fn x -> x.id == t.id end))
    end

    {:ok, s}
  end

  defp editor_key(_key, s, _node), do: {:ok, s}

  defp limit_input(s, node, key) do
    value = Integer.to_string(Map.fetch!(session_limits(node, s), key))
    {:ok, %{s | page: {:input, {:limit, key}, value, String.length(value)}}}
  end

  defp editor_move(s, node, delta) do
    n = length(traces(node, s)) + length(@limits)
    %{s | editor_sel: Integer.mod(s.editor_sel + delta, n)}
  end

  defp editor_item(s, traces) do
    if s.editor_sel < length(traces),
      do: {:trace, Enum.at(traces, s.editor_sel)},
      else: {:limit, @limits |> Enum.at(s.editor_sel - length(traces)) |> elem(0)}
  end

  defp input_key(:esc, s, _node), do: {:ok, %{s | page: :editor}}

  defp input_key(key, %{page: {:input, kind, value, cursor}} = s, node) do
    case Widget.input_event(key, value, cursor) do
      {:edit, value, cursor} -> {:ok, %{s | page: {:input, kind, value, cursor}}}
      {:submit, value} -> {:ok, submit(kind, String.trim(value), %{s | page: :editor}, node)}
      _ -> {:ok, s}
    end
  end

  defp submit(_kind, "", s, _node), do: s

  defp submit(:add, text, s, node) do
    update_traces(node, s, &(&1 ++ [%{id: Config.gen_id(), text: text, enabled: true}]))
    s
  end

  defp submit({:edit, id}, text, s, node) do
    update_traces(
      node,
      s,
      &Enum.map(&1, fn x -> if x.id == id, do: %{x | text: text}, else: x end)
    )

    s
  end

  defp submit({:limit, key}, text, s, node) do
    case Integer.parse(text) do
      {n, ""} when n > 0 ->
        limits = Map.put(session_limits(node, s), key, n)
        Config.update_session(s.node_id, s.id, %{limits: limits})
        s

      _ ->
        %{
          s
          | error: %Server.Schema.AppError{
              message: "#{key} must be a positive integer",
              detail: nil
            }
        }
    end
  end

  defp update_traces(node, s, fun),
    do: Config.update_session(s.node_id, s.id, %{traces: fun.(traces(node, s))})

  @doc "The session of `node` that the screen shows, or nil."
  def config(node, s), do: node && Enum.find(node.sessions, &(&1.id == s.id))

  defp traces(node, s), do: (config(node, s) || %{traces: []}).traces

  defp session_limits(node, s),
    do: (config(node, s) || %{limits: Config.settings().default_limits}).limits

  # --- detail ---

  defp detail_key(k, %{page: {:detail, e, off}} = s, {width, height})
       when k in [:down, {:char, "j"}] do
    lines = lines(s, e, detail_width(width))
    {:ok, %{s | page: {:detail, e, min(off + 1, max(length(lines) - detail_rows(height), 0))}}}
  end

  defp detail_key(k, %{page: {:detail, e, off}} = s, _size) when k in [:up, {:char, "k"}],
    do: {:ok, %{s | page: {:detail, e, max(off - 1, 0)}}}

  defp detail_key(_key, s, _size), do: {:ok, %{s | page: :events}}

  defp detail_width(width), do: max(width - 6, 10)
  defp detail_rows(height), do: max(height - 6, 1)

  # The lexer runs once for each event and width: the update keeps its result,
  # and the view reads it.
  defp cache(s, event, width) do
    key = {event.id, width}

    if Map.has_key?(s.highlight, key),
      do: s,
      else: %{s | highlight: Map.put(s.highlight, key, Highlight.lines(event.info, width))}
  end

  defp lines(s, event, width) do
    Map.get_lazy(s.highlight, {event.id, width}, fn -> Highlight.lines(event.info, width) end)
  end

  # --- views ---

  def view(s, node, settings, width, height) do
    case s.page do
      {:detail, event, offset} -> detail_view(s, event, offset, width, height)
      :editor -> editor_view(s, node, width, height)
      {:input, kind, value, cursor} -> input_view(kind, value, cursor, width, height)
      :events -> events_view(s, node, settings, width, height)
    end
  end

  defp events_view(s, node, settings, width, height) do
    name = if c = config(node, s), do: c.name, else: "?"
    rows_height = max(height - 4, 1)
    all = rows(s)
    offset = max(s.sel - rows_height + 1, 0)
    columns = Map.get(settings, :columns, %{name: true, pid: true, mfa: true, info: true})

    list =
      case all do
        [] ->
          [text(empty_text(s), fg: Theme.color(:muted))]

        _ ->
          all
          |> Enum.with_index()
          |> Enum.slice(offset, rows_height)
          |> Enum.map(fn {{e, ret}, i} -> event_row(e, ret, i == s.sel, columns, width - 4) end)
      end

    vstack([
      header(node, name, s),
      box(box(vstack(list), border: false, padding: [top: 0, right: 0, bottom: 1, left: 0]),
        title: "Events",
        width: width
      ),
      status_line(s, width)
    ])
  end

  defp empty_text(%{status: "running"}), do: "Waiting for calls…"
  defp empty_text(_s), do: "No events · space starts the trace · e edits the patterns"

  defp header(node, name, s) do
    node_name = if node, do: node.name, else: "?"

    dirty =
      if dirty?(node, s),
        do: [text("  unapplied · a applies", fg: Theme.color(:warning))],
        else: []

    hstack(
      [
        text(" redbug ", fg: Theme.color(:title), bold: true),
        text(" #{node_name} ▸ #{name} ", fg: Theme.color(:text), bg: Theme.color(:element)),
        text("  " <> status_text(s), fg: status_color(s))
      ] ++ dirty
    )
  end

  defp dirty?(node, s) do
    c = config(node, s)

    c != nil and s.status == "running" and
      Server.Trace.Signature.compute(c.traces, c.limits) != s.applied_sig
  end

  defp status_text(%{status: "running"}), do: "● running"
  defp status_text(%{ended: ended}) when is_binary(ended), do: "■ stopped (#{ended})"
  defp status_text(_s), do: "■ stopped"
  defp status_color(%{status: "running"}), do: Theme.color(:success)
  defp status_color(_s), do: Theme.color(:muted)

  defp event_row(e, ret, selected?, columns, width) do
    bg = if selected?, do: [bg: Theme.color(:element)], else: []
    indent = String.duplicate("  ", e.depth || 0)
    {mark, mark_color} = kind_mark(e.kind)

    info =
      case ret do
        nil -> e.info
        r -> "#{e.info} → #{r.info}"
      end

    parts =
      [
        {e.ts <> " ", :muted},
        columns[:pid] && {e.pid <> " ", :muted},
        columns[:name] && e.name not in [nil, ""] && {e.name <> " ", :muted},
        {indent <> mark <> " ", mark_color},
        columns[:mfa] && {e.mfa <> " ", :text},
        columns[:info] && {one_line(info), :muted}
      ]
      |> Enum.filter(& &1)

    parts
    |> fit_parts(width)
    |> Enum.map(fn {t, c} -> text(t, [fg: Theme.color(c)] ++ bg) end)
    |> hstack()
  end

  defp kind_mark("call"), do: {"→", :title}
  defp kind_mark("retn"), do: {"←", :success}
  defp kind_mark("send"), do: {"⇒", :warning}
  defp kind_mark("recv"), do: {"⇐", :warning}
  defp kind_mark(_restart), do: {"──", :muted}

  defp one_line(text), do: text |> String.replace(~r/\s*\n\s*/, " ")

  # Cut the parts to `width` cells, then pad the row to the width.
  defp fit_parts(parts, width) do
    {parts, used} =
      Enum.reduce(parts, {[], 0}, fn {t, c}, {acc, used} ->
        room = width - used
        w = Terra.Width.string(t)

        cond do
          room <= 0 -> {acc, used}
          w <= room -> {[{t, c} | acc], used + w}
          true -> {[{cut(t, room), c} | acc], width}
        end
      end)

    Enum.reverse([{String.duplicate(" ", max(width - used, 0)), :muted} | parts])
  end

  defp cut(t, room) do
    t
    |> String.graphemes()
    |> Enum.reduce_while({"", 0}, fn g, {acc, used} ->
      w = Terra.Width.grapheme(g)
      if used + w <= room - 1, do: {:cont, {acc <> g, used + w}}, else: {:halt, {acc, used}}
    end)
    |> elem(0)
    |> Kernel.<>("…")
  end

  defp status_line(s, width) do
    count = "#{length(s.events)} events"
    error = if s.error, do: [text("  ✗ #{s.error.message}", fg: Theme.color(:error))], else: []

    hints =
      "j/k move · enter detail · space start/stop · a apply · e edit · f fold · c clear · esc back"

    room =
      max(
        width - String.length(count) - 4 -
          if(s.error, do: String.length(s.error.message) + 4, else: 0),
        0
      )

    hints =
      if String.length(hints) > room,
        do: String.slice(hints, 0, max(room - 1, 0)) <> "…",
        else: hints

    hstack(
      [text(count, fg: Theme.color(:muted))] ++
        error ++ [text("   " <> hints, fg: Theme.color(:muted))]
    )
  end

  defp editor_view(s, node, width, height) do
    traces = traces(node, s)
    limits = session_limits(node, s)

    trace_lines =
      case traces do
        [] ->
          [text("  no trace patterns · n adds one", fg: Theme.color(:muted))]

        _ ->
          traces
          |> Enum.with_index()
          |> Enum.map(fn {t, i} -> trace_line(t, i == s.editor_sel) end)
      end

    limit_lines =
      @limits
      |> Enum.with_index(length(traces))
      |> Enum.map(fn {{key, label}, i} ->
        line(
          String.pad_trailing(label, 14) <> Integer.to_string(Map.fetch!(limits, key)),
          i == s.editor_sel
        )
      end)

    error =
      if s.error, do: [text(""), text("✗ #{s.error.message}", fg: Theme.color(:error))], else: []

    box(
      vstack(
        [text("Trace patterns", fg: Theme.color(:title), bold: true)] ++
          trace_lines ++
          [text(""), text("Limits", fg: Theme.color(:title), bold: true)] ++
          limit_lines ++
          error ++
          [
            text(""),
            text("j/k move · space on/off · n new · enter edit · d delete · esc back",
              fg: Theme.color(:muted)
            )
          ]
      ),
      title: "Edit session",
      width: width,
      height: height,
      padding: [top: 0, right: 2, bottom: 0, left: 2]
    )
  end

  defp trace_line(t, selected?),
    do: line("#{if t.enabled, do: "[x]", else: "[ ]"} #{t.text}", selected?)

  defp line(string, selected?) do
    style =
      if selected?,
        do: [fg: Theme.color(:text), bg: Theme.color(:element)],
        else: [fg: Theme.color(:text)]

    text("  " <> string <> " ", style)
  end

  defp input_view(kind, value, cursor, width, height) do
    title =
      case kind do
        :add -> "New trace pattern"
        {:edit, _} -> "Edit trace pattern"
        {:limit, key} -> "Limit: #{key}"
      end

    box(
      vstack([
        Widget.input(value,
          cursor: cursor,
          placeholder: "lists:seq/2, send, receive, or a number"
        ),
        text(""),
        text("Enter save · Esc cancel", fg: Theme.color(:muted))
      ]),
      title: title,
      width: width,
      height: height,
      padding: [top: 1, right: 2, bottom: 0, left: 2]
    )
  end

  defp detail_view(s, event, offset, width, height) do
    lines = lines(s, event, detail_width(width))
    rows = detail_rows(height)
    visible = lines |> Enum.drop(offset) |> Enum.take(rows)

    body =
      Enum.map(visible, fn parts ->
        case parts do
          [] -> text("")
          _ -> hstack(Enum.map(parts, fn {t, c} -> text(t, fg: c) end))
        end
      end)

    box(
      vstack(
        [
          text("#{event.ts}  #{event.kind}  #{event.pid} #{event.name}", fg: Theme.color(:muted)),
          text(event.mfa, fg: Theme.color(:title)),
          text("")
        ] ++
          body ++ [text(""), text("j/k scroll · any other key closes", fg: Theme.color(:muted))]
      ),
      title: "Event",
      width: width,
      height: height,
      padding: [top: 0, right: 2, bottom: 0, left: 2]
    )
  end
end
