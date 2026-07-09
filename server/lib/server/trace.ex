defmodule Server.Trace do
  @moduledoc """
  Facade over the per-session `:redbug` runners.

  A `Server.Trace.Runner` GenServer owns the live redbug session for one config
  session plus its event buffer. Runners are started on demand under
  `Server.Trace.Supervisor` and addressed by `session_id` via
  `Server.Trace.Registry`. Stores (`Server.Stores.SessionRoot`) forward intent
  here and subscribe to per-session PubSub broadcasts; they never call `:redbug`
  directly.
  """

  alias Server.{Runners, Trace.Runner}

  @registry Server.Trace.Registry
  @supervisor Server.Trace.Supervisor
  @pubsub Server.PubSub

  @doc "PubSub topic carrying a session's trace events/status."
  def topic(session_id), do: "session:" <> session_id

  @doc "Subscribe the caller to a session's trace broadcasts."
  def subscribe(session_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(session_id))

  @doc "Start (or restart) tracing for a session. Ensures a runner exists."
  def start(node_id, session_id) do
    Runners.ensure(@registry, @supervisor, Runner, node_id, session_id)
    Runner.start(session_id)
  end

  @doc "Stop tracing; the event buffer is retained."
  def stop(session_id), do: Runners.with_runner(@registry, session_id, &Runner.stop/1)

  @doc "Mark a session stopped because its target node went down (buffer retained)."
  def node_down(session_id), do: Runners.with_runner(@registry, session_id, &Runner.node_down/1)

  @doc "Apply current config (RTP/limit edits) by restarting the trace; inserts a separator."
  def apply_restart(session_id), do: Runners.with_runner(@registry, session_id, &Runner.apply_restart/1)

  @doc "Clear the event buffer."
  def clear(session_id), do: Runners.with_runner(@registry, session_id, &Runner.clear/1)

  @doc "Current buffered events (newest first) and status, or empty/stopped if no runner."
  def snapshot(session_id) do
    case Runners.whereis(@registry, session_id) do
      nil -> %{events: [], status: "stopped", applied_sig: nil}
      _pid -> Runner.snapshot(session_id)
    end
  end

  @doc "Stop and remove a session's runner (on session delete)."
  def terminate(session_id), do: Runners.terminate(@registry, @supervisor, session_id)
end
