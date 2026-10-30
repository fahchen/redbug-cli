defmodule Server.Tui.SessionTest do
  @moduledoc """
  The sessions pane and the session screen of the Terra TUI. The last test
  traces `target@127.0.0.1` (cookie `rbtest`), as `session_root_test.exs` does:

      elixir --name rbe2e@127.0.0.1 --cookie rbtest -S mix test
  """
  # The app reads and writes the shared Server.Config, as the store tests do.
  use ExUnit.Case, async: false

  alias Server.Config
  alias Server.Schema.TraceEvent

  setup do
    for n <- Config.nodes(), do: Config.delete_node(n.id)
    for p <- Config.presets(), do: Config.delete_preset(p.id)

    machine =
      Terra.Test.start(Server.Tui.App, app: [width: 120, height: 30], width: 120, height: 30)

    on_exit(fn -> if Process.alive?(machine), do: Terra.Test.stop(machine) end)
    %{machine: machine}
  end

  defp eventually(fun, tries \\ 100) do
    if fun.() do
      :ok
    else
      if tries == 0, do: flunk("condition never held")
      Process.sleep(20)
      eventually(fun, tries - 1)
    end
  end

  defp screen(machine), do: Terra.Test.render(machine)
  defp keys(machine, keys), do: Terra.Test.send_keys(machine, keys)

  # A node that does not exist, so its sessions stay offline.
  defp add_node(machine, name \\ "ghost@127.0.0.1") do
    {:ok, id} = Config.add_node(%{name: name, cookie: "rbtest"})
    eventually(fn -> screen(machine) =~ name end)
    id
  end

  defp add_session(machine, node_id, name, attrs \\ %{}) do
    {:ok, id} = Config.add_session(node_id, Map.put(attrs, :name, name))
    eventually(fn -> screen(machine) =~ name end)
    id
  end

  defp event(id, kind, attrs \\ %{}) do
    struct(
      %TraceEvent{
        id: Integer.to_string(id),
        kind: kind,
        pid: "<0.#{100 + id}.0>",
        name: "",
        mfa: "lists:seq/2",
        info: "(1, #{id})",
        pair: "",
        depth: 0,
        ts: "12:00:00.#{String.pad_leading(Integer.to_string(id), 3, "0")}"
      },
      attrs
    )
  end

  # The bridge casts the trace messages to the runtime in the same way.
  defp cast(machine, message), do: GenServer.cast(machine, {:event, message})

  defp open(machine, node_id, name) do
    add_session(machine, node_id, name)
    keys(machine, [:enter, :enter])
    eventually(fn -> screen(machine) =~ "▸ #{name}" end)
    Terra.Test.state(machine).session.id
  end

  test "enter focuses the sessions pane, and n names a blank session and opens it",
       %{machine: m} do
    node_id = add_node(m)
    keys(m, :enter)
    assert screen(m) =~ "No sessions · n to add"
    assert screen(m) =~ "j/k session"

    keys(m, ["n", "probe", :enter])
    assert screen(m) =~ ~s(New session "probe" · start from)
    assert screen(m) =~ "blank (no trace patterns)"

    keys(m, :enter)
    eventually(fn -> screen(m) =~ "ghost@127.0.0.1 ▸ probe" end)
    [session] = Config.fetch_node(node_id).sessions
    assert session.traces == []
    assert session.limits == Config.settings().default_limits

    # the node does not answer, and the trace is not running: esc leaves at once
    keys(m, :esc)
    assert screen(m) =~ "1 ·  probe"
  end

  test "a preset gives the new session its traces with new ids", %{machine: m} do
    node_id = add_node(m)

    {:ok, _} =
      Config.add_preset(%{
        name: "seqs",
        traces: [%{id: "p1", text: "lists:seq/2", enabled: true}],
        limits: %{keep: 7, time: 8, msgs: 9}
      })

    keys(m, [:tab, "n", "from preset", :enter])
    assert screen(m) =~ "seqs"
    keys(m, [:down, :enter])

    eventually(fn -> Config.fetch_node(node_id).sessions != [] end)
    [session] = Config.fetch_node(node_id).sessions
    assert [%{text: "lists:seq/2", enabled: true, id: id}] = session.traces
    assert id != "p1"
    assert session.limits == %{keep: 7, time: 8, msgs: 9}
  end

  test "r renames, d asks before it deletes, Ctrl+D deletes, and #g jumps", %{machine: m} do
    node_id = add_node(m)
    add_session(m, node_id, "one")
    add_session(m, node_id, "two")
    add_session(m, node_id, "three")

    keys(m, [:enter, "3", "g"])
    assert Terra.Test.state(m).sess_sel == 2

    keys(m, ["r"] ++ List.duplicate(:backspace, 5) ++ ["drei", :enter])
    eventually(fn -> screen(m) =~ "3 ·  drei" end)

    keys(m, "d")
    assert screen(m) =~ ~s(Delete session "drei"?)
    keys(m, "n")
    assert screen(m) =~ "drei"
    keys(m, ["d", "y"])
    eventually(fn -> length(Config.fetch_node(node_id).sessions) == 2 end)

    keys(m, [{:ctrl, :d}])
    eventually(fn -> Enum.map(Config.fetch_node(node_id).sessions, & &1.name) == ["one"] end)

    keys(m, :esc)
    assert Terra.Test.state(m).focus == :nodes
  end

  test "the events show, fold, group, filter, sort, and delete", %{machine: m} do
    node_id = add_node(m)
    sid = open(m, node_id, "events")

    cast(
      m,
      {:trace_events, sid,
       [
         event(3, "send", %{pid: "<0.9.0>", mfa: "gen:call/3", info: "hello"}),
         event(2, "retn", %{pair: "1", info: "[1, 2]"}),
         event(1, "call", %{pair: "1", info: "(1, 2)"})
       ]}
    )

    eventually(fn -> screen(m) =~ "hello" end)
    assert screen(m) =~ "#1"
    assert screen(m) =~ "Sort:ts↓ · Filter:- · Group:none"

    keys(m, "f")
    assert screen(m) =~ "(1, 2) → [1, 2]"
    assert screen(m) =~ "Fold"

    keys(m, "g")
    assert screen(m) =~ "<0.9.0> · 1"

    keys(m, ["g", "g", "g", "/", "hello", :enter])
    assert screen(m) =~ "Filter:all/hello"
    refute screen(m) =~ "(1, 2)"
    keys(m, ["/"] ++ List.duplicate(:backspace, 5) ++ [:enter])
    assert screen(m) =~ "Filter:-"

    keys(m, ["o", :down, :enter])
    assert screen(m) =~ "Sort:ts↑"

    # the first row of ts↑ with fold is the call; d asks, y deletes it
    keys(m, ["j", "d"])
    assert screen(m) =~ "Delete this event?"
    keys(m, "y")
    refute screen(m) =~ "(1, 2)"
    assert length(Terra.Test.state(m).session.events) == 2
  end

  test "the detail page shows the term and moves between events", %{machine: m} do
    node_id = add_node(m)
    sid = open(m, node_id, "detail")

    cast(
      m,
      {:trace_events, sid,
       [
         event(2, "call", %{info: ~s|(%{a: 1, b: "x"})\ncp = Foo.bar/1|}),
         event(1, "send", %{info: "ping"})
       ]}
    )

    eventually(fn -> screen(m) =~ "ping" end)
    keys(m, :enter)
    assert screen(m) =~ "Kind  → call"
    assert screen(m) =~ "args"
    assert screen(m) =~ ~s|%{a: 1, b: "x"}|
    assert screen(m) =~ "stack"
    assert screen(m) =~ "1. cp = Foo.bar/1"

    # Ctrl+N goes to the next event
    keys(m, {:ctrl, :n})
    assert screen(m) =~ "Kind  ↑ send"
    assert screen(m) =~ "payload"

    keys(m, :esc)
    assert screen(m) =~ "Sort:ts↓"
    # the detail keeps the highlight of each opened event
    assert map_size(Terra.Test.state(m).session.highlight) == 2
  end

  test "the snapshot and a late event with the same id give one row", %{machine: m} do
    node_id = add_node(m)
    sid = open(m, node_id, "dedupe")

    cast(
      m,
      {:trace_snapshot, sid, %{events: [event(1, "send")], status: "stopped", applied_sig: nil}}
    )

    cast(m, {:trace_events, sid, [event(2, "send"), event(1, "send")]})
    cast(m, {:trace_events, "another", [event(3, "send")]})
    eventually(fn -> screen(m) =~ "(1, 2)" end)
    assert Enum.map(Terra.Test.state(m).session.events, & &1.id) == ["2", "1"]
  end

  test "the status line stays on the last row, below the flash and the border", %{machine: m} do
    node_id = add_node(m)
    sid = open(m, node_id, "layout")
    Terra.Test.resize(m, 80, 24)
    events = for i <- 40..1//-1, do: event(i, "send")
    cast(m, {:trace_events, sid, events})
    cast(m, {:trace_error, sid, %Server.Schema.AppError{message: "boom", detail: "more"}})
    eventually(fn -> screen(m) =~ "✗ boom · e detail" end)

    lines = m |> screen() |> String.split("\n")
    assert length(lines) == 24
    assert List.last(lines) =~ "j/k move"
    assert Enum.at(lines, -2) =~ "✗ boom"
    assert Enum.at(lines, -3) =~ "└"
    # the newest event is on the first row of the list
    assert Enum.at(lines, 3) =~ "12:00:00.040"

    keys(m, "e")
    assert screen(m) =~ "more"
  end

  test "t edits the trace patterns, and l edits the limits", %{machine: m} do
    node_id = add_node(m)
    sid = open(m, node_id, "editor")
    patterns = fn -> Enum.find(Config.fetch_node(node_id).sessions, &(&1.id == sid)).traces end

    keys(m, "t")
    assert screen(m) =~ "no trace patterns · n adds one"

    keys(m, ["n", "lists:seq/2", :enter])
    eventually(fn -> screen(m) =~ "[x] lists:seq/2" end)

    keys(m, " ")
    eventually(fn -> screen(m) =~ "[ ] lists:seq/2" end)

    keys(m, ["e", " -> return", :enter])
    eventually(fn -> match?([%{text: "lists:seq/2 -> return"}], patterns.()) end)

    keys(m, ["l"] ++ List.duplicate(:backspace, 20) ++ ["10 20 30", :enter])

    eventually(fn ->
      Enum.find(Config.fetch_node(node_id).sessions, &(&1.id == sid)).limits ==
        %{keep: 10, time: 20, msgs: 30}
    end)

    keys(m, ["l"] ++ List.duplicate(:backspace, 20) ++ ["x", :enter])
    assert screen(m) =~ "Limits must be three numbers"

    keys(m, ["d", "y"])
    eventually(fn -> patterns.() == [] end)

    keys(m, :esc)
    assert screen(m) =~ "No events yet · space to start"
  end

  test "the status chip shows the node state", %{machine: m} do
    node_id = add_node(m)
    open(m, node_id, "chip")

    # the node does not exist: the connect gives up
    eventually(fn -> screen(m) =~ "can't reach node" end, 500)
    assert screen(m) =~ "space retry"
    keys(m, "?")
    assert screen(m) =~ "Ctrl+N/P"
  end

  test "a session traces the target node and shows the events", %{machine: m} do
    node_id = add_node(m, "target@127.0.0.1")

    add_session(m, node_id, "live", %{
      traces: [%{id: Config.gen_id(), text: "lists:seq/2", enabled: true}],
      limits: %{keep: 50, time: 30, msgs: 1000}
    })

    keys(m, [:enter, :enter])
    eventually(fn -> screen(m) =~ "◇ idle" end, 500)

    keys(m, " ")
    driver = drive_target_calls()
    eventually(fn -> screen(m) =~ "● " and screen(m) =~ ":lists.seq/2" end, 500)
    assert screen(m) =~ "x stop"

    keys(m, :enter)
    assert screen(m) =~ "Kind  → call"
    keys(m, :esc)

    keys(m, :esc)
    assert screen(m) =~ "Stop trace and leave?"
    keys(m, "y")
    assert screen(m) =~ "1 ·  live"
    Process.exit(driver, :kill)
  end

  defp drive_target_calls do
    spawn(fn ->
      Stream.repeatedly(fn ->
        :rpc.call(:"target@127.0.0.1", :lists, :seq, [1, 5])
        Process.sleep(50)
      end)
      |> Stream.run()
    end)
  end
end
