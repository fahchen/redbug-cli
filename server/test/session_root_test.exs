defmodule Server.Stores.SessionRootTest do
  @moduledoc """
  End-to-end test of the SessionRoot store against a live target node.

  Requires a distributed VM and a reachable `target@127.0.0.1` node (cookie
  `rbtest`) that periodically calls `:lists.seq/2`. Run with:

      elixir --name rbe2e@127.0.0.1 --cookie rbtest -S mix test
  """
  use ExUnit.Case, async: false

  alias Musubi.Testing
  alias Server.{Config, Trace}

  @target "target@127.0.0.1"
  @cookie "rbtest"

  setup do
    {:ok, node_id} = Config.add_node(%{name: @target, cookie: @cookie})

    {:ok, session_id} =
      Config.add_session(node_id, %{
        name: "e2e",
        traces: [%{id: Config.gen_id(), text: "lists:seq/2", enabled: true}],
        limits: %{keep: 500, time: 30, msgs: 1000}
      })

    %{node_id: node_id, session_id: session_id}
  end

  # Stream contents are client-owned: the server emits stream ops as push
  # patches and never materializes the list in render/1. So event-content
  # assertions read the materialized Runner buffer (Trace.snapshot/1), which
  # the store mirrors over the same PubSub topic; render/1 covers plain fields.
  test "full trace lifecycle over the store layer", %{node_id: nid, session_id: sid} do
    s = Testing.mount(Server.Stores.SessionRoot, %{"node_id" => nid, "session_id" => sid})

    assert Testing.render(s).status == "stopped"

    Testing.dispatch_command(s, :startTrace, %{})
    Process.sleep(1500)

    assert Testing.render(s).status == "running"
    assert length(Trace.snapshot(sid).events) > 0

    # Editing RTP while running drifts the signature -> dirty marker.
    Testing.dispatch_command(s, :addTrace, %{text: "lists:reverse/1"})
    Process.sleep(200)
    assert Testing.render(s).dirty == true

    # Applying recompiles and inserts a restart separator; dirty clears.
    Testing.dispatch_command(s, :applyRestart, %{})
    Process.sleep(500)
    assert Testing.render(s).dirty == false
    assert Enum.any?(Trace.snapshot(sid).events, &(&1.kind == "restart"))

    # Stop returns to stopped but retains the buffer (stop != clear).
    Testing.dispatch_command(s, :stopTrace, %{})
    Process.sleep(200)
    assert Testing.render(s).status == "stopped"
    assert length(Trace.snapshot(sid).events) > 0

    # Clear empties the buffer.
    Testing.dispatch_command(s, :clearEvents, %{})
    Process.sleep(200)
    assert Trace.snapshot(sid).events == []
  end
end
