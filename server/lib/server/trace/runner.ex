defmodule Server.Trace.Runner do
  @moduledoc """
  Owns a live `:redbug` session for one config session plus its event buffer.

  redbug is a singleton per target node (registered `redbug_<target>`); patterns
  are compiled at start with no hot-add, so applying RTP/limit edits = stop +
  start (`apply_restart/1`), which inserts a `restart` separator and keeps the
  buffer. `stop/1` retains the buffer (stop ≠ clear); `clear/1` empties it.

  Trace events arrive via redbug's `print_fun` (a separate process) which sends
  `{:redbug, msg}` here; cooked rows are buffered (capped at the session's
  `keep` limit, newest first) and broadcast on `Server.Trace.topic/1`.
  """

  use GenServer, restart: :transient

  require Logger

  alias Server.Config

  @registry Server.Trace.Registry
  @pubsub Server.PubSub

  defstruct [
    :node_id,
    :session_id,
    :target,
    status: "stopped",
    buffer: [],
    keep: 500,
    applied_sig: nil
  ]

  # --- API ---

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id))
  end

  def start(session_id), do: GenServer.call(via(session_id), :start)
  def stop(session_id), do: GenServer.call(via(session_id), :stop)
  def apply_restart(session_id), do: GenServer.call(via(session_id), :apply_restart)
  def clear(session_id), do: GenServer.call(via(session_id), :clear)
  def snapshot(session_id), do: GenServer.call(via(session_id), :snapshot)

  defp via(session_id), do: {:via, Registry, {@registry, session_id}}

  # --- callbacks ---

  @impl true
  def init(opts) do
    state = %__MODULE__{
      node_id: Keyword.fetch!(opts, :node_id),
      session_id: Keyword.fetch!(opts, :session_id)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:start, _from, state) do
    case do_start(state, _separator? = false) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason, new_state} -> {:reply, {:error, reason}, new_state}
    end
  end

  def handle_call(:apply_restart, _from, state) do
    case do_start(state, _separator? = true) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      {:error, reason, new_state} -> {:reply, {:error, reason}, new_state}
    end
  end

  def handle_call(:stop, _from, state) do
    redbug_stop(state.target)
    Config.set_session_status(state.session_id, "stopped")
    new_state = %{state | status: "stopped"}
    broadcast(state.session_id, {:trace_status, status_payload(new_state)})
    {:reply, :ok, new_state}
  end

  def handle_call(:clear, _from, state) do
    new_state = %{state | buffer: []}
    broadcast(state.session_id, {:trace_reset})
    {:reply, :ok, new_state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, %{events: state.buffer, status: state.status, applied_sig: state.applied_sig}, state}
  end

  @impl true
  def handle_info({:redbug, msg}, state) do
    case to_event(msg) do
      nil ->
        {:noreply, state}

      event ->
        new_state = push_event(state, event)
        broadcast(state.session_id, {:trace_event, event})
        {:noreply, new_state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    redbug_stop(state.target)
    :ok
  end

  # --- start/stop redbug ---

  defp do_start(state, separator?) do
    with {:ok, node} <- fetch_node(state.node_id),
         {:ok, session} <- fetch_session(node, state.session_id),
         enabled = Enum.filter(session.traces, & &1.enabled),
         {:ok, patterns} <- require_patterns(enabled) do
      target = String.to_atom(node.name)
      Config.connect_node(state.node_id)

      redbug_stop(target)
      wait_redbug_down(target, 50)

      opts = [
        target: target,
        cookie: cookie_atom(node),
        time: session.limits.time * 1000,
        msgs: session.limits.msgs,
        print_fun: print_fun(self())
      ]

      case :redbug.start(patterns, opts) do
        result when is_tuple(result) and tuple_size(result) in [2, 3] ->
          state =
            state
            |> Map.put(:target, target)
            |> Map.put(:status, "running")
            |> Map.put(:keep, session.limits.keep)
            |> Map.put(:applied_sig, Server.Trace.Signature.compute(session.traces, session.limits))
            |> maybe_separator(separator?)

          Config.set_session_status(state.session_id, "running")
          broadcast(state.session_id, {:trace_status, status_payload(state)})
          {:ok, state}

        other ->
          Logger.error("redbug start failed for #{node.name}: #{inspect(other)}")
          {:error, redbug_error(other), %{state | status: "stopped"}}
      end
    else
      {:error, reason} -> {:error, reason, %{state | status: "stopped"}}
    end
  end

  defp maybe_separator(state, false), do: state

  defp maybe_separator(state, true) do
    sep = separator_event()
    state = push_event(state, sep)
    broadcast(state.session_id, {:trace_event, sep})
    state
  end

  defp require_patterns([]), do: {:error, :no_enabled_rtp}

  defp require_patterns(enabled) do
    {:ok,
     Enum.map(enabled, &(&1.text |> Server.Trace.Pattern.to_redbug() |> String.to_charlist()))}
  end

  defp fetch_node(node_id) do
    case Config.fetch_node(node_id) do
      nil -> {:error, :node_not_found}
      node -> {:ok, node}
    end
  end

  defp fetch_session(node, session_id) do
    case Enum.find(node.sessions, &(&1.id == session_id)) do
      nil -> {:error, :session_not_found}
      session -> {:ok, session}
    end
  end

  defp cookie_atom(node) do
    case Map.get(node, :cookie) do
      nil -> :""
      "" -> :""
      c -> String.to_atom(c)
    end
  end

  defp redbug_stop(nil), do: :ok
  defp redbug_stop(target), do: :redbug.stop(target)

  defp wait_redbug_down(_target, 0), do: :ok

  defp wait_redbug_down(target, retries) do
    name = String.to_atom("redbug_" <> Atom.to_string(target))

    case Process.whereis(name) do
      nil ->
        :ok

      _pid ->
        Process.sleep(20)
        wait_redbug_down(target, retries - 1)
    end
  end

  defp print_fun(runner), do: fn msg -> send(runner, {:redbug, msg}) end

  defp redbug_error({:argument_error, _} = e), do: inspect(e)
  defp redbug_error(other) when is_atom(other), do: other
  defp redbug_error(other), do: inspect(other)

  # --- buffer ---

  defp push_event(state, event) do
    %{state | buffer: Enum.take([event | state.buffer], state.keep)}
  end

  defp status_payload(state), do: %{status: state.status, applied_sig: state.applied_sig}

  defp broadcast(session_id, message) do
    Phoenix.PubSub.broadcast(@pubsub, Server.Trace.topic(session_id), message)
  end

  # --- event mapping (from redbug print_fun message) ---

  defp separator_event do
    %Server.Schema.TraceEvent{
      id: event_id(),
      kind: "restart",
      pid: "",
      name: "",
      mfa: "",
      info: "restarted " <> now_hms(),
      ts: now_hms()
    }
  end

  defp to_event({tag, payload, {pid, name_or_call}, ts})
       when tag in [:call, :retn, :send, :recv] do
    {mfa, info} = describe(tag, payload)

    %Server.Schema.TraceEvent{
      id: event_id(),
      kind: Atom.to_string(tag),
      pid: inspect(pid),
      name: pid_name(name_or_call),
      mfa: mfa,
      info: info,
      ts: fmt_ts(ts)
    }
  end

  defp to_event(_other), do: nil

  defp describe(:call, {{m, f, args}, _stack}), do: {fmt_mf(m, f, length(args)), inspect(args)}
  defp describe(:retn, {{m, f, a}, ret}), do: {fmt_mf(m, f, a), inspect(ret)}
  defp describe(:send, {message, to}), do: {"send", "→ #{inspect(to)}: #{inspect(message)}"}
  defp describe(:recv, message), do: {"recv", inspect(message)}
  defp describe(tag, payload), do: {Atom.to_string(tag), inspect(payload)}

  defp fmt_mf(m, f, a), do: "#{inspect(m)}.#{f}/#{a}"

  defp pid_name(name) when is_atom(name), do: Atom.to_string(name)
  defp pid_name({m, f, a}), do: fmt_mf(m, f, a)
  defp pid_name(other), do: inspect(other)

  defp fmt_ts({h, m, s, us}) do
    :io_lib.format("~2..0b:~2..0b:~2..0b.~3..0b", [h, m, s, div(us, 1000)])
    |> to_string()
  end

  defp fmt_ts(other), do: inspect(other)

  defp now_hms do
    {_, {h, m, s}} = :calendar.local_time()
    :io_lib.format("~2..0b:~2..0b:~2..0b", [h, m, s]) |> to_string()
  end

  defp event_id, do: Integer.to_string(System.unique_integer([:monotonic, :positive]))
end
