defmodule Server.RemoteConsoleTest do
  @moduledoc """
  End-to-end test of the `Server.Remote` console layer against a live
  target node. Runs code blocks on `target@127.0.0.1` (cookie `rbtest`) over
  distribution. Run with:

      elixir --name rbe2e@127.0.0.1 --cookie rbtest -S mix test
  """
  use ExUnit.Case, async: false

  alias Server.{Config, Remote}

  @target "target@127.0.0.1"
  @cookie "rbtest"

  setup do
    {:ok, node_id} = Config.add_node(%{name: @target, cookie: @cookie})

    {:ok, session_id} =
      Config.add_session(node_id, %{
        name: "console-e2e",
        traces: [],
        limits: %{keep: 500, time: 30, msgs: 1000}
      })

    on_exit(fn -> Remote.terminate(session_id) end)
    %{node_id: node_id, session_id: session_id}
  end

  test "run / stop / clear through Server.Remote", %{node_id: nid, session_id: sid} do
    # Elixir block evaluates and finalizes "ok" with the result inspected.
    Remote.run(nid, sid, "1 + 1", "math")
    math = await_final(sid, "math")
    assert math.status == "ok"
    assert math.result =~ "2"
    assert math.duration_ms >= 0

    # Erlang falls through the Elixir path and evaluates too (auto-detected).
    Remote.run(nid, sid, "lists:seq(1,3).", "erl")
    erl = await_final(sid, "erl")
    assert erl.status == "ok"
    assert erl.result =~ "[1, 2, 3]" or erl.result =~ "[1,2,3]"

    # Captured stdout rides along on the entry.
    Remote.run(nid, sid, ~s|IO.puts("hi there")|, "io")
    io = await_final(sid, "io")
    assert io.status == "ok"
    assert io.output =~ "hi there"

    # A long eval is force-stoppable mid-run -> status "stopped".
    Remote.run(nid, sid, "Process.sleep(60_000)", "sleep")
    running = await_running(sid, "sleep")
    Remote.stop(sid, running.id)
    stopped = await_final(sid, "sleep")
    assert stopped.status == "stopped"

    assert length(Remote.snapshot(sid).history) == 4

    # Clear empties the server-held history.
    Remote.clear(sid)
    Process.sleep(200)
    assert Remote.snapshot(sid).history == []
  end

  # Polls snapshot until the named entry leaves "running".
  defp await_final(sid, name), do: poll(sid, name, fn e -> e.status != "running" end)

  # Polls snapshot until the named entry exists and is "running".
  defp await_running(sid, name), do: poll(sid, name, fn e -> e.status == "running" end)

  defp poll(sid, name, done?, tries \\ 50) do
    entry = Enum.find(Remote.snapshot(sid).history, &(&1.name == name))

    cond do
      entry && done?.(entry) -> entry
      tries == 0 -> flunk("entry #{inspect(name)} never satisfied predicate")
      true -> Process.sleep(100) && poll(sid, name, done?, tries - 1)
    end
  end
end
