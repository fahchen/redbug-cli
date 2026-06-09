defmodule Server.Stores.TraceStore do
  @moduledoc """
  Root store that drives `:redbug` against a remote target node and streams the
  cooked trace events into the TUI. The controller node connects to `target`
  with a matching `cookie`; redbug auto-loads itself onto the target.

  Params (from the client root): `target`, `cookie`, `pattern`.
  """

  use Musubi.Store, root: true

  alias Server.TraceEvent

  require Logger

  @default_target "target@127.0.0.1"
  @default_cookie "poc"
  @default_pattern "lists:seq -> return"

  # Keep tracing effectively open-ended; the store process owns the redbug
  # session and stops it on terminate.
  @trace_time :timer.hours(24)
  @trace_msgs 1_000_000
  @keep -500

  state do
    stream(:events, TraceEvent.t(), item_key: & &1.id, limit: @keep)
  end

  @impl Musubi.Store
  def mount(params, socket) do
    target = param(params, "target", @default_target)
    cookie = param(params, "cookie", @default_cookie)
    pattern = param(params, "pattern", @default_pattern)

    # Start redbug off the mount path: connecting to an unreachable target node
    # can block for ~20s, which would otherwise stall the client on "mount".
    send(self(), {:start_trace, target, cookie, pattern})
    {:ok, socket}
  end

  @impl Musubi.Store
  def render(_socket) do
    %{events: stream(:events)}
  end

  @impl Musubi.Store
  def handle_command(_name, _payload, socket), do: {:noreply, socket}

  @impl Musubi.Store
  def handle_info({:start_trace, target, cookie, pattern}, socket) do
    me = self()
    target_node = String.to_atom(target)

    # redbug is a singleton, registered per target as `redbug_<target>`. A stale
    # session (e.g. a TUI that reconnected before its old store's terminate ran)
    # makes start a no-op (`:redbug_already_started`), leaving this client with no
    # events. Stop it *by target* and wait until it's actually down — stop/1 is
    # async (sends `stop` and returns) — so restart is idempotent.
    :redbug.stop(target_node)
    wait_redbug_down(String.to_atom("redbug_" <> target), 50)

    opts = [
      target: target_node,
      cookie: String.to_atom(cookie),
      time: @trace_time,
      msgs: @trace_msgs,
      print_fun: fn msg -> send(me, {:redbug, msg}) end
    ]

    # redbug.start returns {n_procs, n_funcs} locally, or {remote_node, n_procs,
    # n_funcs} when tracing a remote target. Anything else is a start error.
    case :redbug.start(String.to_charlist(pattern), opts) do
      {n_procs, n_funcs} when is_integer(n_procs) and is_integer(n_funcs) ->
        Logger.info("redbug tracing #{target}: #{n_procs} procs, #{n_funcs} funcs")

      {node, n_procs, n_funcs} when is_integer(n_procs) and is_integer(n_funcs) ->
        Logger.info("redbug tracing #{target} via #{node}: #{n_procs} procs, #{n_funcs} funcs")

      other ->
        Logger.error("redbug start failed for #{target}: #{inspect(other)}")
    end

    {:noreply, socket}
  end

  def handle_info({:redbug, msg}, socket) do
    case to_event(msg) do
      nil -> {:noreply, socket}
      event -> {:noreply, stream_insert(socket, :events, event, at: 0, limit: @keep)}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl Musubi.Store
  def terminate(_reason, _socket) do
    :redbug.stop()
    :ok
  end

  defp wait_redbug_down(_name, 0), do: :ok

  defp wait_redbug_down(name, retries) do
    case Process.whereis(name) do
      nil ->
        :ok

      _pid ->
        Process.sleep(20)
        wait_redbug_down(name, retries - 1)
    end
  end

  defp param(params, key, default) do
    case Map.get(params, key) do
      nil -> default
      "" -> default
      value -> value
    end
  end

  defp to_event({tag, payload, {pid, name_or_call}, ts})
       when tag in [:call, :retn, :send, :recv] do
    {mfa, info} = describe(tag, payload)

    %TraceEvent{
      id: Integer.to_string(System.unique_integer([:monotonic, :positive])),
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

  defp fmt_ts({h, m, s, _us}) do
    :io_lib.format("~2..0b:~2..0b:~2..0b", [h, m, s]) |> to_string()
  end

  defp fmt_ts(other), do: inspect(other)
end
