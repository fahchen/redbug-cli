defmodule Server.Tui.Bridge do
  @moduledoc """
  Sends the controller state to the Terra runtime of the TUI.

  It subscribes to the config broadcasts and, for each burst of
  `{:config_updated}` messages, casts one `{:event, {:nodes, nodes, settings}}`
  to the runtime. While the TUI shows a session (`watch/2`), it also subscribes
  to the trace topic of that session and casts the trace messages in batches:
  `{:trace_events, session_id, events}` (newest first), `{:trace_status,
  session_id, payload}`, `{:trace_error, session_id, error}`, and
  `{:trace_reset, session_id}`. It stops when the runtime stops.
  """

  alias Server.{Config, Trace}

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

  @doc "Follows the trace topic of `session_id`, or of no session with `nil`."
  @spec watch(pid(), String.t() | nil) :: :ok
  def watch(bridge, session_id) do
    send(bridge, {:watch, session_id})
    :ok
  end

  defp loop(runtime, session) do
    receive do
      {:config_updated} ->
        flush()
        send_state(runtime)
        loop(runtime, session)

      {:watch, next} ->
        if session, do: Phoenix.PubSub.unsubscribe(Server.PubSub, Trace.topic(session))
        if next, do: Trace.subscribe(next)
        loop(runtime, next)

      {:trace_event, event} when session != nil ->
        cast(runtime, {:trace_events, session, take_events([event], 1)})
        loop(runtime, session)

      {:trace_status, payload} when session != nil ->
        cast(runtime, {:trace_status, session, payload})
        loop(runtime, session)

      {:trace_error, error} when session != nil ->
        cast(runtime, {:trace_error, session, error})
        loop(runtime, session)

      {:trace_reset} when session != nil ->
        cast(runtime, {:trace_reset, session})
        loop(runtime, session)

      {:DOWN, _ref, :process, ^runtime, _reason} ->
        :ok

      _other ->
        loop(runtime, session)
    end
  end

  defp cast(runtime, message), do: GenServer.cast(runtime, {:event, message})

  defp send_state(runtime), do: cast(runtime, {:nodes, Config.nodes(), Config.settings()})

  # The trace events that are already queued go in the same batch, newest first.
  defp take_events(acc, n) when n >= @batch, do: acc

  defp take_events(acc, n) do
    receive do
      {:trace_event, event} -> take_events([event | acc], n + 1)
    after
      0 -> acc
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
