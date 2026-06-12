defmodule Server.Stores.ConsoleRootTest do
  @moduledoc """
  End-to-end test of the ConsoleRoot store + Server.Remote layer against a live
  target node. Runs code blocks on `target@127.0.0.1` (cookie `rbtest`) over
  distribution. Run with:

      elixir --name rbe2e@127.0.0.1 --cookie rbtest -S mix test
  """
  use ExUnit.Case, async: false

  alias Musubi.Testing
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

  # History is client-owned (server emits stream ops, never materializes the
  # list in render/1), so content assertions read Remote.snapshot/1 — the same
  # source the store mirrors over PubSub. render/1 covers plain fields.
  test "run / rerun / stop / clear over the store layer", %{node_id: nid, session_id: sid} do
    s = Testing.mount(Server.Stores.ConsoleRoot, %{"node_id" => nid, "session_id" => sid})

    r = Testing.render(s)
    assert r.node_id == nid
    assert r.session_id == sid
    assert is_list(r.snippets)

    # Elixir block evaluates and finalizes "ok" with the result inspected.
    Testing.dispatch_command(s, :run, %{code: "1 + 1", name: "math"})
    math = await_final(sid, "math")
    assert math.status == "ok"
    assert math.result =~ "2"
    assert math.duration_ms >= 0

    # Erlang falls through the Elixir path and evaluates too (auto-detected).
    Testing.dispatch_command(s, :run, %{code: "lists:seq(1,3).", name: "erl"})
    erl = await_final(sid, "erl")
    assert erl.status == "ok"
    assert erl.result =~ "[1, 2, 3]" or erl.result =~ "[1,2,3]"

    # Captured stdout rides along on the entry.
    Testing.dispatch_command(s, :run, %{code: ~s|IO.puts("hi there")|, name: "io"})
    io = await_final(sid, "io")
    assert io.status == "ok"
    assert io.output =~ "hi there"

    # A long eval is force-stoppable mid-run -> status "stopped".
    Testing.dispatch_command(s, :run, %{code: "Process.sleep(60_000)", name: "sleep"})
    running = await_running(sid, "sleep")
    Testing.dispatch_command(s, :stopExecution, %{id: running.id})
    stopped = await_final(sid, "sleep")
    assert stopped.status == "stopped"

    assert length(Remote.snapshot(sid).history) == 4

    # Clear empties the server-held history.
    Testing.dispatch_command(s, :clearHistory, %{})
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
