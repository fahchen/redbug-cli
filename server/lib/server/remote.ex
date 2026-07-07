defmodule Server.Remote do
  @moduledoc """
  Facade over the per-session `Server.Remote.Console` runners.

  A console runner owns one session's execution history and spawns/kills work
  on the target node. Runners are started on demand under
  `Server.Remote.Supervisor`, addressed by `session_id` via
  `Server.Remote.Registry`. The `Server.Stores.ConsoleRoot` store forwards
  intent here and subscribes to per-session PubSub broadcasts; it never spawns
  remote work directly.
  """

  alias Server.Remote.Console

  @registry Server.Remote.Registry
  @supervisor Server.Remote.Supervisor
  @pubsub Server.PubSub

  @doc "PubSub topic carrying a session's console exec inserts/updates."
  def topic(session_id), do: "console:" <> session_id

  @doc "Subscribe the caller to a session's console broadcasts."
  def subscribe(session_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(session_id))

  @doc "Run a code block on the session's node. Ensures a runner exists."
  def run(node_id, session_id, code, name) do
    ensure_runner(node_id, session_id)
    Console.run(session_id, code, name)
  end

  @doc "Force-stop (kill) a running execution."
  def stop(session_id, exec_id), do: with_runner(session_id, &Console.stop(&1, exec_id))

  @doc "Delete an execution entry from the history."
  def delete_exec(session_id, exec_id), do: with_runner(session_id, &Console.delete(&1, exec_id))

  @doc "Clear the execution history."
  def clear(session_id), do: with_runner(session_id, &Console.clear/1)

  @doc "Current execution history (newest first), or empty if no runner."
  def snapshot(session_id) do
    case whereis(session_id) do
      nil -> %{history: []}
      _pid -> Console.snapshot(session_id)
    end
  end

  @doc "Stop and remove a session's runner (on session delete)."
  def terminate(session_id) do
    case whereis(session_id) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(@supervisor, pid)
    end
  end

  # --- internals ---

  defp ensure_runner(node_id, session_id) do
    case whereis(session_id) do
      nil ->
        spec = {Console, node_id: node_id, session_id: session_id}
        DynamicSupervisor.start_child(@supervisor, spec)

      _pid ->
        :ok
    end
  end

  defp with_runner(session_id, fun) do
    case whereis(session_id) do
      nil -> :ok
      _pid -> fun.(session_id)
    end
  end

  defp whereis(session_id) do
    case Registry.lookup(@registry, session_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end
end
