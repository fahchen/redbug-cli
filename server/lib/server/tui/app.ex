defmodule Server.Tui.App do
  @moduledoc """
  The Terra app of the TUI: the node screen. It runs in the controller BEAM
  and calls `Server.Config` directly, not over the WebSocket.

  `init/1` starts a `Server.Tui.Bridge`, which sends config changes to the
  runtime in batches as `{:nodes, nodes, settings}` messages. The layout takes
  its sizes from `{:resize, w, h}`. The node form, the confirm question, and the
  help are full-screen pages. `docs/terra-gaps.md` records each feature of the
  Bun TUI that this app cuts or simplifies.
  """

  use Terra

  alias Server.{Config, Remote}
  alias Server.Tui.{Bridge, Theme}
  alias Terra.Widget

  @list_width 40
  @spinner ~w(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
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
    Bridge.start_link(self(), query_size: Keyword.get(opts, :query_size, false))

    %{
      width: Keyword.get(opts, :width, 80),
      height: Keyword.get(opts, :height, 24),
      nodes: Config.nodes(),
      settings: Config.settings(),
      selected: 0,
      page: :nodes,
      tick: 0,
      ticking: false
    }
    |> schedule_spin()
  end

  @impl Terra.App
  def update(msg, state) do
    case handle(msg, state) do
      {:quit, state} -> {:quit, state}
      state -> schedule_spin(state)
    end
  end

  # --- messages that every page takes ---

  defp handle({:resize, w, h}, state), do: %{state | width: w, height: h}

  defp handle({:nodes, nodes, settings}, state),
    do: clamp(%{state | nodes: nodes, settings: settings})

  defp handle(:spin, state), do: %{state | tick: state.tick + 1, ticking: false}

  # --- pages ---

  defp handle(_key, %{page: :help} = state), do: %{state | page: :nodes}

  defp handle(key, %{page: {:confirm, _question, action}} = state) do
    case key do
      {:char, "y"} -> confirm(action, %{state | page: :nodes})
      {:char, "n"} -> %{state | page: :nodes}
      :esc -> %{state | page: :nodes}
      _ -> state
    end
  end

  defp handle(key, %{page: {:form, form}} = state), do: form_key(key, form, state)
  defp handle(key, %{page: :nodes} = state), do: nodes_key(key, state)

  # --- node list keys ---

  defp nodes_key(key, state) when key in [:down, {:char, "j"}], do: move(state, 1)
  defp nodes_key(key, state) when key in [:up, {:char, "k"}], do: move(state, -1)

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

  defp move(%{nodes: []} = state, _delta), do: state

  defp move(state, delta),
    do: %{state | selected: Integer.mod(state.selected + delta, length(state.nodes))}

  defp clamp(state),
    do: %{state | selected: state.selected |> min(length(state.nodes) - 1) |> max(0)}

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

  # A tick runs only while a node connects.
  defp schedule_spin(%{ticking: false} = state) do
    if Enum.any?(state.nodes, &(&1.status == "connecting")),
      do: {%{state | ticking: true}, [{:tick, @spin_ms, :spin}]},
      else: state
  end

  defp schedule_spin(state), do: state

  # --- views ---

  @impl Terra.App
  def view(%{page: :help} = state), do: page(state, "Help", help_lines())

  def view(%{page: {:confirm, question, _action}} = state) do
    box(
      vstack([
        text(question, fg: Theme.color(:text)),
        text(""),
        text("y = yes · n/Esc = no", fg: Theme.color(:muted))
      ]),
      width: state.width,
      height: state.height,
      align: :center,
      valign: :center
    )
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
          box(detail_view(state),
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

  defp page(state, title, lines) do
    box(vstack(lines),
      title: title,
      width: state.width,
      height: state.height,
      padding: [top: 0, right: 2, bottom: 0, left: 2]
    )
  end

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
      text(fit(name, name_width), [fg: Theme.color(name_color)] ++ bg),
      text(env, [fg: Theme.color(:muted)] ++ bg),
      text(" #{count} ", [fg: Theme.color(:muted)] ++ bg)
    ])
  end

  defp glyph("connected", _tick), do: {"●", :success}
  defp glyph("connecting", tick), do: {Enum.at(@spinner, rem(tick, length(@spinner))), :warning}
  defp glyph("error", _tick), do: {"✖", :error}
  defp glyph(_status, _tick), do: {" ", :muted}

  # Pad or cut `string` to `width` cells.
  defp fit(string, width) do
    cells = Terra.Width.string(string)

    if cells > width,
      do: cut(String.graphemes(string), width - 1, []) <> "…",
      else: string <> String.duplicate(" ", width - cells)
  end

  # The graphemes that fit in `room` cells, padded to `room` cells (a wide
  # grapheme that does not fit leaves one blank cell).
  defp cut([g | rest], room, acc) do
    w = Terra.Width.grapheme(g)
    if w <= room, do: cut(rest, room - w, [g | acc]), else: cut([], room, acc)
  end

  defp cut([], room, acc),
    do: IO.iodata_to_binary([Enum.reverse(acc), String.duplicate(" ", room)])

  # --- node detail ---

  defp detail_title(state) do
    case current(state) do
      nil -> "—"
      node -> node.name
    end
  end

  defp detail_view(state) do
    case current(state) do
      nil ->
        text("Select a node", fg: Theme.color(:muted))

      node ->
        vstack(chips(node) ++ [text(""), sessions_line(node)])
    end
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

  defp chip(label, value, tone \\ :text) do
    hstack([
      text(" #{label} ", fg: Theme.color(:muted), bg: Theme.color(:element)),
      text(" #{value} ", fg: Theme.color(tone), bg: Theme.color(:panel))
    ])
  end

  defp sessions_line(node) do
    text("#{length(node.sessions)} sessions", fg: Theme.color(:muted))
  end

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
        do: hint_segments(hints(), state.width - String.length(left) - 4),
        else: []

    hstack([text(left, fg: Theme.color(:muted)), text("   ") | hints])
  end

  defp hints do
    env = if Config.env_mode?(), do: " · env read-only", else: ""
    "j/k node · n new · c connect · e edit · d del#{env} · ? help · q quit"
  end

  # Cut the hints to `room` cells with a final `…`; the key of each segment
  # (its first word) takes the title colour.
  defp hint_segments(hints, room) do
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

  defp help_lines do
    [
      {"j/k  ↓/↑", "move the node selection"},
      {"n", "new node"},
      {"e", "edit the node"},
      {"c", "connect, or disconnect a connected node"},
      {"d", "delete the node (asks first)"},
      {"Ctrl+D", "delete the node (does not ask)"},
      {"?", "this help"},
      {"q", "quit (asks first)"}
    ]
    |> Enum.map(fn {key, action} ->
      hstack([
        text(String.pad_trailing(key, 12), fg: Theme.color(:title)),
        text(action, fg: Theme.color(:text))
      ])
    end)
    |> Kernel.++([text(""), text("press any key to close", fg: Theme.color(:muted))])
  end
end
