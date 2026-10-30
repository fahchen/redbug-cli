defmodule Server.Tui.App do
  @moduledoc """
  The Terra app of the TUI: the node screen. It runs in the controller BEAM
  and calls `Server.Config` directly, not over the WebSocket.

  `init/1` starts a `Server.Tui.Bridge`, which sends config changes to the
  runtime in batches as `{:nodes, nodes, settings}` messages, and the trace
  messages of the open session. The node screen has the node list and the
  sessions pane of the selected node; `Server.Tui.Session` is the session
  screen. The layout takes its sizes from `{:resize, w, h}`. The node form, the
  session name and preset pages, the confirm question, and the help are
  full-screen pages. `docs/terra-gaps.md` records each feature of the Bun TUI
  that this app cuts or simplifies.
  """

  use Terra

  alias Server.{Config, Remote}
  alias Server.Tui.{Bridge, Presets, Session, Settings, Snippets, Theme, Ui}
  alias Terra.Widget

  @list_width 40
  @spin_ms 80

  # {key, label, section note before the field (or nil), placeholder}
  @fields [
    {:name, "Node name", {"Connection", "how the controller reaches the Erlang node"},
     "myapp, the part before @ in myapp@host"},
    {:host, "Host", nil, "127.0.0.1, where the node runs"},
    {:cookie, "Cookie", nil, "secretcookie, Erlang distribution cookie"},
    {:port, "Dist port", nil, "optional, distribution port for a direct dial"},
    {:ssh_host, "SSH host", {"SSH tunnel", "optional, for a node behind an SSH bastion"},
     "bastion.example.com, leave blank to dial directly"},
    {:ssh_port, "SSH port", nil, "22"},
    {:ssh_user, "SSH user", nil, "deploy"},
    {:container, "Container", {"Container", "optional, a Docker container on the SSH host"},
     "myapp, leave blank for a host process"},
    {:label, "Label", {"Display", "optional, alias shown in the node list"}, "Staging"}
  ]
  @field_keys Enum.map(@fields, &elem(&1, 0))

  @impl Terra.App
  def init(opts) do
    bridge = Bridge.start_link(self(), query_size: Keyword.get(opts, :query_size, false))

    %{
      width: Keyword.get(opts, :width, 80),
      height: Keyword.get(opts, :height, 24),
      bridge: bridge,
      nodes: Config.nodes(),
      settings: Config.settings(),
      selected: 0,
      focus: :nodes,
      sess_sel: 0,
      # the digits typed before `g` in the sessions pane
      digits: "",
      # the open session screen (Server.Tui.Session), or nil
      session: nil,
      page: :nodes,
      tick: 0,
      ticking: false,
      seconds: false
    }
    |> with_ticks()
  end

  @impl Terra.App
  def update(msg, state) do
    case handle(msg, state) do
      {:quit, state} -> {:quit, state}
      state -> with_ticks(state)
    end
  end

  # --- messages that every page takes ---

  defp handle({:resize, w, h}, state), do: %{state | width: w, height: h}

  defp handle({:nodes, nodes, settings}, state),
    do: clamp(%{state | nodes: nodes, settings: settings})

  defp handle(:spin, state), do: %{state | tick: state.tick + 1, ticking: false}

  defp handle(:second, %{session: nil} = state), do: %{state | seconds: false}

  defp handle(:second, state),
    do: %{state | session: Session.second(state.session), seconds: false}

  # Trace messages of the bridge for the open session; a late message of a
  # closed session has no effect.
  defp handle({:trace_snapshot, id, snap}, state), do: trace(state, id, {:trace_snapshot, snap})
  defp handle({:trace_events, id, events}, state), do: trace(state, id, {:trace_events, events})
  defp handle({:trace_status, id, payload}, state), do: trace(state, id, {:trace_status, payload})
  defp handle({:trace_error, id, error}, state), do: trace(state, id, {:trace_error, error})
  defp handle({:trace_reset, id}, state), do: trace(state, id, :trace_reset)

  # --- pages ---

  defp handle(key, %{page: :session} = state) do
    case Session.key(key, state.session, session_node(state), {state.width, state.height}) do
      {:ok, session} -> %{state | session: session}
      {:settings, session} -> open_screen(%{state | session: session}, Settings)
      :close -> close_session(state)
    end
  end

  # The presets, snippets, and settings screens. `back` is the page to show
  # when the screen closes (tui/src/App.tsx:113-136).
  defp handle(key, %{page: {:screen, module, screen, back}} = state) do
    case module.key(key, screen) do
      {:ok, screen} ->
        %{state | page: {:screen, module, screen, back}}

      {:settings, screen} ->
        open_screen(%{state | page: {:screen, module, screen, back}}, Settings)

      :close ->
        %{state | page: back}
    end
  end

  defp handle(_key, %{page: :help} = state), do: %{state | page: :nodes}

  defp handle(key, %{page: {:session_name, node_id, value, cursor}} = state) do
    case key do
      :esc ->
        %{state | page: :nodes}

      key ->
        case Widget.input_event(key, value, cursor) do
          {:edit, value, cursor} ->
            %{state | page: {:session_name, node_id, value, cursor}}

          {:submit, value} ->
            if String.trim(value) == "",
              do: state,
              else: %{state | page: {:session_preset, node_id, String.trim(value), 0}}

          _ ->
            state
        end
    end
  end

  defp handle(key, %{page: {:session_preset, node_id, name, index}} = state) do
    # the options: blank, then each preset
    count = length(Config.presets()) + 1

    case key do
      k when k in [:down, {:char, "j"}] ->
        %{state | page: {:session_preset, node_id, name, min(index + 1, count - 1)}}

      k when k in [:up, {:char, "k"}] ->
        %{state | page: {:session_preset, node_id, name, max(index - 1, 0)}}

      :esc ->
        %{state | page: :nodes}

      :enter ->
        create_session(state, node_id, name, index)

      _ ->
        state
    end
  end

  defp handle(key, %{page: {:rename, node_id, id, value, cursor}} = state) do
    case key do
      :esc ->
        %{state | page: :nodes}

      key ->
        case Widget.input_event(key, value, cursor) do
          {:edit, value, cursor} ->
            %{state | page: {:rename, node_id, id, value, cursor}}

          {:submit, value} ->
            name = String.trim(value)
            if name != "", do: Config.update_session(node_id, id, %{name: name})
            %{state | page: :nodes}

          _ ->
            state
        end
    end
  end

  defp handle(key, %{page: {:confirm, _question, action}} = state) do
    case key do
      {:char, "y"} -> confirm(action, %{state | page: :nodes})
      {:char, "n"} -> %{state | page: :nodes}
      :esc -> %{state | page: :nodes}
      _ -> state
    end
  end

  defp handle(key, %{page: {:form, form}} = state), do: form_key(key, form, state)
  defp handle(key, %{page: :nodes, focus: :sessions} = state), do: sessions_key(key, state)
  defp handle(key, %{page: :nodes} = state), do: nodes_key(key, state)

  defp trace(%{session: %{id: id} = session} = state, id, message) do
    keep = Session.session_limits(session_node(state), session).keep
    %{state | session: Session.trace(message, session, keep)}
  end

  defp trace(state, _id, _message), do: state

  # --- sessions pane keys (tui/src/App.tsx:376-449) ---

  defp sessions_key({:ctrl, :d}, state) do
    case current_session(state) do
      nil -> state
      session -> confirm({:delete_session, current(state).id, session}, state)
    end
  end

  defp sessions_key(key, state) when key in [:esc, :tab, :left, {:char, "h"}],
    do: %{state | focus: :nodes, digits: ""}

  defp sessions_key(key, state) when key in [:down, {:char, "j"}], do: move_session(state, 1)
  defp sessions_key(key, state) when key in [:up, {:char, "k"}], do: move_session(state, -1)

  defp sessions_key(:enter, state) do
    case current_session(state) do
      nil -> state
      session -> open_session(state, current(state).id, session.id)
    end
  end

  defp sessions_key({:char, "n"}, state), do: new_session(state)

  defp sessions_key({:char, "r"}, state) do
    case current_session(state) do
      nil -> state
      s -> %{state | page: {:rename, current(state).id, s.id, s.name, String.length(s.name)}}
    end
  end

  defp sessions_key({:char, "d"}, state) do
    case current_session(state) do
      nil ->
        state

      s ->
        question = ~s(Delete session "#{s.name}"?)
        %{state | page: {:confirm, question, {:delete_session, current(state).id, s}}}
    end
  end

  # `<number>g` jumps to the session of that number.
  defp sessions_key({:char, "g"}, %{digits: digits} = state) when digits != "" do
    n = String.to_integer(digits)
    count = length(sessions(state))

    if n >= 1 and count > 0,
      do: %{state | sess_sel: min(n - 1, count - 1), digits: ""},
      else: %{state | digits: ""}
  end

  defp sessions_key({:char, "?"}, state), do: %{state | page: :help}

  defp sessions_key({:char, d}, state) when d in ~w(0 1 2 3 4 5 6 7 8 9),
    do: %{state | digits: state.digits <> d}

  defp sessions_key(_key, state), do: %{state | digits: ""}

  defp sessions(state), do: (current(state) || %{sessions: []}).sessions
  defp current_session(state), do: Enum.at(sessions(state), state.sess_sel)

  defp move_session(state, delta) do
    case length(sessions(state)) do
      0 -> state
      n -> %{state | sess_sel: Integer.mod(state.sess_sel + delta, n), digits: ""}
    end
  end

  defp new_session(state) do
    case current(state) do
      nil -> state
      node -> %{state | page: {:session_name, node.id, "", 0}}
    end
  end

  # The createSession command of Server.Stores.NodeStore: the traces of the
  # preset get new ids. The new session opens, as in tui/src/App.tsx:257-268.
  defp create_session(state, node_id, name, index) do
    {traces, limits} =
      case Enum.at(Config.presets(), index - 1) do
        preset when index > 0 and preset != nil ->
          {Enum.map(preset.traces, &%{&1 | id: Config.gen_id()}), preset.limits}

        _ ->
          {[], Config.settings().default_limits}
      end

    {:ok, id} = Config.add_session(node_id, %{name: name, traces: traces, limits: limits})
    state = %{state | nodes: Config.nodes(), focus: :sessions}
    sess_sel = state |> sessions() |> Enum.find_index(&(&1.id == id)) || 0
    open_session(%{state | sess_sel: sess_sel}, node_id, id)
  end

  # Opening a session connects its node, as SessionRoot.mount/2 does.
  defp open_session(state, node_id, id) do
    if Config.node_connection(node_id).status != "connected", do: Config.request_connect(node_id)
    Bridge.watch(state.bridge, id)
    %{state | page: :session, session: Session.new(node_id, id, state.settings), digits: ""}
  end

  defp open_screen(state, module),
    do: %{state | page: {:screen, module, module.new(), state.page}}

  defp close_session(state) do
    Session.close(state.session)
    Bridge.watch(state.bridge, nil)
    %{state | page: :nodes, session: nil}
  end

  defp session_node(%{session: session} = state),
    do: Enum.find(state.nodes, &(&1.id == session.node_id))

  # --- node list keys ---

  defp nodes_key(key, state) when key in [:down, {:char, "j"}], do: move(state, 1)
  defp nodes_key(key, state) when key in [:up, {:char, "k"}], do: move(state, -1)

  # The sessions pane takes the focus even when it is empty, so `n` there
  # adds the first session.
  defp nodes_key(key, state) when key in [:enter, :tab, :right] do
    if current(state), do: %{state | focus: :sessions, sess_sel: 0}, else: state
  end

  defp nodes_key({:char, "n"}, state) do
    if Config.env_mode?(), do: state, else: %{state | page: {:form, new_form(:new, %{})}}
  end

  defp nodes_key({:char, "e"}, state) do
    case editable(state) do
      nil -> state
      node -> %{state | page: {:form, new_form({:edit, node.id}, node_fields(node))}}
    end
  end

  defp nodes_key({:char, "c"}, state) do
    case current(state) do
      nil -> state
      %{status: "connected"} = node -> tap(state, fn _ -> Config.disconnect_node(node.id) end)
      node -> tap(state, fn _ -> Config.request_connect(node.id) end)
    end
  end

  defp nodes_key({:char, "d"}, state) do
    case editable(state) do
      nil ->
        state

      node ->
        question = ~s(Delete node "#{node.name}" and all its sessions?)
        %{state | page: {:confirm, question, {:delete, node}}}
    end
  end

  defp nodes_key({:ctrl, :d}, state) do
    case editable(state) do
      nil -> state
      node -> confirm({:delete, node}, state)
    end
  end

  defp nodes_key({:char, "p"}, state), do: open_screen(state, Presets)
  defp nodes_key({:char, "l"}, state), do: open_screen(state, Snippets)
  defp nodes_key({:char, ","}, state), do: open_screen(state, Settings)
  defp nodes_key({:char, "?"}, state), do: %{state | page: :help}
  defp nodes_key({:char, "q"}, state), do: %{state | page: {:confirm, "Quit redbug?", :quit}}
  defp nodes_key(_key, state), do: state

  defp confirm(:quit, state), do: {:quit, state}

  # The same steps as the deleteNode command of Server.Stores.NodeStore: stop
  # the traces and the console of each session, then delete the node.
  defp confirm({:delete, node}, state) do
    Enum.each(node.sessions, fn s ->
      Server.Trace.terminate(s.id)
      Remote.purge(s.id)
    end)

    Config.delete_node(node.id)
    %{state | selected: max(state.selected - 1, 0)}
  end

  # The deleteSession command of Server.Stores.SessionItemStore.
  defp confirm({:delete_session, node_id, session}, state) do
    Server.Trace.terminate(session.id)
    Remote.purge(session.id)
    Config.delete_session(node_id, session.id)
    %{state | sess_sel: max(state.sess_sel - 1, 0)}
  end

  defp move(%{nodes: []} = state, _delta), do: state

  defp move(state, delta),
    do: %{state | selected: Integer.mod(state.selected + delta, length(state.nodes)), sess_sel: 0}

  defp clamp(state) do
    state = %{state | selected: state.selected |> min(length(state.nodes) - 1) |> max(0)}
    %{state | sess_sel: state.sess_sel |> min(length(sessions(state)) - 1) |> max(0)}
  end

  defp current(state), do: Enum.at(state.nodes, state.selected)

  defp editable(state) do
    case current(state) do
      %{source: "env"} -> nil
      node -> node
    end
  end

  # --- node form ---

  defp new_form(mode, values) do
    values = Map.new(@field_keys, &{&1, Map.get(values, &1, "")})
    %{mode: mode, values: values, focus: 0, cursor: String.length(values.name), error: nil}
  end

  # The form shows the name of `name@host` as two fields.
  defp node_fields(node) do
    {name, host} =
      case String.split(node.name, "@", parts: 2) do
        [name, host] -> {name, host}
        [name] -> {name, ""}
      end

    for key <- @field_keys, into: %{} do
      case key do
        :name -> {key, name}
        :host -> {key, host}
        key -> {key, Map.get(node, key) || ""}
      end
    end
  end

  defp form_key(key, form, state) when key in [:tab, :down], do: focus(form, state, 1)
  defp form_key(key, form, state) when key in [{:ctrl, :tab}, :up], do: focus(form, state, -1)
  defp form_key(:esc, _form, state), do: %{state | page: :nodes}
  defp form_key(:enter, form, state), do: save(form, state)

  defp form_key(key, form, state) do
    field = Enum.at(@field_keys, form.focus)

    case Widget.input_event(key, form.values[field], form.cursor) do
      {:edit, value, cursor} ->
        form = %{form | values: Map.put(form.values, field, value), cursor: cursor}
        %{state | page: {:form, form}}

      _ ->
        state
    end
  end

  defp focus(form, state, delta) do
    index = Integer.mod(form.focus + delta, length(@fields))
    value = form.values[Enum.at(@field_keys, index)]
    %{state | page: {:form, %{form | focus: index, cursor: String.length(value)}}}
  end

  defp save(form, state) do
    case validate(form.values) do
      :ok ->
        attrs = attrs(form.values)

        case form.mode do
          :new -> Config.add_node(attrs)
          {:edit, id} -> Config.update_node(id, attrs)
        end

        %{state | page: :nodes}

      {:error, message} ->
        %{state | page: {:form, %{form | error: message}}}
    end
  end

  # A node behind SSH finds its name and cookie on connect; a direct node needs them.
  defp validate(%{ssh_host: ssh_host} = values) do
    cond do
      String.trim(ssh_host) != "" ->
        :ok

      String.trim(values.name) == "" or String.trim(values.cookie) == "" ->
        {:error, "Direct node needs a name and cookie"}

      not valid_host?(String.trim(values.host)) ->
        {:error,
         "Host must be a hostname or IP (e.g. 127.0.0.1 or app.example.com), not a bare number"}

      true ->
        :ok
    end
  end

  # tui/src/Tree.tsx:9-15: a dotted quad, or a name with a letter or a dot.
  defp valid_host?(host) do
    Regex.match?(~r/^\d{1,3}(\.\d{1,3}){3}$/, host) or
      (Regex.match?(~r/^[A-Za-z0-9.-]+$/, host) and Regex.match?(~r/[A-Za-z.]/, host))
  end

  defp attrs(values) do
    host = String.trim(values.host)
    name = if host == "", do: values.name, else: "#{String.trim(values.name)}@#{host}"

    values
    |> Map.drop([:host])
    |> Map.put(:name, name)
    |> Map.update!(:label, &if(&1 == "", do: nil, else: &1))
  end

  # --- spinner ---

  defp with_ticks(state) do
    {state, spin} = schedule_spin(state)
    {state, second} = schedule_second(state)

    case spin ++ second do
      [] -> state
      commands -> {state, commands}
    end
  end

  # A spinner tick runs only while a node connects.
  defp schedule_spin(%{ticking: false} = state) do
    if Enum.any?(state.nodes, &(&1.status == "connecting")),
      do: {%{state | ticking: true}, [{:tick, @spin_ms, :spin}]},
      else: {state, []}
  end

  defp schedule_spin(state), do: {state, []}

  # A one-second tick runs while the open session traces.
  defp schedule_second(%{seconds: false, session: session} = state) when session != nil do
    if Session.ticking?(session),
      do: {%{state | seconds: true}, [{:tick, 1000, :second}]},
      else: {state, []}
  end

  defp schedule_second(state), do: {state, []}

  # --- views ---

  @impl Terra.App
  def view(%{page: :session} = state) do
    Session.view(
      state.session,
      session_node(state),
      state.settings,
      state.width,
      state.height,
      state.tick
    )
  end

  def view(%{page: {:screen, module, screen, _back}} = state),
    do: module.view(screen, state.width, state.height)

  def view(%{page: :help} = state), do: page(state, "Help", Ui.help_lines(help_rows()))

  def view(%{page: {:confirm, question, _action}} = state),
    do: Ui.confirm(state.width, state.height, question)

  def view(%{page: {:session_name, _node_id, value, cursor}} = state) do
    page(state, "New session", [
      hstack([
        text("Name  ", fg: Theme.color(:title)),
        Widget.input(value, cursor: cursor, placeholder: "session name")
      ]),
      text(""),
      text("Enter next (pick a preset) · Esc cancel", fg: Theme.color(:muted))
    ])
  end

  def view(%{page: {:session_preset, _node_id, name, index}} = state) do
    options =
      ["blank (no trace patterns)" | Enum.map(Config.presets(), & &1.name)]
      |> Enum.with_index()
      |> Enum.map(fn {label, i} ->
        style = if i == index, do: [bg: Theme.color(:element)], else: []
        text("  #{label} ", [fg: Theme.color(:text)] ++ style)
      end)

    page(
      state,
      ~s(New session "#{name}" · start from),
      options ++ [text(""), text("j/k move · Enter create · Esc cancel", fg: Theme.color(:muted))]
    )
  end

  def view(%{page: {:rename, _node_id, _id, value, cursor}} = state) do
    page(state, "Rename session", [
      hstack([
        text("Name  ", fg: Theme.color(:title)),
        Widget.input(value, cursor: cursor, placeholder: "session name")
      ]),
      text(""),
      text("Enter save · Esc cancel", fg: Theme.color(:muted))
    ])
  end

  def view(%{page: {:form, form}} = state), do: page(state, form_title(form), form_lines(form))

  def view(state) do
    # The panels take the rows between the tab row and the status line.
    body = max(state.height - 2, 3)
    # Terra draws a box over all the width it gets, so the detail box starts on
    # the last column of the list box: the two boxes share one border column.
    detail_width = max(state.width - @list_width + 1, 10)

    panels =
      hstack(
        [
          box(list_view(state, body - 2), title: "Nodes", width: @list_width - 1),
          box(detail_view(state, body - 2),
            title: detail_title(state),
            width: detail_width,
            padding: [top: 0, right: 1, bottom: 0, left: 1]
          )
        ],
        height: body - 1
      )

    # A Terra box fills all the rows below it, so a box of no border with one
    # row of bottom padding keeps the last row free for the status line.
    vstack([
      tabs(),
      box(panels, border: false, padding: [top: 0, right: 0, bottom: 1, left: 0]),
      status_line(state)
    ])
  end

  defp tabs do
    hstack([
      text(" redbug ", fg: Theme.color(:title), bold: true),
      text(" Nodes ", fg: Theme.color(:text), bg: Theme.color(:element))
    ])
  end

  defp page(state, title, lines), do: Ui.page(state.width, state.height, title, lines)

  # --- node list ---

  defp list_view(%{nodes: []}, _rows) do
    vstack([
      text("No nodes yet", fg: Theme.color(:text)),
      text(""),
      text("Node ▸ Session ▸ Trace", fg: Theme.color(:muted)),
      text("                └ → Events", fg: Theme.color(:muted)),
      text("a target, a run, a pattern,", fg: Theme.color(:muted)),
      text("the calls it catches, live.", fg: Theme.color(:muted)),
      text(""),
      hstack([
        text("n", fg: Theme.color(:title)),
        text("  add your first node", fg: Theme.color(:muted))
      ])
    ])
  end

  defp list_view(state, rows) do
    # Keep the selected row in the window of `rows` rows.
    offset = max(state.selected - rows + 1, 0)

    state.nodes
    |> Enum.with_index()
    |> Enum.slice(offset, max(rows, 1))
    |> Enum.map(fn {node, index} -> node_row(node, index == state.selected, state.tick) end)
    |> vstack()
  end

  defp node_row(node, selected?, tick) do
    # the inner width of the list box: the shared border column, the left
    # border, and one blank cell on each side
    width = @list_width - 4
    bg = if selected?, do: [bg: Theme.color(:element)], else: []
    {glyph, glyph_color} = glyph(node.status, tick)
    name_color = if selected? or node.status == "connected", do: :text, else: :muted
    name = node[:label] || node.name
    env = if node.source == "env", do: "  env", else: ""
    count = Integer.to_string(length(node.sessions))
    name_width = max(width - 2 - String.length(env) - String.length(count) - 1, 1)

    hstack([
      text(" #{glyph} ", [fg: Theme.color(glyph_color)] ++ bg),
      text(Ui.fit(name, name_width), [fg: Theme.color(name_color)] ++ bg),
      text(env, [fg: Theme.color(:muted)] ++ bg),
      text(" #{count} ", [fg: Theme.color(:muted)] ++ bg)
    ])
  end

  defp glyph("connected", _tick), do: {"●", :success}
  defp glyph("connecting", tick), do: {Ui.spinner(tick), :warning}
  defp glyph("error", _tick), do: {"✖", :error}
  defp glyph(_status, _tick), do: {" ", :muted}

  # --- node detail ---

  defp detail_title(state) do
    case current(state) do
      nil -> "—"
      node -> node.name
    end
  end

  defp detail_view(state, rows) do
    case current(state) do
      nil ->
        text("Select a node", fg: Theme.color(:muted))

      node ->
        chips = chips(node)
        vstack(chips ++ [text("") | session_rows(state, node, rows - length(chips) - 1)])
    end
  end

  # tui/src/Tree.tsx:59-82: the number and the name of each session.
  defp session_rows(_state, %{sessions: []}, _rows),
    do: [text("No sessions · n to add", fg: Theme.color(:muted))]

  defp session_rows(state, node, rows) do
    rows = max(rows, 1)
    offset = max(state.sess_sel - rows + 1, 0)
    width = max(state.width - @list_width - 3, 10)

    node.sessions
    |> Enum.with_index()
    |> Enum.slice(offset, rows)
    |> Enum.map(fn {session, index} ->
      active? = state.focus == :sessions and index == state.sess_sel
      bg = if active?, do: [bg: Theme.color(:element)], else: []
      num = String.pad_leading("#{index + 1} ·", 4)

      hstack([
        text(num, [fg: Theme.color(if(active?, do: :title, else: :muted))] ++ bg),
        text(
          Ui.fit("  " <> session.name, max(width - 4, 1)),
          [fg: Theme.color(if(active?, do: :text, else: :muted))] ++ bg
        )
      ])
    end)
  end

  defp chips(node) do
    host =
      cond do
        present?(node[:ssh_host]) ->
          node.ssh_host

        String.contains?(node.name, "@") ->
          node.name |> String.split("@", parts: 2) |> List.last()

        true ->
          node.name
      end

    [
      present?(node[:label]) && chip("Label", node.label),
      chip("Host", host),
      chip("Cookie", redact(node.cookie)),
      present?(node[:ssh_host]) && chip("SSH", ssh(node)),
      present?(node[:container]) && chip("Container", node.container),
      node.source == "env" && chip("Source", "env (read-only)"),
      node[:error] && chip("Error", "#{node.error.message} · c retry", :error)
    ]
    |> Enum.filter(& &1)
  end

  defp chip(label, value, tone \\ :text), do: Ui.chip(label, value, tone)

  defp ssh(node),
    do: if(present?(node[:ssh_user]), do: "#{node.ssh_user}@", else: "") <> node.ssh_host

  # tui/src/Tree.tsx:85-89
  defp redact(cookie) when cookie in [nil, ""], do: "—"

  defp redact(cookie) do
    if String.length(cookie) <= 4,
      do: String.duplicate("•", String.length(cookie)),
      else: String.slice(cookie, 0, 2) <> "••••" <> String.slice(cookie, -2, 2)
  end

  defp present?(value), do: is_binary(value) and value != ""

  # --- status line ---

  defp status_line(state) do
    connected = Enum.count(state.nodes, &(&1.status == "connected"))
    dist = if Server.Dist.enabled?(), do: "", else: "distribution off · "
    left = "#{dist}#{connected}/#{length(state.nodes)} connected"

    hints =
      if Map.get(state.settings, :show_hints, true),
        do: Ui.hints(hints(state), state.width - String.length(left) - 4),
        else: []

    hstack([text(left, fg: Theme.color(:muted)), text("   ") | hints])
  end

  defp hints(%{focus: :sessions}),
    do: "j/k session · enter open · r rename · n new · d del · #g jump · tab/esc nodes · ? help"

  defp hints(_state) do
    env = if Config.env_mode?(), do: " · env read-only", else: ""

    "j/k node · enter sessions · n new · c connect · e edit · d del · p presets · l snippets#{env} · , settings · ? help · q quit"
  end

  # --- form view ---

  defp form_title(%{mode: :new}), do: "New node"
  defp form_title(_form), do: "Edit node"

  defp form_lines(form) do
    fields =
      @fields
      |> Enum.with_index()
      |> Enum.flat_map(fn {{key, label, section, placeholder}, index} ->
        focused? = index == form.focus

        section_lines(section) ++
          [field_line(label, form.values[key], placeholder, focused?, form.cursor)]
      end)

    error =
      if form.error, do: [text(""), text("✗ #{form.error}", fg: Theme.color(:error))], else: []

    fields ++
      error ++
      [
        text(""),
        text("Tab/Shift+Tab switch field · Enter save · Esc cancel", fg: Theme.color(:muted))
      ]
  end

  defp section_lines(nil), do: []

  defp section_lines({title, note}) do
    [
      hstack([
        text(title, fg: Theme.color(:title), bold: true),
        text("  #{note}", fg: Theme.color(:muted))
      ])
    ]
  end

  defp field_line(label, value, placeholder, focused?, cursor) do
    label_color = if focused?, do: :title, else: :muted

    input =
      if focused?,
        do: Widget.input(value, cursor: cursor, placeholder: placeholder),
        else: text(value, fg: Theme.color(:text))

    hstack([text("  " <> String.pad_trailing(label, 12), fg: Theme.color(label_color)), input])
  end

  # --- help ---

  defp help_rows do
    [
      {:section, "nodes"},
      {"j/k  ↓/↑", "move the node selection"},
      {"enter  tab  →", "go to the sessions pane"},
      {"n", "new node"},
      {"e", "edit the node"},
      {"c", "connect, or disconnect a connected node"},
      {"d", "delete the node (asks first)"},
      {"Ctrl+D", "delete the node (does not ask)"},
      {"p", "presets"},
      {"l", "snippets"},
      {",", "settings"},
      {"q", "quit (asks first)"},
      {:section, "sessions"},
      {"j/k  ↓/↑", "move the session selection"},
      {"enter", "open the session"},
      {"n", "new session"},
      {"r", "rename the session"},
      {"d", "delete the session (asks first)"},
      {"Ctrl+D", "delete the session (does not ask)"},
      {"<number>g", "go to the session of that number"},
      {"tab  esc", "back to the node list"},
      {"?", "this help"}
    ]
  end
end
