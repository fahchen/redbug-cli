defmodule Server.Runners do
  @moduledoc """
  Shared lifecycle for per-session runner GenServers.

  `Server.Trace` and `Server.Remote` are thin facades over their own runner
  module (`Trace.Runner` / `Remote.Console`), but the plumbing is identical:
  each runner is addressed by `session_id` through a `Registry` and started on
  demand under a `DynamicSupervisor`. That registry/supervisor bookkeeping lives
  here so the two facades stay in lock-step.
  """

  @doc "Pid of the session's runner, or `nil` when none is running."
  def whereis(registry, session_id) do
    case Registry.lookup(registry, session_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "Start `child` for the session if no runner exists; no-op if one already runs."
  def ensure(registry, supervisor, child, node_id, session_id) do
    case whereis(registry, session_id) do
      nil -> DynamicSupervisor.start_child(supervisor, {child, node_id: node_id, session_id: session_id})
      _pid -> :ok
    end
  end

  @doc "Run `fun.(session_id)` only if a runner exists; `:ok` otherwise."
  def with_runner(registry, session_id, fun) do
    case whereis(registry, session_id) do
      nil -> :ok
      _pid -> fun.(session_id)
    end
  end

  @doc "Stop and remove the session's runner (on session delete); `:ok` if none."
  def terminate(registry, supervisor, session_id) do
    case whereis(registry, session_id) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(supervisor, pid)
    end
  end
end
