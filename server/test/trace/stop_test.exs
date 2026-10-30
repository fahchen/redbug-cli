defmodule Server.TraceStopTest do
  @moduledoc """
  The stop paths of a trace against a live target node: the msgs limit, the
  time limit, and a stop by the user. redbug's end text goes to the StringIO
  group leader of the runner, not to the terminal, and the status message
  gives the reason.

  Requires a distributed VM and a reachable `target@127.0.0.1` node (cookie
  `rbtest`). Run with:

      elixir --name rbe2e@127.0.0.1 --cookie rbtest -S mix test
  """
  use ExUnit.Case, async: false

  alias Server.{Config, Trace}

  @target "target@127.0.0.1"
  @cookie "rbtest"

  setup do
    driver = drive_target_calls()
    on_exit(fn -> Process.exit(driver, :kill) end)
    :ok
  end

  test "the msgs limit ends the trace with ended msgs" do
    {nid, sid} = session(%{keep: 500, time: 30, msgs: 3})
    :ok = Trace.subscribe(sid)
    assert :ok = Trace.start(nid, sid)

    assert_receive {:trace_status, %{status: "stopped", ended: "msgs"}}, 10_000
    refute_receive {:trace_error, _}, 200
    assert end_text(sid) == ""
  end

  test "the time limit ends the trace with ended time" do
    {nid, sid} = session(%{keep: 500, time: 1, msgs: 1_000_000})
    :ok = Trace.subscribe(sid)
    assert :ok = Trace.start(nid, sid)

    assert_receive {:trace_status, %{status: "stopped", ended: "time"}}, 10_000
    refute_receive {:trace_error, _}, 200
    assert end_text(sid) == ""
  end

  test "a stop by the user gives no error, and the end text stays off the terminal" do
    {nid, sid} = session(%{keep: 500, time: 30, msgs: 1000})
    :ok = Trace.subscribe(sid)
    assert :ok = Trace.start(nid, sid)
    assert_receive {:trace_status, %{status: "running"}}, 5_000

    :ok = Trace.stop(sid)
    assert_receive {:trace_status, %{status: "stopped", ended: nil}}, 5_000

    # redbug writes the text after the stop call returns.
    assert poll(fn -> end_text(sid) =~ "redbug done, stopped - " end)
    refute_receive {:trace_error, _}, 200
  end

  test "end_reason/1 reads the last end text of redbug" do
    assert Server.Trace.Runner.end_reason("") == nil

    hint = "you might want to set the max_queue option (see redbug:help/0)\n"
    text = "redbug done, stopped - 1\n" <> hint <> "redbug done, {msg_queue,5001} - 7\n"
    assert Server.Trace.Runner.end_reason(text) == "{msg_queue,5001}"

    # ~p breaks a long reason over lines.
    long =
      :io_lib.format("redbug done, ~p - ~p~n", [
        {{:badmatch, {:error, :enoent}},
         [{:redbug_targ, :init, 1, [file: ~c"redbug_targ.erl", line: 97]}]},
        3
      ])
      |> IO.iodata_to_binary()

    assert long =~ "\n"

    assert Server.Trace.Runner.end_reason(long) =~
             ~r/^\{\{badmatch,\{error,enoent\}\}, \[\{redbug_targ,init,1/

    # a printer crash ends with a term, not a count
    assert Server.Trace.Runner.end_reason("redbug done, printer_crash - {oops}\n") == nil
  end

  defp session(limits) do
    {:ok, nid} = Config.add_node(%{name: @target, cookie: @cookie})

    {:ok, sid} =
      Config.add_session(nid, %{
        name: "stop",
        traces: [%{id: Config.gen_id(), text: "lists:seq/2", enabled: true}],
        limits: limits
      })

    on_exit(fn -> Trace.terminate(sid) end)
    {nid, sid}
  end

  defp poll(check, tries \\ 50) do
    cond do
      check.() -> true
      tries == 0 -> false
      true -> Process.sleep(100) && poll(check, tries - 1)
    end
  end

  # The text that is in the StringIO group leader of the runner now.
  defp end_text(sid) do
    [{runner, _}] = Registry.lookup(Server.Trace.Registry, sid)
    {:group_leader, io} = Process.info(runner, :group_leader)
    {_input, output} = StringIO.contents(io)
    output
  end

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
