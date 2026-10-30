defmodule Server.Tui.Session do
  @moduledoc """
  The session screen of the Terra TUI: the live event list, the session editor
  (trace patterns and limits), and the event detail page. `Server.Tui.App`
  keeps the screen state (a map from `new/3`) and gives it the keys, the
  one-second ticks, and the trace messages of the bridge. The screen calls
  `Server.Trace` and `Server.Config` directly, as `Server.Stores.SessionRoot`
  does. The keys follow `tui/src/SessionScreen.tsx`; `docs/terra-gaps.md`
  records the keys and features that differ.
  """

  import Terra.View

  alias Server.{Config, Trace}
  alias Server.Tui.{Highlight, Theme, Ui}
  alias Terra.Widget

  # tui/src/sessionTypes.ts
  @sorts [
    {"ts", "desc"},
    {"ts", "asc"},
    {"kind", "asc"},
    {"kind", "desc"},
    {"pid", "asc"},
    {"mfa", "asc"}
  ]
  @groups ~w(none pid mfa kind)
  @scopes ~w(all mfa pid info)
  @all_columns %{name: true, pid: true, mfa: true, info: true}
  @col %{pair: 6, ts: 12, name: 16, pid: 11, mfa: 22}
  @gap "  "
  @spark_n 12
  @ramp ~w(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)

  @doc """
  The screen state of a session. The events, the status, and the applied
  signature come from the `{:trace_snapshot, snap}` of the bridge.
  """
  def new(node_id, session_id, settings) do
    %{
      node_id: node_id,
      id: session_id,
      events: [],
      # the highest event id on the screen: the snapshot and the subscription can both give an event
      max_id: 0,
      status: "stopped",
      applied_sig: nil,
      ended: nil,
      error: nil,
      # the id of the selected event, or nil (no row shows as selected until j/k)
      sel: nil,
      sort: parse_sort(Map.get(settings, :default_sort)),
      filter: nil,
      group: "none",
      fold: false,
      page: :events,
      editor_sel: 0,
      highlight: %{},
      # running time and the event rate for the status chip
      elapsed: 0,
      arrived: 0,
      buckets: List.duplicate(0, @spark_n)
    }
  end

  @doc "Closes the session: stops its trace, as SessionRoot.terminate/2 does."
  def close(session), do: Trace.stop(session.id)

  @doc "True while the screen needs the one-second tick (the trace runs)."
  def ticking?(s), do: s.status == "running"

  @doc "The one-second tick: the remaining time and the rate sparkline."
  def second(%{status: "running"} = s),
    do: %{s | elapsed: s.elapsed + 1, buckets: tl(s.buckets) ++ [s.arrived], arrived: 0}

  def second(s), do: s

  # --- trace messages ---

  @doc "Applies a trace message of the bridge. `keep` is the event limit of the session."
  # Events that came before the snapshot and are newer than it stay on top.
  def trace({:trace_snapshot, snap}, s, keep) do
    top = max_id(snap.events, 0)
    events = Enum.take(Enum.filter(s.events, &(id(&1) > top)) ++ snap.events, keep)

    %{s | events: events, max_id: max(top, s.max_id), applied_sig: snap.applied_sig}
    |> put_status(snap.status)
  end

  def trace({:trace_events, events}, s, keep) do
    case Enum.filter(events, &(id(&1) > s.max_id)) do
      [] ->
        s

      fresh ->
        %{
          s
          | events: Enum.take(fresh ++ s.events, keep),
            max_id: max_id(fresh, s.max_id),
            arrived: s.arrived + length(fresh)
        }
    end
  end

  def trace({:trace_status, payload}, s, _keep) do
    %{s | applied_sig: payload.applied_sig, ended: Map.get(payload, :ended)}
    |> put_status(payload.status)
  end

  def trace({:trace_error, error}, s, _keep), do: %{s | error: error, status: "stopped"}
  def trace(:trace_reset, s, _keep), do: %{s | events: [], sel: nil, highlight: %{}}

  # A new run starts the clock and the sparkline again.
  defp put_status(%{status: "running"} = s, "running"), do: s

  defp put_status(s, "running"),
    do: %{s | status: "running", elapsed: 0, arrived: 0, buckets: List.duplicate(0, @spark_n)}

  defp put_status(s, status), do: %{s | status: status}

  defp id(event), do: String.to_integer(event.id)
  defp max_id(events, acc), do: Enum.reduce(events, acc, &max(id(&1), &2))

  # --- state of the status chip (tui/src/SessionScreen.tsx:103-110) ---

  defp state(s, node) do
    node_status = if node, do: node.status, else: "idle"

    cond do
      node_status == "error" -> :unreachable
      node_status != "connected" -> :connecting
      s.status == "running" -> :running
      s.ended -> :ended
      s.error -> :failed
      true -> :idle
    end
  end

  # --- keys ---

  @doc """
  Applies a key. `node` is the node of the session from the config. Returns
  `{:ok, session}`, or `:close` when the user leaves the session screen.
  """
  def key(key, s, node, size)

  def key(key, %{page: {:detail, offset}} = s, _node, size), do: detail_key(key, offset, s, size)
  def key(key, %{page: :editor} = s, node, _size), do: editor_key(key, s, node)
  def key(key, %{page: {:input, _, _, _, _}} = s, node, _size), do: input_key(key, s, node)
  def key(key, %{page: {:filter, _, _, _}} = s, _node, _size), do: filter_key(key, s)
  def key(key, %{page: {:sort, _}} = s, _node, _size), do: sort_key(key, s)
  def key(key, %{page: {:confirm, _, _, _}} = s, node, _size), do: confirm_key(key, s, node)
  def key(_key, %{page: :help} = s, _node, _size), do: {:ok, %{s | page: :events}}

  def key(key, %{page: :error} = s, _node, _size) when key in [:esc, {:char, "e"}],
    do: {:ok, %{s | page: :events}}

  def key(_key, %{page: :error} = s, _node, _size), do: {:ok, s}
  def key(key, %{page: :events} = s, node, size), do: events_key(key, s, node, size)

  defp events_key(:esc, s, node, _size) do
    if s.status == "running" do
      notes =
        if dirty?(node, s),
          do: ["⚠ unapplied changes will be lost · a to apply first"],
          else: []

      {:ok, %{s | page: {:confirm, "Stop trace and leave?", notes, :leave}}}
    else
      :close
    end
  end

  defp events_key(k, s, _node, _size) when k in [:down, {:char, "j"}], do: {:ok, move(s, 1)}
  defp events_key(k, s, _node, _size) when k in [:up, {:char, "k"}], do: {:ok, move(s, -1)}

  # Nothing selected yet: select the first event and open it in one press.
  defp events_key(:enter, s, _node, size) do
    s = if selected(s), do: s, else: move(s, 1)
    {:ok, open_detail(s, size)}
  end

  defp events_key({:char, " "}, s, node, _size) do
    case state(s, node) do
      :unreachable -> {:ok, tap(s, fn _ -> Config.request_connect(s.node_id) end)}
      st when st in [:idle, :ended, :failed] -> {:ok, put_error(s, Trace.start(s.node_id, s.id))}
      _ -> {:ok, s}
    end
  end

  defp events_key({:char, "x"}, %{status: "running"} = s, _node, _size) do
    Trace.stop(s.id)
    {:ok, %{s | error: nil}}
  end

  defp events_key({:ctrl, :l}, s, _node, _size) do
    Trace.clear(s.id)
    {:ok, %{s | error: nil}}
  end

  # `a` takes the place of Ctrl+S: the raw mode of the OTP tty keeps IXON, so
  # the terminal reads Ctrl+S as XOFF and stops the output.
  defp events_key({:char, "a"}, s, _node, _size),
    do: {:ok, put_error(s, Trace.apply_restart(s.id))}

  defp events_key({:ctrl, :d}, s, _node, _size), do: {:ok, delete_event(s)}

  defp events_key({:char, "d"}, s, _node, _size) do
    if selected(s),
      do: {:ok, %{s | page: {:confirm, "Delete this event?", [], :delete_event}}},
      else: {:ok, s}
  end

  defp events_key({:char, "e"}, %{error: %{detail: detail}} = s, _node, _size)
       when is_binary(detail) and detail != "",
       do: {:ok, %{s | page: :error}}

  defp events_key({:char, "f"}, s, _node, _size), do: {:ok, %{s | fold: not s.fold}}

  defp events_key({:char, "g"}, s, _node, _size),
    do: {:ok, %{s | group: next(@groups, s.group)}}

  defp events_key({:char, "o"}, s, _node, _size),
    do: {:ok, %{s | page: {:sort, Enum.find_index(@sorts, &(&1 == s.sort)) || 0}}}

  defp events_key({:char, "/"}, s, _node, _size) do
    {query, scope} = if s.filter, do: {s.filter.query, s.filter.scope}, else: {"", "all"}
    {:ok, %{s | page: {:filter, query, String.length(query), scope}}}
  end

  defp events_key({:char, "l"}, s, node, _size), do: {:ok, limits_input(s, node, :events)}
  defp events_key({:char, "t"}, s, _node, _size), do: {:ok, %{s | page: :editor, editor_sel: 0}}
  defp events_key({:char, "?"}, s, _node, _size), do: {:ok, %{s | page: :help}}
  defp events_key(_key, s, _node, _size), do: {:ok, s}

  defp put_error(s, :ok), do: %{s | error: nil}
  defp put_error(s, {:error, reason}), do: %{s | error: Server.Errors.humanize(reason)}

  defp next(list, item),
    do: Enum.at(list, rem((Enum.find_index(list, &(&1 == item)) || 0) + 1, length(list)))

  # The event rows only (no group headers), in screen order.
  defp event_rows(s), do: for({:event, e, ret} <- rows(s), do: {e, ret})

  defp selected(s) do
    s.sel && Enum.find(event_rows(s), fn {e, _ret} -> e.id == s.sel end)
  end

  defp move(s, delta) do
    events = event_rows(s)
    index = s.sel && Enum.find_index(events, fn {e, _ret} -> e.id == s.sel end)

    case {events, index} do
      {[], _} ->
        s

      {[{e, _} | _], nil} ->
        %{s | sel: e.id}

      _ ->
        %{
          s
          | sel:
              events
              |> Enum.at((index + delta) |> max(0) |> min(length(events) - 1))
              |> elem(0)
              |> Map.fetch!(:id)
        }
    end
  end

  # Event deletion is local to the screen, as the deleteEvent command of
  # SessionRoot. The row above takes the selection (tui/src/SessionScreen.tsx:251).
  defp delete_event(s) do
    rows = event_rows(s)

    case s.sel && Enum.find_index(rows, fn {e, _ret} -> e.id == s.sel end) do
      nil ->
        s

      index ->
        s = %{s | events: Enum.reject(s.events, &(&1.id == s.sel))}

        case Enum.at(event_rows(s), max(index - 1, 0)) do
          nil -> %{s | sel: nil}
          {e, _ret} -> %{s | sel: e.id}
        end
    end
  end

  # --- event rows (tui/src/sessionHelpers.ts:22-71) ---

  @doc """
  The rows of the event list: `{:header, label, count}` and `{:event, event,
  return}`. With fold, a return whose call is in the list goes on the call row.
  """
  def rows(s) do
    events = s.events

    events =
      if s.group == "none" and s.filter == nil,
        do: events,
        else: Enum.reject(events, &(&1.kind == "restart"))

    events = if s.filter, do: Enum.filter(events, &match_filter(&1, s.filter)), else: events
    {events, returns} = if s.fold, do: fold(events), else: {events, %{}}
    events = sort(events, s.sort)

    ret = fn e ->
      if e.kind == "call" and e.pair not in [nil, ""], do: Map.get(returns, e.pair)
    end

    case s.group do
      "none" ->
        Enum.map(events, &{:event, &1, ret.(&1)})

      group ->
        groups = Enum.group_by(events, &group_key(&1, group))

        events
        |> Enum.map(&group_key(&1, group))
        |> Enum.uniq()
        |> Enum.flat_map(fn key ->
          list = Map.fetch!(groups, key)
          label = if key == "", do: "-", else: key
          [{:header, label, length(list)} | Enum.map(list, &{:event, &1, ret.(&1)})]
        end)
    end
  end

  defp fold(events) do
    calls =
      for %{kind: "call", pair: pair} <- events,
          pair not in [nil, ""],
          into: MapSet.new(),
          do: pair

    returns =
      for %{kind: "retn", pair: pair} = e <- events,
          pair not in [nil, ""],
          into: %{},
          do: {pair, e.info}

    {Enum.reject(events, &(&1.kind == "retn" and MapSet.member?(calls, &1.pair))), returns}
  end

  defp sort(events, {key, dir}) do
    sorter = if dir == "asc", do: :asc, else: :desc

    case key do
      "ts" ->
        Enum.sort_by(events, &id/1, sorter)

      key ->
        Enum.sort_by(events, &{Map.get(&1, String.to_existing_atom(key)) || "", id(&1)}, sorter)
    end
  end

  defp group_key(e, "pid"), do: e.pid
  defp group_key(e, "mfa"), do: e.mfa || "-"
  defp group_key(e, "kind"), do: e.kind

  defp match_filter(e, %{scope: scope, query: query}) do
    q = String.downcase(query)

    fields =
      case scope do
        "pid" -> [e.pid]
        "mfa" -> [e.mfa]
        "info" -> [e.info]
        "all" -> [e.pid, e.mfa, e.info, e.name]
      end

    Enum.any?(fields, &(is_binary(&1) and String.contains?(String.downcase(&1), q)))
  end

  # tui/src/sessionHelpers.ts:73-83
  defp parse_sort(setting) do
    case String.split(setting || "", "_") do
      [key, dir] when key in ~w(ts kind pid mfa) ->
        {key, if(dir == "asc", do: "asc", else: "desc")}

      [key] when key in ~w(ts kind pid mfa) ->
        {key, "desc"}

      _ ->
        {"ts", "desc"}
    end
  end

  # --- sort and filter pages ---

  defp sort_key(k, %{page: {:sort, i}} = s) when k in [:down, {:char, "j"}],
    do: {:ok, %{s | page: {:sort, min(i + 1, length(@sorts) - 1)}}}

  defp sort_key(k, %{page: {:sort, i}} = s) when k in [:up, {:char, "k"}],
    do: {:ok, %{s | page: {:sort, max(i - 1, 0)}}}

  defp sort_key(:enter, %{page: {:sort, i}} = s),
    do: {:ok, %{s | sort: Enum.at(@sorts, i), page: :events}}

  defp sort_key(:esc, s), do: {:ok, %{s | page: :events}}
  defp sort_key(_key, s), do: {:ok, s}

  defp filter_key(:esc, s), do: {:ok, %{s | page: :events}}

  defp filter_key(:tab, %{page: {:filter, query, cursor, scope}} = s),
    do: {:ok, %{s | page: {:filter, query, cursor, next(@scopes, scope)}}}

  defp filter_key(key, %{page: {:filter, query, cursor, scope}} = s) do
    case Widget.input_event(key, query, cursor) do
      {:edit, query, cursor} ->
        {:ok, %{s | page: {:filter, query, cursor, scope}}}

      {:submit, query} ->
        filter =
          if String.trim(query) == "", do: nil, else: %{scope: scope, query: String.trim(query)}

        {:ok, %{s | filter: filter, page: :events}}

      _ ->
        {:ok, s}
    end
  end

  # --- confirm page ---

  defp confirm_key({:char, "y"}, %{page: {:confirm, _, _, action}} = s, node),
    do: confirm(action, %{s | page: back(action)}, node)

  defp confirm_key(k, %{page: {:confirm, _, _, action}} = s, _node)
       when k in [{:char, "n"}, :esc],
       do: {:ok, %{s | page: back(action)}}

  defp confirm_key(_key, s, _node), do: {:ok, s}

  defp back({:delete_trace, _id}), do: :editor
  defp back(_action), do: :events

  defp confirm(:leave, _s, _node), do: :close
  defp confirm(:delete_event, s, _node), do: {:ok, delete_event(s)}

  defp confirm({:delete_trace, id}, s, node) do
    update_traces(node, s, &Enum.reject(&1, fn t -> t.id == id end))
    {:ok, s}
  end

  # --- editor: trace patterns (tui/src/SessionScreen.tsx:379-400) ---

  defp editor_key(:esc, s, _node), do: {:ok, %{s | page: :events}}

  defp editor_key(k, s, node) when k in [:down, {:char, "j"}],
    do: {:ok, editor_move(s, node, 1)}

  defp editor_key(k, s, node) when k in [:up, {:char, "k"}],
    do: {:ok, editor_move(s, node, -1)}

  defp editor_key({:char, "n"}, s, _node), do: {:ok, %{s | page: {:input, :add, "", 0, :editor}}}
  defp editor_key({:char, "l"}, s, node), do: {:ok, limits_input(s, node, :editor)}

  defp editor_key(key, s, node) do
    case {key, Enum.at(traces(node, s), s.editor_sel)} do
      {_key, nil} ->
        {:ok, s}

      {k, t} when k in [:enter, {:char, "e"}] ->
        {:ok, %{s | page: {:input, {:edit, t.id}, t.text, String.length(t.text), :editor}}}

      {{:char, " "}, t} ->
        update_traces(
          node,
          s,
          &Enum.map(&1, fn x -> if x.id == t.id, do: %{x | enabled: not x.enabled}, else: x end)
        )

        {:ok, s}

      {{:char, "d"}, t} ->
        {:ok, %{s | page: {:confirm, ~s(Delete trace "#{t.text}"?), [], {:delete_trace, t.id}}}}

      {{:ctrl, :d}, t} ->
        confirm({:delete_trace, t.id}, s, node)

      _ ->
        {:ok, s}
    end
  end

  defp editor_move(s, node, delta) do
    case length(traces(node, s)) do
      0 -> s
      n -> %{s | editor_sel: Integer.mod(s.editor_sel + delta, n)}
    end
  end

  # tui/src/limits.ts: "keep time msgs", space-separated.
  defp limits_input(s, node, back) do
    l = session_limits(node, s)
    value = "#{l.keep} #{l.time} #{l.msgs}"
    %{s | page: {:input, :limits, value, String.length(value), back}}
  end

  defp input_key(:esc, %{page: {:input, _, _, _, back}} = s, _node), do: {:ok, %{s | page: back}}

  defp input_key(key, %{page: {:input, kind, value, cursor, back}} = s, node) do
    case Widget.input_event(key, value, cursor) do
      {:edit, value, cursor} -> {:ok, %{s | page: {:input, kind, value, cursor, back}}}
      {:submit, value} -> {:ok, submit(kind, String.trim(value), %{s | page: back}, node)}
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

  defp submit(:limits, text, s, node) do
    case parse_limits(text) do
      {:ok, keep, time, msgs} ->
        limits = Map.merge(session_limits(node, s), %{keep: keep, time: time, msgs: msgs})
        Config.update_session(s.node_id, s.id, %{limits: limits})
        %{s | error: nil}

      :error ->
        %{
          s
          | error: %Server.Schema.AppError{
              message: "Limits must be three numbers: keep time msgs",
              detail: nil
            }
        }
    end
  end

  defp parse_limits(text) do
    case text |> String.split() |> Enum.map(&Integer.parse/1) do
      [{keep, ""}, {time, ""}, {msgs, ""}] when keep >= 0 and time >= 0 and msgs >= 0 ->
        {:ok, keep, time, msgs}

      _ ->
        :error
    end
  end

  defp update_traces(node, s, fun),
    do: Config.update_session(s.node_id, s.id, %{traces: fun.(traces(node, s))})

  @doc "The session of `node` that the screen shows, or nil."
  def config(node, s), do: node && Enum.find(node.sessions, &(&1.id == s.id))

  defp traces(node, s), do: (config(node, s) || %{traces: []}).traces

  @doc "The limits of the session."
  def session_limits(node, s),
    do: (config(node, s) || %{limits: Config.settings().default_limits}).limits

  # --- detail page ---

  defp open_detail(s, {width, _height}) do
    case selected(s) do
      nil -> s
      {e, ret} -> %{cache(s, e, ret, detail_width(width)) | page: {:detail, 0}}
    end
  end

  defp detail_key(k, _offset, s, _size) when k in [:esc, :tab], do: {:ok, %{s | page: :events}}

  defp detail_key(k, offset, s, size) when k in [:down, {:char, "j"}],
    do: {:ok, scroll(s, offset + 1, size)}

  defp detail_key(k, offset, s, size) when k in [:up, {:char, "k"}],
    do: {:ok, scroll(s, offset - 1, size)}

  defp detail_key({:ctrl, :f}, offset, s, {_, h} = size),
    do: {:ok, scroll(s, offset + detail_rows(h), size)}

  defp detail_key({:ctrl, :b}, offset, s, {_, h} = size),
    do: {:ok, scroll(s, offset - detail_rows(h), size)}

  # Ctrl+N and Ctrl+P take the place of Ctrl+J and Ctrl+K: Terra reads Ctrl+J as Enter.
  defp detail_key({:ctrl, :n}, _offset, s, size), do: {:ok, open_detail(move(s, 1), size)}
  defp detail_key({:ctrl, :p}, _offset, s, size), do: {:ok, open_detail(move(s, -1), size)}
  defp detail_key(_key, _offset, s, _size), do: {:ok, s}

  defp scroll(s, offset, {width, height}) do
    case selected(s) do
      nil ->
        %{s | page: :events}

      {e, ret} ->
        last = max(length(lines(s, e, ret, detail_width(width))) - detail_rows(height), 0)
        %{s | page: {:detail, offset |> max(0) |> min(last)}}
    end
  end

  defp detail_width(width), do: max(width - 6, 10)
  # the border, the two meta lines and their blank line, and the hint line
  defp detail_rows(height), do: max(height - 7, 1)

  # The lexer runs once for each event, return, and width: the update keeps
  # its result, and the view reads it.
  defp cache(s, e, ret, width) do
    key = {e.id, ret, width}

    if Map.has_key?(s.highlight, key),
      do: s,
      else: %{s | highlight: Map.put(s.highlight, key, body_lines(e, ret, width))}
  end

  defp lines(s, e, ret, width),
    do: Map.get_lazy(s.highlight, {e.id, ret, width}, fn -> body_lines(e, ret, width) end)

  # tui/src/SessionDetail.tsx:57-95: the payload, the return, and the stack.
  defp body_lines(e, ret, width) do
    {payload, stack} = split_info(e)
    label = %{"call" => "args", "retn" => "return"} |> Map.get(e.kind, "payload")
    muted = Theme.color(:muted)

    [[{label, muted}] | Highlight.lines(payload, width)] ++
      if(ret, do: [[], [{"return", muted}] | Highlight.lines(ret, width)], else: []) ++
      if stack == [],
        do: [],
        else:
          [[], [{"stack", muted}]] ++
            (stack
             |> Enum.with_index(1)
             |> Enum.map(fn {line, i} ->
               [
                 {String.pad_leading("#{i}. ", 4), muted},
                 {Ui.fit(line, max(width - 4, 1)), muted}
               ]
             end))
  end

  # tui/src/sessionHelpers.ts:5-19
  defp split_info(%{kind: "call", info: info}) do
    {stack, payload} = info |> String.split("\n") |> Enum.split_with(&stack_line?/1)

    if stack == [],
      do: {info, []},
      else: {payload |> Enum.join("\n") |> String.trim_trailing(), stack}
  end

  defp split_info(e), do: {e.info, []}

  defp stack_line?(line),
    do: String.contains?(line, "cp = ") or String.contains?(line, "Return addr")

  # --- views ---

  @doc "The view of the screen. `tick` drives the connecting spinner."
  def view(s, node, settings, width, height, tick) do
    case s.page do
      {:detail, offset} -> detail_view(s, offset, width, height)
      :editor -> editor_view(s, node, width, height)
      {:input, kind, value, cursor, _back} -> input_view(kind, value, cursor, width, height)
      {:filter, query, cursor, scope} -> filter_view(query, cursor, scope, width, height)
      {:sort, i} -> sort_view(i, width, height)
      {:confirm, question, notes, _} -> Ui.confirm(width, height, question, notes)
      :help -> Ui.page(width, height, "Help · session", Ui.help_lines(help_rows()))
      :error -> error_view(s, width, height)
      :events -> events_view(s, node, settings, width, height, tick)
    end
  end

  defp events_view(s, node, settings, width, height, tick) do
    flash = error_flash(s)
    # the header, the border, the column header, the flash, and the status line
    room = max(height - 5 - length(flash), 1)
    columns = Map.get(settings, :columns) || @all_columns
    # tui/src/SessionScreen.tsx:156-159: the pid column fits the longest pid.
    pid_width = Enum.reduce(s.events, @col.pid, &max(String.length(&1.pid), &2))
    widths = %{inner: max(width - 4, 10), pid: pid_width}
    all = rows(s)
    index = s.sel && Enum.find_index(all, &match?({:event, %{id: id}, _} when id == s.sel, &1))
    offset = if index, do: max(index - room + 1, 0), else: 0
    ditto? = s.group == "none" and s.filter == nil

    list =
      case all do
        [] ->
          [text(empty_text(s), fg: Theme.color(:muted))]

        _ ->
          all
          |> Enum.slice(offset, room)
          |> Enum.map_reduce(nil, fn
            {:header, label, count}, _prev ->
              {text(Ui.fit("#{label} · #{count}", widths.inner), fg: Theme.color(:muted)), nil}

            {:event, e, ret}, prev ->
              prev = if ditto?, do: prev
              {event_row(e, ret, e.id == s.sel, prev, columns, widths), e}
          end)
          |> elem(0)
      end

    # A Terra box fills all the rows below it, so a box of no border with
    # bottom padding keeps the rows of the flash and the status line free. A
    # stack places the next child below the measured height of the box, so the
    # box gets a fixed height.
    vstack(
      [
        header(node, s),
        box(
          box(vstack([column_header(columns, widths) | list]),
            title: events_title(s),
            width: width,
            padding: [top: 0, right: 1, bottom: 0, left: 1]
          ),
          border: false,
          height: max(height - 2 - length(flash), 3),
          padding: [top: 0, right: 0, bottom: 1 + length(flash), left: 0]
        )
      ] ++ flash ++ [status_line(s, node, width, tick)]
    )
  end

  defp events_title(s) do
    {key, dir} = s.sort
    filter = if s.filter, do: "#{s.filter.scope}/#{s.filter.query}", else: "-"
    fold = if s.fold, do: " · Fold", else: ""

    "Events · Sort:#{key}#{if dir == "asc", do: "↑", else: "↓"} · Filter:#{filter} · Group:#{s.group}#{fold}"
  end

  defp empty_text(%{status: "running"}), do: "Waiting for calls…"
  defp empty_text(_s), do: "No events yet · space to start"

  defp header(node, s) do
    node_name = if node, do: node.name, else: "?"
    name = if c = config(node, s), do: c.name, else: "?"

    hstack([
      text(" redbug ", fg: Theme.color(:title), bold: true),
      text(" #{node_name} ▸ #{name} ", fg: Theme.color(:text), bg: Theme.color(:element))
    ])
  end

  defp error_flash(%{error: nil}), do: []

  defp error_flash(%{error: error}) do
    more = if is_binary(error.detail) and error.detail != "", do: " · e detail", else: ""
    [text("✗ #{error.message}#{more}", fg: Theme.color(:error))]
  end

  defp dirty?(node, s) do
    c = config(node, s)

    c != nil and s.status == "running" and
      Server.Trace.Signature.compute(c.traces, c.limits) != s.applied_sig
  end

  defp column_header(columns, widths) do
    [
      Ui.fit("#", @col.pair) <> @gap,
      Ui.fit("Ts", @col.ts) <> @gap,
      columns[:name] && Ui.fit("Name", @col.name) <> @gap,
      columns[:pid] && Ui.fit("Pid", widths.pid) <> @gap,
      columns[:mfa] && Ui.fit("  Mfa", @col.mfa + 2) <> @gap,
      columns[:info] && "Info"
    ]
    |> Enum.filter(& &1)
    |> Enum.join()
    |> Ui.fit(widths.inner)
    |> text(fg: Theme.color(:muted))
  end

  # tui/src/SessionEvents.tsx:23-75
  defp event_row(%{kind: "restart"} = e, _ret, selected?, _prev, _columns, widths),
    do:
      text(
        Ui.fit("── #{e.info} ──", widths.inner),
        [fg: Theme.color(:muted)] ++ sel_bg(selected?)
      )

  defp event_row(e, ret, selected?, prev, columns, widths) do
    bg = sel_bg(selected?)
    ditto_name? = prev != nil and prev.name == e.name and not selected?
    ditto_pid? = prev != nil and prev.pid == e.pid and not selected?
    pair = if e.pair in [nil, ""], do: "", else: "##{e.pair}"
    lead = String.duplicate("  ", min(e.depth || 0, 8))
    info = if ret, do: "#{e.info} → #{ret}", else: e.info

    [
      {Ui.fit(pair, @col.pair) <> @gap, :muted},
      {Ui.fit(e.ts, @col.ts) <> @gap, :muted},
      columns[:name] &&
        {Ui.fit(blank(e.name), @col.name) <> @gap, if(ditto_name?, do: :muted, else: :text)},
      columns[:pid] &&
        {Ui.fit(e.pid, widths.pid) <> @gap, if(ditto_pid?, do: :muted, else: :text)},
      columns[:mfa] && {kind_mark(e.kind) <> " ", kind_color(e.kind)},
      columns[:mfa] && {Ui.fit(blank(e.mfa), @col.mfa) <> @gap, :text},
      columns[:info] && {lead <> one_line(info), :text}
    ]
    |> Enum.filter(& &1)
    |> fit_parts(widths.inner)
    |> Enum.map(fn {t, c} -> text(t, [fg: Theme.color(c)] ++ bg) end)
    |> hstack()
  end

  defp sel_bg(true), do: [bg: Theme.color(:element)]
  defp sel_bg(false), do: []

  defp blank(value) when value in [nil, ""], do: "-"
  defp blank(value), do: value

  # tui/src/sessionTypes.ts:23-29
  defp kind_mark("call"), do: "→"
  defp kind_mark("retn"), do: "←"
  defp kind_mark("send"), do: "↑"
  defp kind_mark("recv"), do: "↓"
  defp kind_mark(_kind), do: "?"

  defp kind_color("call"), do: :title
  defp kind_color("retn"), do: :success
  defp kind_color(_kind), do: :warning

  defp one_line(text), do: String.replace(text, ~r/\s*\n\s*/, " ")

  # Cut the parts to `width` cells, then pad the row to the width.
  defp fit_parts(parts, width) do
    {parts, used} =
      Enum.reduce(parts, {[], 0}, fn {t, c}, {acc, used} ->
        room = width - used
        w = Terra.Width.string(t)

        cond do
          room <= 0 -> {acc, used}
          w <= room -> {[{t, c} | acc], used + w}
          true -> {[{Ui.fit(t, room), c} | acc], width}
        end
      end)

    Enum.reverse([{String.duplicate(" ", max(width - used, 0)), :muted} | parts])
  end

  # tui/src/SessionStatus.tsx:24-46 and tui/src/SessionScreen.tsx:411-424
  defp status_line(s, node, width, tick) do
    {chip, color} = chip(s, node, tick)
    dirty = if state(s, node) == :running and dirty?(node, s), do: "  ⚠ unapplied", else: ""

    space =
      case state(s, node) do
        :unreachable -> "space retry"
        :idle -> "space start"
        st when st in [:ended, :failed] -> "space restart"
        :running -> if dirty == "", do: "x stop", else: "x stop · a apply"
        :connecting -> nil
      end

    hints =
      [
        "j/k move",
        "enter detail",
        "f #{if s.fold, do: "unfold", else: "fold"}",
        "t traces",
        "d del",
        space,
        "? help",
        "esc back"
      ]
      |> Enum.filter(& &1)
      |> Enum.join(" · ")

    room = width - Terra.Width.string(chip) - String.length(dirty) - 3

    hstack(
      [text(chip, fg: Theme.color(color)), text(dirty, fg: Theme.color(:warning)), text("   ")] ++
        Ui.hints(hints, room)
    )
  end

  defp chip(s, node, tick) do
    limits = session_limits(node, s)

    case state(s, node) do
      :connecting ->
        {"#{Ui.spinner(tick)} connecting…", :warning}

      :unreachable ->
        {"✖ can't reach node", :error}

      :idle ->
        {"◇ idle", :muted}

      :ended ->
        if s.ended == "msgs",
          do: {"⧗ msgs limit (#{limits.msgs})", :warning},
          else: {"⧗ time limit (#{limits.time}s)", :warning}

      :failed ->
        {"✖ restart failed · space retry", :error}

      :running ->
        spark = if Enum.any?(s.buckets, &(&1 > 0)), do: sparkline(s.buckets) <> " ", else: ""
        remaining = max(limits.time - s.elapsed, 0)
        {"● #{spark}#{length(s.events)}/#{limits.keep} · #{remaining}s", :success}
    end
  end

  # tui/src/sessionHelpers.ts:144-149
  defp sparkline(buckets) do
    top = Enum.max([1 | buckets])
    n = length(@ramp) - 1
    Enum.map_join(buckets, &Enum.at(@ramp, min(n, floor(&1 / top * n))))
  end

  defp help_rows do
    [
      {"j/k  ↓/↑", "move"},
      {"enter", "open detail"},
      {"f", "fold call+return into one row"},
      {"o", "sort"},
      {"/", "filter (Tab changes the scope)"},
      {"g", "cycle grouping"},
      {"l", "limits"},
      {"t", "trace patterns"},
      {"space", "start, restart, or reconnect"},
      {"x", "stop"},
      {"a", "apply the changes (restart)"},
      {"Ctrl+L", "clear the events"},
      {"e / d", "error detail / delete event"},
      {"Ctrl+D", "delete event (no confirm)"},
      {"esc", "back (asks while the trace runs)"},
      {:section, "detail page"},
      {"j/k", "scroll"},
      {"Ctrl+F/B", "page down / up"},
      {"Ctrl+N/P", "next / previous event"},
      {"esc  tab", "close"}
    ]
  end

  defp error_view(s, width, height) do
    body = (s.error && (s.error.detail || s.error.message)) || ""

    lines =
      body
      |> String.split("\n")
      |> Enum.take(max(height - 4, 1))
      |> Enum.map(&text(Ui.fit(&1, max(width - 6, 1)), fg: Theme.color(:text)))

    Ui.page(
      width,
      height,
      "Error",
      lines ++ [text(""), text("esc/e close", fg: Theme.color(:muted))]
    )
  end

  defp editor_view(s, node, width, height) do
    traces = traces(node, s)
    l = session_limits(node, s)

    trace_lines =
      case traces do
        [] ->
          [text("  no trace patterns · n adds one", fg: Theme.color(:muted))]

        _ ->
          traces
          |> Enum.with_index()
          |> Enum.map(fn {t, i} ->
            line("#{if t.enabled, do: "[x]", else: "[ ]"} #{t.text}", i == s.editor_sel)
          end)
      end

    error =
      if s.error, do: [text(""), text("✗ #{s.error.message}", fg: Theme.color(:error))], else: []

    Ui.page(
      width,
      height,
      "Trace patterns",
      trace_lines ++
        [
          text(""),
          text("Limits  keep #{l.keep} · time #{l.time}s · msgs #{l.msgs}",
            fg: Theme.color(:muted)
          )
        ] ++
        error ++
        [
          text(""),
          text("j/k move · space on/off · n new · e edit · d del · l limits · esc back",
            fg: Theme.color(:muted)
          )
        ]
    )
  end

  defp line(string, selected?) do
    style = [fg: Theme.color(:text)] ++ sel_bg(selected?)
    text("  " <> string <> " ", style)
  end

  defp input_view(kind, value, cursor, width, height) do
    {title, notes, placeholder} =
      case kind do
        :add ->
          {"New trace pattern", [], "Enum.map/2 -> return"}

        {:edit, _} ->
          {"Edit trace pattern", [], "Enum.map/2 -> return"}

        :limits ->
          {"Session limits",
           [
             "keep time msgs (space-separated)",
             "keep = TUI buffer cap · time = stop after Ns · msgs = stop after N events"
           ], "500 900 10000"}
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

  defp filter_view(query, cursor, scope, width, height) do
    scopes =
      Enum.map(@scopes, fn x ->
        if x == scope,
          do: text(" #{x} ", fg: Theme.color(:text), bg: Theme.color(:element)),
          else: text(" #{x} ", fg: Theme.color(:muted))
      end)

    Ui.page(width, height, "Filter events", [
      hstack([text("Scope ", fg: Theme.color(:muted)) | scopes]),
      hstack([
        text("Query ", fg: Theme.color(:muted)),
        Widget.input(query, cursor: cursor, placeholder: "text to match")
      ]),
      text(""),
      text("Tab scope · Enter apply (empty clears) · Esc cancel", fg: Theme.color(:muted))
    ])
  end

  defp sort_view(index, width, height) do
    options =
      @sorts
      |> Enum.with_index()
      |> Enum.map(fn {{key, dir}, i} ->
        line("#{key} #{if dir == "asc", do: "↑ asc", else: "↓ desc"}", i == index)
      end)

    Ui.page(
      width,
      height,
      "Sort events",
      options ++ [text(""), text("j/k move · Enter apply · Esc cancel", fg: Theme.color(:muted))]
    )
  end

  defp detail_view(s, offset, width, height) do
    case selected(s) do
      nil ->
        Ui.page(width, height, "Detail", [text("No event", fg: Theme.color(:muted))])

      {e, ret} ->
        body =
          s
          |> lines(e, ret, detail_width(width))
          |> Enum.drop(offset)
          |> Enum.take(detail_rows(height))
          |> Enum.map(fn
            [] -> text("")
            parts -> hstack(Enum.map(parts, fn {t, c} -> text(t, fg: c) end))
          end)

        Ui.page(
          width,
          height,
          "Detail",
          [
            hstack([
              Ui.chip("Kind", "#{kind_mark(e.kind)} #{e.kind}"),
              text(" "),
              Ui.chip("Ts", e.ts),
              text(" "),
              Ui.chip("Pid", e.pid),
              text(" "),
              Ui.chip("Name", blank(e.name))
            ]),
            Ui.chip("Mfa", blank(e.mfa)),
            text("")
          ] ++
            body ++
            [text("j/k scroll · ^F/^B page · ^N/^P event · esc close", fg: Theme.color(:muted))]
        )
    end
  end
end
