defmodule Server.TraceLifecycleTest do
  @moduledoc """
  End-to-end test of the `Server.Trace` layer against a live target node.

  Requires a distributed VM and a reachable `target@127.0.0.1` node (cookie
  `rbtest`) that periodically calls `:lists.seq/2`. Run with:

      elixir --name rbe2e@127.0.0.1 --cookie rbtest -S mix test
  """
  use ExUnit.Case, async: false

  alias Server.{Config, Trace}
  alias Server.Trace.Signature

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

  test "full trace lifecycle through Server.Trace", %{node_id: nid, session_id: sid} do
    assert Trace.snapshot(sid).status == "stopped"

    assert :ok = Trace.start(nid, sid)

    # Drive the trace ourselves instead of waiting on the target's own loop:
    # repeated rpc calls execute lists:seq/2 on the target, which redbug traces.
    driver = drive_target_calls()
    Process.sleep(1500)

    assert Trace.snapshot(sid).status == "running"
    assert length(Trace.snapshot(sid).events) > 0

    # Editing RTP while running drifts the signature -> dirty marker.
    add_trace(nid, sid, "lists:reverse/1")
    assert dirty?(nid, sid)

    # Applying recompiles and inserts a restart separator; dirty clears.
    Trace.apply_restart(sid)
    Process.sleep(500)
    refute dirty?(nid, sid)
    assert Enum.any?(Trace.snapshot(sid).events, &(&1.kind == "restart"))

    # Stop returns to stopped but retains the buffer (stop != clear).
    Trace.stop(sid)
    Process.sleep(200)
    assert Trace.snapshot(sid).status == "stopped"
    assert length(Trace.snapshot(sid).events) > 0

    # Clear empties the buffer.
    Trace.clear(sid)
    Process.sleep(200)
    assert Trace.snapshot(sid).events == []

    Process.exit(driver, :kill)
  end

  defp session(nid, sid) do
    Config.nodes()
    |> Enum.find(&(&1.id == nid))
    |> Map.fetch!(:sessions)
    |> Enum.find(&(&1.id == sid))
  end

  defp add_trace(nid, sid, text) do
    traces = session(nid, sid).traces ++ [%{id: Config.gen_id(), text: text, enabled: true}]
    Config.update_session(nid, sid, %{traces: traces})
  end

  # The marker of the session screen: the edited config differs from the
  # signature that the runner applied.
  defp dirty?(nid, sid) do
    s = session(nid, sid)
    Signature.compute(s.traces, s.limits) != Trace.snapshot(sid).applied_sig
  end

  # Spawns a loop that rpc-invokes :lists.seq/2 on the target so the trace has
  # deterministic traffic to capture, independent of the target's own workload.
  defp drive_target_calls do
    spawn(fn ->
      Stream.repeatedly(fn ->
        :rpc.call(String.to_atom(@target), :lists, :seq, [1, 5])
        Process.sleep(50)
      end)
      |> Stream.run()
    end)
  end
end
