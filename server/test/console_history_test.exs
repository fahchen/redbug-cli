defmodule Server.Remote.ConsoleHistoryTest do
  @moduledoc """
  Console history survives a restart: the runner loads its session's JSON file
  on init, rewrites it as the history changes, and drops it on purge. No live
  target node needed.
  """
  use ExUnit.Case, async: false

  alias Server.{Config, Remote}
  alias Server.Remote.Console

  setup do
    {:ok, node_id} = Config.add_node(%{name: "target@127.0.0.1", cookie: "rbtest"})
    session_id = Config.gen_id()
    file = Console.path(session_id)

    on_exit(fn ->
      Remote.terminate(session_id)
      File.rm(file)
      File.rm(file <> ".tmp")
      Config.delete_node(node_id)
    end)

    %{node_id: node_id, session_id: session_id, path: file}
  end

  defp seed(ctx, execs) do
    File.mkdir_p!(Path.dirname(ctx.path))
    File.write!(ctx.path, Jason.encode!(execs))
    Remote.ensure(ctx.node_id, ctx.session_id)
  end

  defp exec(id, fields \\ %{}) do
    Map.merge(
      %{id: id, name: id, code: "1 + 1", status: "ok", result: "2", output: "", ts: "10:00:00", duration_ms: 3},
      fields
    )
  end

  test "restores persisted execs on init", ctx do
    seed(ctx, [exec("e1", %{code: "1 + 1"}), exec("e2")])

    assert [e1, e2] = Remote.snapshot(ctx.session_id).history
    assert e1.id == "e1"
    assert e1.code == "1 + 1"
    assert e1.status == "ok"
    assert e2.id == "e2"
  end

  test "restores a still-running exec as stopped", ctx do
    seed(ctx, [exec("e1", %{status: "running", duration_ms: nil})])

    assert [%{status: "stopped"}] = Remote.snapshot(ctx.session_id).history
  end

  test "rewrites the file when an exec is deleted", ctx do
    seed(ctx, [exec("e1"), exec("e2")])

    Remote.delete_exec(ctx.session_id, "e1")

    assert [%{id: "e2"}] = Remote.snapshot(ctx.session_id).history
    assert [%{"id" => "e2"}] = ctx.path |> File.read!() |> Jason.decode!()
  end

  test "purge drops the file — nothing else knows its name", ctx do
    seed(ctx, [exec("e1")])

    Remote.purge(ctx.session_id)

    refute File.exists?(ctx.path)
  end

  test "a session id can't escape the console directory", ctx do
    dir = Path.dirname(ctx.path)
    assert Path.dirname(Console.path("../../etc/passwd")) == dir
    assert Path.dirname(Console.path("a/b")) == dir
  end
end
