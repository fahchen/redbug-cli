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
    :redbug_ref,
    :started_at,
    :applied_limits,
    status: "stopped",
    buffer: [],
    keep: 500,
    event_count: 0,
    applied_sig: nil,
    # per-pid LIFO stack of {pair_id, mfa} for open calls, used to give a call
    # and its return a shared `pair` id and the call `depth`.
    call_stack: %{},
    pair_seq: 0
  ]

  # --- API ---

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id))
  end

  def start(session_id), do: GenServer.call(via(session_id), :start)
  def stop(session_id), do: GenServer.call(via(session_id), :stop)
  def node_down(session_id), do: GenServer.cast(via(session_id), :node_down)
  def apply_restart(session_id), do: GenServer.call(via(session_id), :apply_restart)
  def clear(session_id), do: GenServer.call(via(session_id), :clear)
  def snapshot(session_id), do: GenServer.call(via(session_id), :snapshot)

  defp via(session_id), do: {:via, Registry, {@registry, session_id}}

  # --- callbacks ---

  @impl true
  def init(opts) do
    # Trap exits so a supervisor/disconnect shutdown runs terminate/2 → :redbug.stop,
    # tearing the trace off the target immediately — instead of leaving it to
    # redbug's own nodedown cleanup (or the time/msgs limits) once the controller
    # goes away. The catch-all handle_info absorbs any stray {:EXIT, _, _}.
    Process.flag(:trap_exit, true)

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
    state = demonitor_redbug(state)
    redbug_stop(state.target)
    Config.set_session_status(state.session_id, "stopped")
    new_state = %{state | status: "stopped"}
    broadcast(state.session_id, {:trace_status, status_payload(new_state)})
    {:reply, :ok, new_state}
  end

  def handle_call(:clear, _from, state) do
    new_state = %{state | buffer: [], call_stack: %{}}
    broadcast(state.session_id, {:trace_reset})
    {:reply, :ok, new_state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, %{events: state.buffer, status: state.status, applied_sig: state.applied_sig}, state}
  end

  @impl true
  # The target's dist link dropped (node restart / tunnel down). redbug doesn't
  # notify its print_fun on nodedown, so Config's node watcher tells us: flip to
  # stopped and push an error so the session stops showing a stale "running".
  def handle_cast(:node_down, state) do
    # nodedown also kills the redbug consumer; drop its monitor so the generic
    # "trace ended" DOWN doesn't race the clearer :noconnection message.
    state = demonitor_redbug(state)
    Config.set_session_status(state.session_id, "stopped")
    new_state = %{state | status: "stopped"}
    broadcast(state.session_id, {:trace_status, status_payload(new_state)})
    broadcast(state.session_id, {:trace_error, Server.Errors.humanize(:noconnection)})
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:redbug, msg}, state) do
    case cook(msg, state) do
      {:emit, event, state} -> {:noreply, emit_event(state, event)}
      {:ignore, state} -> {:noreply, state}
    end
  end

  # redbug's consumer process died on its own: it hit the time/msgs limit, was
  # stopped on the target (redbug is a singleton per node, so another client can
  # stop it), or crashed. redbug never routes this through print_fun, so without
  # this the session would keep showing a stale "running" with no new events.
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{redbug_ref: ref} = state) do
    # :normal = redbug hit its time/msgs cap (expected terminal); other reasons = crash.
    ended = if reason == :normal, do: which_limit(state), else: nil
    Config.set_session_status(state.session_id, "stopped")
    new_state = %{state | status: "stopped", redbug_ref: nil}
    broadcast(state.session_id, {:trace_status, status_payload(new_state, ended)})
    if ended == nil, do: broadcast(state.session_id, {:trace_error, ended_error(reason)})
    {:noreply, new_state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    redbug_stop(state.target)
    :ok
  end

  # --- start/stop redbug ---

  defp do_start(state, separator?) do
    # drop any prior monitor (and flush its DOWN) before we stop/replace redbug,
    # so restarting doesn't get mistaken for the trace ending.
    state = demonitor_redbug(state)

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
      ] ++ stack_opts(enabled)

      # redbug returns {ProcName, matched_functions, matched_procs} on success and
      # {:argument_error, reason} on a bad pattern. A pattern whose module/function/
      # arity isn't loaded on the target matches 0 functions (or errors), which we
      # surface instead of reporting a "running" trace that can never fire.
      case :redbug.start(patterns, opts) do
        {proc, matched, _procs} when is_atom(proc) and is_integer(matched) and matched > 0 ->
          state =
            state
            |> Map.put(:target, target)
            |> Map.put(:status, "running")
            |> Map.put(:keep, session.limits.keep)
            |> Map.put(:started_at, System.monotonic_time(:millisecond))
            |> Map.put(:applied_limits, session.limits)
            |> Map.put(:event_count, 0)
            |> Map.put(:call_stack, %{})
            |> Map.put(:pair_seq, 0)
            |> Map.put(:applied_sig, Server.Trace.Signature.compute(session.traces, session.limits))
            |> monitor_redbug(proc)
            |> maybe_separator(separator?)

          Config.set_session_status(state.session_id, "running")
          broadcast(state.session_id, {:trace_status, status_payload(state)})
          {:ok, state}

        {proc, 0, _procs} when is_atom(proc) ->
          state = %{state | status: "stopped"}
          Config.set_session_status(state.session_id, "stopped")
          broadcast(state.session_id, {:trace_status, status_payload(state)})
          {:error, :no_matching_functions, state}

        other ->
          Logger.error("redbug start failed for #{node.name}: #{inspect(other)}")
          state = %{state | status: "stopped"}
          Config.set_session_status(state.session_id, "stopped")
          broadcast(state.session_id, {:trace_status, status_payload(state)})
          {:error, redbug_error(other), state}
      end
    else
      {:error, reason} ->
        state = %{state | status: "stopped"}
        Config.set_session_status(state.session_id, "stopped")
        broadcast(state.session_id, {:trace_status, status_payload(state)})
        {:error, reason, state}
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
    {:ok, Enum.map(enabled, &to_pattern(&1.text))}
  end

  # redbug takes the atoms `send`/`'receive'` to trace messages (node-wide) and a
  # charlist RTP for call/return tracing. A bare "send"/"receive" RTP means "trace
  # messages"; everything else is a normal MFA pattern.
  defp to_pattern(text) do
    case String.trim(text) do
      "send" -> :send
      "receive" -> :receive
      _ -> text |> Server.Trace.Pattern.to_redbug() |> String.to_charlist()
    end
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

  @doc false
  def stack_opts(traces) do
    if Enum.any?(traces, &(String.contains?(&1.text, "stack"))),
      do: [max_msg_size: 2_000_000],
      else: []
  end

  defp redbug_error({:argument_error, :no_matching_functions}), do: :no_matching_functions
  defp redbug_error({:argument_error, reason}), do: "redbug: #{inspect(reason)}"
  defp redbug_error(other) when is_atom(other), do: other
  defp redbug_error(other), do: inspect(other)

  # --- redbug liveness (monitor the local consumer proc) ---

  defp monitor_redbug(state, proc) do
    ref =
      case Process.whereis(proc) do
        pid when is_pid(pid) -> Process.monitor(pid)
        _ -> nil
      end

    %{state | redbug_ref: ref}
  end

  defp demonitor_redbug(%{redbug_ref: ref} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    %{state | redbug_ref: nil}
  end

  defp demonitor_redbug(state), do: state

  # A clean :normal exit is the time/msgs limit firing (expected); anything else
  # is a crash. Either way the trace is no longer live and the user should know.
  defp ended_error(reason),
    do: Server.Errors.humanize("Trace ended on the target: #{inspect(reason)}")

  # --- buffer ---

  defp push_event(state, event) do
    %{state | buffer: Enum.take([event | state.buffer], state.keep)}
  end

  defp status_payload(state, ended \\ nil),
    do: %{status: state.status, applied_sig: state.applied_sig, ended: ended}

  # Which cap fired when redbug clean-exited: msgs if the count reached it, time
  # if the run lived long enough. A short clean exit is an external stop/restart,
  # not a limit.
  @doc false
  def which_limit(%{applied_limits: nil}), do: nil

  def which_limit(%{applied_limits: limits} = state) do
    elapsed = System.monotonic_time(:millisecond) - (state.started_at || 0)

    cond do
      state.event_count >= limits.msgs -> "msgs"
      elapsed >= limits.time * 1000 -> "time"
      true -> nil
    end
  end

  defp broadcast(session_id, message) do
    Phoenix.PubSub.broadcast(@pubsub, Server.Trace.topic(session_id), message)
  end

  # --- event mapping (from redbug print_fun message) ---

  # Broadcast an event and buffer it (newest first, capped), counting it toward
  # the msgs limit.
  defp emit_event(state, event) do
    broadcast(state.session_id, {:trace_event, event})
    %{push_event(state, event) | event_count: state.event_count + 1}
  end

  defp separator_event do
    message_event("restart", "", "", "", "restarted " <> Server.Time.hms(), Server.Time.hms())
  end

  # A call: emit it right away (real-time) with a fresh `pair` id and the current
  # nesting `depth`, and remember {pair, mfa} on the per-pid stack so its return
  # can reuse the same pair id.
  defp cook({:call, payload, {pid, name}, ts}, state) do
    {mfa, info} = describe(:call, payload)
    key = inspect(pid)
    stack = Map.get(state.call_stack, key, [])
    pair = Integer.to_string(state.pair_seq)

    ev = %Server.Schema.TraceEvent{
      id: event_id(),
      kind: "call",
      pid: key,
      name: pid_name(name),
      mfa: mfa,
      info: info,
      pair: pair,
      depth: length(stack),
      ts: fmt_ts(ts)
    }

    state = %{state | call_stack: Map.put(state.call_stack, key, [{pair, mfa} | stack]), pair_seq: state.pair_seq + 1}
    {:emit, ev, state}
  end

  # A return: pop the matching open call (same pid, same MFA at the LIFO top) and
  # reuse its pair id + depth. No match (call evicted, trace started mid-flight,
  # or MFA mismatch) → emit unpaired (empty pair, depth 0).
  defp cook({:retn, payload, {pid, name}, ts}, state) do
    {mfa, ret} = describe(:retn, payload)
    key = inspect(pid)

    {pair, depth, stacks} =
      case state.call_stack do
        %{^key => [{pair, ^mfa} | rest]} -> {pair, length(rest), Map.put(state.call_stack, key, rest)}
        _ -> {"", 0, state.call_stack}
      end

    ev = %{message_event("retn", key, pid_name(name), mfa, ret, fmt_ts(ts)) | pair: pair, depth: depth}
    {:emit, ev, %{state | call_stack: stacks}}
  end

  defp cook({tag, payload, {pid, name}, ts}, state) when tag in [:send, :recv] do
    {mfa, info} = describe(tag, payload)
    {:emit, message_event(Atom.to_string(tag), inspect(pid), pid_name(name), mfa, info, fmt_ts(ts)), state}
  end

  defp cook(_other, state), do: {:ignore, state}

  # Build a non-call event (no pairing): empty pair, depth 0.
  defp message_event(kind, pid, name, mfa, info, ts) do
    %Server.Schema.TraceEvent{
      id: event_id(),
      kind: kind,
      pid: pid,
      name: name,
      mfa: mfa,
      info: info,
      pair: "",
      depth: 0,
      ts: ts
    }
  end

  defp describe(:call, {{m, f, args}, stack}) do
    info =
      case stack_info(stack) do
        "" -> pp(args)
        s -> pp(args) <> "\n" <> s
      end

    {fmt_mf(m, f, length(args)), info}
  end

  defp describe(:retn, {{m, f, a}, ret}), do: {fmt_mf(m, f, a), pp(ret)}
  defp describe(:send, {message, to}), do: {"send", "→ #{inspect(to)}: #{pp(message)}"}
  defp describe(:recv, message), do: {"recv", pp(message)}
  defp describe(tag, payload), do: {Atom.to_string(tag), pp(payload)}

  defp stack_info(<<>>), do: ""
  defp stack_info(stack) when is_binary(stack) do
    stack
    |> String.split("\n")
    |> Enum.filter(&(String.contains?(&1, "cp = ") or String.contains?(&1, "Return addr")))
    |> Enum.take(8)
    |> Enum.join("\n")
  end
  defp stack_info(_), do: ""

  defp fmt_mf(m, f, a), do: "#{inspect(m)}.#{f}/#{a}"

  defp pid_name(name) when is_atom(name), do: Atom.to_string(name)
  defp pid_name({m, f, a}), do: fmt_mf(m, f, a)
  defp pid_name(other), do: inspect(other)

  defp fmt_ts({h, m, s, us}) do
    :io_lib.format("~2..0b:~2..0b:~2..0b.~3..0b", [h, m, s, div(us, 1000)])
    |> to_string()
  end

  defp fmt_ts(other), do: inspect(other)

  defp event_id, do: Integer.to_string(System.unique_integer([:monotonic, :positive]))

  # Pretty-print an Erlang/Elixir term with no length limit, so maps, lists,
  # and tuples render fully indented in the TUI detail pane.
  defp pp(term), do: inspect(term, limit: :infinity, pretty: true, width: 100)
end
