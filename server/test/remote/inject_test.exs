defmodule Server.Remote.InjectTest do
  @moduledoc """
  End-to-end test of `Server.Remote.Inject` against target nodes of each
  supported OTP version, while the controller runs the OTP of `mise.toml`.

  The test starts one peer node per version with the `erl` and the Elixir
  `ebin` that `mise where` gives for the pins in `mise.toml` (run `mise install`
  first). It needs a distributed VM:

      elixir --name rbe2e@127.0.0.1 --cookie rbtest -S mix test test/remote/inject_test.exs
  """
  use ExUnit.Case, async: false

  alias Server.{Config, Remote, Trace}

  # {OTP major, erlang pin, elixir pin}; keep in step with [tools] in mise.toml.
  @targets [
    {"27", "erlang@27.2.4", "elixir@1.18.4-otp-27"},
    {"28", "erlang@28.5.0.2", "elixir@1.19.5-otp-28"},
    {"29", "erlang@29.1.1", "elixir@1.20.4-otp-29"}
  ]

  setup_all do
    unless Node.alive?(), do: raise("start the test VM with --name (see @moduledoc)")

    nodes =
      Map.new(@targets, fn {otp, erlang, elixir} ->
        {peer, node} = start_target(otp, erlang, elixir)
        on_exit(fn -> :peer.stop(peer) end)
        {otp, node}
      end)

    plain_nodes =
      Map.new(@targets, fn {otp, erlang, _elixir} ->
        {peer, node} = start_target(otp, erlang, nil)
        on_exit(fn -> :peer.stop(peer) end)
        {otp, node}
      end)

    %{nodes: nodes, plain_nodes: plain_nodes}
  end

  for {otp, _erlang, _elixir} <- @targets do
    describe "OTP #{otp} target" do
      setup %{nodes: nodes} do
        node = Map.fetch!(nodes, unquote(otp))
        cookie = Atom.to_string(Node.get_cookie())
        {:ok, node_id} = Config.add_node(%{name: Atom.to_string(node), cookie: cookie})

        {:ok, session_id} =
          Config.add_session(node_id, %{
            name: "inject-#{unquote(otp)}",
            traces: [%{id: Config.gen_id(), text: "lists:seq/2", enabled: true}],
            limits: %{keep: 500, time: 30, msgs: 1000}
          })

        on_exit(fn ->
          Remote.terminate(session_id)
          Trace.terminate(session_id)
        end)

        %{node: node, node_id: node_id, session_id: session_id}
      end

      test "runs console code", %{node: node, node_id: nid, session_id: sid} do
        assert :rpc.call(node, :erlang, :system_info, [:otp_release]) == ~c"#{unquote(otp)}"

        {:ok, _} = Remote.run(nid, sid, "Enum.sum([1, 2, 3])", "elixir")
        assert %{status: "ok", result: "6"} = await_final(sid, "elixir")

        {:ok, _} = Remote.run(nid, sid, "lists:seq(1, 3).", "erlang")
        assert %{status: "ok", result: "[1,2,3]"} = await_final(sid, "erlang")

        # The second run finds the current worker and does not load it again.
        refute :rpc.call(node, :erlang, :check_old_code, [Server.Remote.Worker])
      end

      test "gives the Erlang text of Erlang code", %{node_id: nid, session_id: sid} do
        assert_erlang_cases(nid, sid)
      end

      test "runs a redbug trace", %{node: node, node_id: nid, session_id: sid} do
        assert :ok = Trace.start(nid, sid)
        for _ <- 1..5, do: :rpc.call(node, :lists, :seq, [1, 5])
        assert Enum.any?(await_events(sid), &(&1.kind == "call"))
        assert :ok = Trace.stop(sid)
      end
    end

    describe "OTP #{otp} target without Elixir" do
      setup %{plain_nodes: nodes} do
        node = Map.fetch!(nodes, unquote(otp))
        cookie = Atom.to_string(Node.get_cookie())
        {:ok, node_id} = Config.add_node(%{name: Atom.to_string(node), cookie: cookie})
        {:ok, session_id} = Config.add_session(node_id, %{name: "plain-#{unquote(otp)}"})
        on_exit(fn -> Remote.terminate(session_id) end)
        %{node: node, node_id: node_id, session_id: session_id}
      end

      test "runs console code", %{node: node, node_id: nid, session_id: sid} do
        assert :rpc.call(node, :erlang, :system_info, [:otp_release]) == ~c"#{unquote(otp)}"
        assert :rpc.call(node, :code, :which, [Code]) == :non_existing

        {:ok, _} = Remote.run(nid, sid, ~s|io:format("hi~n"), lists:seq(1, 3).|, "seq")
        assert %{status: "ok", result: "[1,2,3]", output: "hi\n"} = await_final(sid, "seq")

        # The same text as on a target with Elixir (see the test above).
        assert_erlang_cases(nid, sid)

        # Elixir code is not Erlang: the console gives the Erlang parse error.
        {:ok, _} = Remote.run(nid, sid, "Enum.sum([1, 2, 3])", "elixir")

        assert %{status: "error", result: "1: syntax error before: '.'"} =
                 await_final(sid, "elixir")
      end
    end
  end

  # Erlang code with a final dot, and its status and result on each target. The
  # Elixir formatter and evaluator would read the last three cases as Elixir.
  @erlang_cases [
    {"lists:nth(0, [a]).", "error", "{error,function_clause}"},
    {"lists:seq(1,.", "error", "1: syntax error before: '.'"},
    {"{a, b}.", "ok", "{a,b}"},
    {"[X || X <- [1, 2]].", "ok", "[1,2]"},
    {"\#{a => 1}.", "ok", "\#{a => 1}"}
  ]

  defp assert_erlang_cases(nid, sid) do
    for {code, status, result} <- @erlang_cases do
      {:ok, _} = Remote.run(nid, sid, code, code)
      assert %{status: ^status, result: ^result} = await_final(sid, code)
    end
  end

  # The peer runs the `erl` of `erlang`. With `elixir`, the Elixir of `elixir` is
  # in its code path and started, as `iex --name` would; with nil, the peer is a
  # plain Erlang node.
  defp start_target(otp, erlang, elixir) do
    erl = Path.join([mise_where(erlang), "bin", "erl"])
    [_name, host] = node() |> Atom.to_string() |> String.split("@")
    kind = if elixir, do: "inject", else: "plain"

    {:ok, peer, node} =
      :peer.start(%{
        name: :"#{kind}#{otp}_#{System.unique_integer([:positive])}",
        host: String.to_charlist(host),
        exec: String.to_charlist(erl),
        args: [~c"-setcookie", Atom.to_charlist(Node.get_cookie()) | elixir_args(elixir)]
      })

    if elixir, do: {:ok, _} = :erpc.call(node, :application, :ensure_all_started, [:elixir])
    {peer, node}
  end

  defp elixir_args(nil), do: []

  defp elixir_args(elixir),
    do: [~c"-pa", String.to_charlist(Path.join([mise_where(elixir), "lib", "elixir", "ebin"]))]

  defp mise_where(tool) do
    case System.cmd("mise", ["where", tool], stderr_to_stdout: true) do
      {path, 0} -> String.trim(path)
      {out, _} -> raise "#{tool} is not installed (run `mise install`): #{out}"
    end
  end

  defp await_final(sid, name) do
    poll(fn ->
      entry = Enum.find(Remote.snapshot(sid).history, &(&1.name == name))
      if entry && entry.status != "running", do: entry
    end)
  end

  defp await_events(sid) do
    poll(fn ->
      events = Trace.snapshot(sid).events
      if events != [], do: events
    end)
  end

  defp poll(fun, tries \\ 50) do
    case fun.() do
      nil when tries > 0 -> Process.sleep(100) && poll(fun, tries - 1)
      nil -> flunk("condition never held")
      value -> value
    end
  end
end
