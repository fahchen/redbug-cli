defmodule Server.Tui.Bridge do
  @moduledoc """
  Sends the controller state to the Terra runtime of the TUI.

  It subscribes to the config broadcasts and, for each burst of
  `{:config_updated}` messages, casts one `{:event, {:nodes, nodes, settings}}`
  to the runtime. While the TUI shows a session (`watch/2`), it also subscribes
  to the trace topic of that session, casts `{:trace_snapshot, session_id,
  snapshot}` (`Server.Trace.snapshot/1` after the subscription), and casts the
  trace messages in batches: `{:trace_events, session_id, events}` (newest
  first; an event can also be in the snapshot), `{:trace_status,
  session_id, payload}`, `{:trace_error, session_id, error}`, and
  `{:trace_reset, session_id}`. It stops when the runtime stops.
  """

  alias Server.{Config, Remote, Trace}

  # the most trace events in one batch
  @batch 500

  @doc """
  Starts the bridge for `runtime`. With `query_size: true`, it first asks the
  runtime to read the terminal size, which gives the app a `{:resize, w, h}`.
  """
  @spec start_link(pid(), keyword()) :: pid()
  def start_link(runtime, opts) do
    spawn_link(fn ->
      Process.monitor(runtime)
      Config.subscribe()
      # A change between the snapshot of init/1 and the subscription has no broadcast left.
      send_state(runtime)
      # The runtime handles this call after its init/1, which starts the bridge.
      if Keyword.fetch!(opts, :query_size), do: Terra.Runtime.resize(runtime)
      loop(runtime, nil)
    end)
  end

  @doc """
  Follows the console topic of the watched session `session_id` and casts
  `{:console, session_id, message}`: first `{:console_snapshot, snapshot}`,
  then the console messages.
  """
  @spec console(pid(), String.t(), String.t()) :: :ok
  def console(bridge, node_id, session_id) do
    send(bridge, {:console, node_id, session_id})
    :ok
  end

  @doc "Follows the trace topic of `session_id`, or of no session with `nil`."
  @spec watch(pid(), String.t() | nil) :: :ok
  def watch(bridge, session_id) do
    send(bridge, {:watch, session_id})
    :ok
  end

  defp loop(runtime, session) do
    receive do
      {:DOWN, _ref, :process, ^runtime, _reason} -> :ok
      message -> loop(runtime, handle(message, runtime, session))
    end
  end

  defp handle({:config_updated}, runtime, session) do
    flush()
    send_state(runtime)
    session
  end

  defp handle({:watch, next}, runtime, session) do
    if session, do: Phoenix.PubSub.unsubscribe(Server.PubSub, Trace.topic(session))
    if session, do: Phoenix.PubSub.unsubscribe(Server.PubSub, Remote.topic(session))
    if next, do: watch_session(runtime, next)
    next
  end

  # As ConsoleRoot.mount/2: the runner restores its history before the snapshot.
  defp handle({:console, node_id, session}, runtime, session) do
    Remote.subscribe(session)
    Remote.ensure(node_id, session)
    cast(runtime, {:console, session, {:console_snapshot, Remote.snapshot(session)}})
    session
  end

  defp handle(_message, _runtime, nil), do: nil

  defp handle({:trace_event, event}, runtime, session) do
    {events, pending} = take_events([event], 1)
    cast(runtime, {:trace_events, session, events})
    if pending, do: handle(pending, runtime, session), else: session
  end

  defp handle({:trace_status, payload}, runtime, session) do
    cast(runtime, {:trace_status, session, payload})
    session
  end

  defp handle({:trace_error, error}, runtime, session) do
    cast(runtime, {:trace_error, session, error})
    session
  end

  defp handle({:trace_reset}, runtime, session) do
    cast(runtime, {:trace_reset, session})
    session
  end

  defp handle({tag, _} = message, runtime, session)
       when tag in [:console_insert, :console_update, :console_delete] do
    cast(runtime, {:console, session, message})
    session
  end

  defp handle({:console_reset}, runtime, session) do
    cast(runtime, {:console, session, :console_reset})
    session
  end

  defp handle(_other, _runtime, session), do: session

  # The snapshot comes after the subscription, so no event falls between them.
  defp watch_session(runtime, session) do
    Trace.subscribe(session)
    cast(runtime, {:trace_snapshot, session, Trace.snapshot(session)})
  end

  defp cast(runtime, message), do: GenServer.cast(runtime, {:event, message})

  defp send_state(runtime), do: cast(runtime, {:nodes, Config.nodes(), Config.settings()})

  # The trace events that are already queued go in the same batch, newest
  # first. The batch stops at the next other trace message, which is returned
  # as pending, so the order of the trace messages stays the same.
  defp take_events(acc, n) when n >= @batch, do: {acc, nil}

  defp take_events(acc, n) do
    receive do
      {:trace_event, event} -> take_events([event | acc], n + 1)
      {tag, _} = message when tag in [:trace_status, :trace_error] -> {acc, message}
      {:trace_reset} = message -> {acc, message}
    after
      0 -> {acc, nil}
    end
  end

  # One batch for each burst: drop the updates that are already queued.
  defp flush do
    receive do
      {:config_updated} -> flush()
    after
      0 -> :ok
    end
  end
end
