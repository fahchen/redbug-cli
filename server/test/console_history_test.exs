defmodule Server.Remote.ConsoleHistoryTest do
  @moduledoc """
  Console history survives a restart: the runner loads its session's JSON file
  on init and rewrites it on delete. No live target node needed.
  """
  use ExUnit.Case, async: false

  alias Server.Remote
  alias Server.Remote.Console

  setup do
    {:ok, node_id} = Server.Config.add_node(%{name: "target@127.0.0.1", cookie: "rbtest"})
    session_id = Server.Config.gen_id()
    file = Console.path(session_id)
    on_exit(fn -> Remote.terminate(session_id); File.rm(file) end)
    %{node_id: node_id, session_id: session_id, path: file}
  end

  test "restores persisted execs and rewrites the file on delete", ctx do
    File.mkdir_p!(Path.dirname(ctx.path))

    File.write!(
      ctx.path,
      Jason.encode!([
        %{id: "e1", name: "one", code: "1 + 1", status: "ok", result: "2", output: "", ts: "10:00:00", duration_ms: 3},
        %{id: "e2", name: "two", code: "loop()", status: "running", result: "", output: "", ts: "10:00:01", duration_ms: nil}
      ])
    )

    Remote.ensure(ctx.node_id, ctx.session_id)
    [e1, e2] = Remote.snapshot(ctx.session_id).history
    assert e1.id == "e1" and e1.code == "1 + 1" and e1.status == "ok"
    # nothing is running after a restart
    assert e2.status == "stopped"

    Remote.delete_exec(ctx.session_id, "e1")
    assert [%{id: "e2"}] = Remote.snapshot(ctx.session_id).history
    assert [%{"id" => "e2"}] = ctx.path |> File.read!() |> Jason.decode!()

    # session delete takes the file with it — nothing else knows its name
    Remote.purge(ctx.session_id)
    refute File.exists?(ctx.path)
  end

  test "a session id can't escape the console directory", ctx do
    dir = Path.dirname(ctx.path)
    assert Path.dirname(Console.path("../../etc/passwd")) == dir
    assert Path.dirname(Console.path("a/b")) == dir
  end
end
