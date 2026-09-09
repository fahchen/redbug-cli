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

  alias Server.{Runners, Remote.Console}

  @registry Server.Remote.Registry
  @supervisor Server.Remote.Supervisor
  @pubsub Server.PubSub

  @doc "PubSub topic carrying a session's console exec inserts/updates."
  def topic(session_id), do: "console:" <> session_id

  @doc "Subscribe the caller to a session's console broadcasts."
  def subscribe(session_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(session_id))

  @doc """
  Start the session's runner if it is not up yet.

  Called on console mount so the runner restores its persisted history before
  `snapshot/1` reads it.
  """
  def ensure(node_id, session_id),
    do: Runners.ensure(@registry, @supervisor, Console, node_id, session_id)

  @doc "Run a code block on the session's node. Ensures a runner exists."
  def run(node_id, session_id, code, name) do
    Runners.ensure(@registry, @supervisor, Console, node_id, session_id)
    Console.run(session_id, code, name)
  end

  @doc "Force-stop (kill) a running execution."
  def stop(session_id, exec_id), do: Runners.with_runner(@registry, session_id, &Console.stop(&1, exec_id))

  @doc "Delete an execution entry from the history."
  def delete_exec(session_id, exec_id), do: Runners.with_runner(@registry, session_id, &Console.delete(&1, exec_id))

  @doc "Clear the execution history."
  def clear(session_id), do: Runners.with_runner(@registry, session_id, &Console.clear/1)

  @doc "Current execution history (newest first), or empty if no runner."
  def snapshot(session_id) do
    case Runners.whereis(@registry, session_id) do
      nil -> %{history: []}
      _pid -> Console.snapshot(session_id)
    end
  end

  @doc "Stop and remove a session's runner (on session delete)."
  def terminate(session_id), do: Runners.terminate(@registry, @supervisor, session_id)

  @doc """
  Drop a session's console for good: stop its runner and delete its persisted
  history. Nothing references the file but its `session_id`-derived name, so a
  deleted session would otherwise leave it behind forever.
  """
  def purge(session_id) do
    terminate(session_id)
    File.rm(Console.path(session_id))
    :ok
  end
end
