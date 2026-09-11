defmodule Server.Remote.Console do
  @moduledoc """
  Owns one session's Console: a capped, append-only history of code
  executions run on the target node.

  Each execution spawns `Server.Remote.Worker` on the target (after injecting
  its BEAM there) and monitors it, so a run is force-stoppable via
  `Process.exit(pid, :kill)` over distribution. A `@timeout` watchdog kills
  runaway evals. Results, output and status flow back as PubSub broadcasts on
  `Server.Remote.topic/1`; the store mirrors them into its stream.

  History is server-held, so it survives ws reconnects, and is mirrored to one
  JSON file per session next to the config (see `path/1`) so it also survives a
  restart. `stop/2` requires the caller to have confirmed (a TUI concern). Code
  is auto-formatted on run via `Server.Code.Format`.
  """

  use GenServer, restart: :transient

  require Logger

  alias Server.{Code.Format, Config}
  alias Server.Schema.ConsoleExec

  @registry Server.Remote.Registry
  @pubsub Server.PubSub
  @timeout 15_000
  @keep 200
  # A runaway `IO.puts` loop would otherwise grow one exec's output without
  # bound — and every finalize rewrites the whole history file.
  @max_output 64_000

  defstruct [:node_id, :session_id, history: [], running: %{}]

  # --- API ---

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via(session_id))
  end

  def run(session_id, code, name), do: GenServer.call(via(session_id), {:run, code, name})
  def stop(session_id, exec_id), do: GenServer.call(via(session_id), {:stop, exec_id})
  def delete(session_id, exec_id), do: GenServer.call(via(session_id), {:delete, exec_id})
  def clear(session_id), do: GenServer.call(via(session_id), :clear)
  def snapshot(session_id), do: GenServer.call(via(session_id), :snapshot)

  defp via(session_id), do: {:via, Registry, {@registry, session_id}}

  # --- callbacks ---

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)

    {:ok,
     %__MODULE__{
       node_id: Keyword.fetch!(opts, :node_id),
       session_id: session_id,
       history: load(session_id)
     }}
  end

  @impl true
  def handle_call({:run, code, name}, _from, state) do
    exec_id = Config.gen_id()

    entry = %ConsoleExec{
      id: exec_id,
      name: name || "",
      code: Format.run(code),
      status: "running",
      result: "",
      output: "",
      ts: Server.Time.hms(),
      duration_ms: nil
    }

    state = push(state, entry)
    broadcast(state, {:console_insert, entry})

    case launch(state, exec_id, entry.code) do
      {:ok, run_meta} ->
        {:reply, {:ok, exec_id}, %{state | running: Map.put(state.running, exec_id, run_meta)}}

      {:error, reason} ->
        state = finalize(state, exec_id, "error", "could not start: #{inspect(reason)}", "")
        {:reply, {:ok, exec_id}, state}
    end
  end

  def handle_call({:stop, exec_id}, _from, state) do
    case Map.get(state.running, exec_id) do
      nil ->
        {:reply, :ok, state}

      meta ->
        Process.exit(meta.pid, :kill)
        running = Map.put(state.running, exec_id, %{meta | cause: "stopped"})
        {:reply, :ok, %{state | running: running}}
    end
  end

  def handle_call({:delete, exec_id}, _from, state) do
    entry = Enum.find(state.history, &(&1.id == exec_id))
    if entry do
      broadcast(state, {:console_delete, exec_id})
    end

    state = persist(%{state | history: Enum.reject(state.history, &(&1.id == exec_id))})
    {:reply, :ok, state}
  end

  def handle_call(:clear, _from, state) do
    broadcast(state, {:console_reset})
    {:reply, :ok, persist(%{state | history: []})}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, %{history: state.history}, state}
  end

  @impl true
  # Live stdout: append each streamed chunk to the running exec and rebroadcast,
  # so output shows up as it happens rather than only on completion.
  def handle_info({:console_chunk, exec_id, chunk}, state) do
    case Map.get(state.running, exec_id) do
      nil -> {:noreply, state}
      _meta -> {:noreply, append_output(state, exec_id, chunk)}
    end
  end

  def handle_info({:console_result, exec_id, result, output}, state) do
    case Map.get(state.running, exec_id) do
      nil ->
        {:noreply, state}

      meta ->
        cancel(meta)
        {status, text} = split(result)
        {:noreply, finalize(state, exec_id, status, text, output, meta)}
    end
  end

  def handle_info({:timeout, exec_id}, state) do
    case Map.get(state.running, exec_id) do
      nil ->
        {:noreply, state}

      meta ->
        Process.exit(meta.pid, :kill)
        running = Map.put(state.running, exec_id, %{meta | cause: "timeout"})
        {:noreply, %{state | running: running}}
    end
  end

  # Worker exited before replying: kill (stop/timeout) or a genuine crash.
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case find_by_ref(state.running, ref) do
      nil ->
        {:noreply, state}

      {exec_id, meta} ->
        cancel(meta)
        {status, text} = down_outcome(meta.cause, reason)
        # nil output = keep whatever stdout was already streamed (stop/timeout
        # mid-run shouldn't wipe the partial output the user saw live).
        {:noreply, finalize(state, exec_id, status, text, nil, meta)}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    for {_id, meta} <- state.running, do: Process.exit(meta.pid, :kill)
    :ok
  end

  # --- launch ---

  defp launch(state, exec_id, code) do
    with {:ok, node} <- fetch_node(state.node_id),
         target = String.to_atom(node.name),
         :ok <- Config.connect_node(state.node_id),
         :ok <- ensure_worker(target) do
      pid = Node.spawn(target, Server.Remote.Worker, :run, [self(), exec_id, code])
      ref = Process.monitor(pid)
      timer = Process.send_after(self(), {:timeout, exec_id}, timeout_ms())
      {:ok, %{pid: pid, ref: ref, timer: timer, started: mono(), cause: nil}}
    end
  end

  defp fetch_node(node_id) do
    case Config.fetch_node(node_id) do
      nil -> {:error, :node_not_found}
      node -> {:ok, node}
    end
  end

  # Inject the worker BEAM onto the target so Node.spawn can reach it.
  defp ensure_worker(target) do
    case :code.get_object_code(Server.Remote.Worker) do
      {mod, bin, file} ->
        case :rpc.call(target, :code, :load_binary, [mod, file, bin]) do
          {:module, ^mod} -> :ok
          other -> {:error, other}
        end

      :error ->
        {:error, :worker_unavailable}
    end
  end

  # --- finalize / history ---

  defp finalize(state, exec_id, status, text, output, meta \\ nil) do
    duration = if meta, do: mono() - meta.started, else: 0

    history =
      Enum.map(state.history, fn e ->
        if e.id == exec_id do
          # nil output keeps the already-streamed stdout (see :DOWN handler).
          %{e | status: status, result: text, output: cap(output || e.output), duration_ms: duration}
        else
          e
        end
      end)

    entry = Enum.find(history, &(&1.id == exec_id))
    if entry, do: broadcast(state, {:console_update, entry})
    # Persist here (not on every streamed chunk): a finished exec is the only
    # state worth carrying across a restart.
    persist(%{state | history: history, running: Map.delete(state.running, exec_id)})
  end

  # Append a streamed stdout chunk to a still-running exec and rebroadcast.
  defp append_output(state, exec_id, chunk) do
    history =
      Enum.map(state.history, fn e ->
        if e.id == exec_id, do: %{e | output: cap(e.output <> chunk)}, else: e
      end)

    entry = Enum.find(history, &(&1.id == exec_id))
    if entry, do: broadcast(state, {:console_update, entry})
    %{state | history: history}
  end

  defp push(state, entry) do
    %{state | history: Enum.take([entry | state.history], @keep)}
  end

  # Slice by characters, not bytes: cutting mid-codepoint would produce invalid
  # UTF-8 that Jason.encode! then refuses. Re-capping an already-capped string is
  # a no-op beyond the marker.
  defp cap(text) when byte_size(text) <= @max_output, do: text
  defp cap(text), do: String.slice(text, 0, @max_output) <> "\n… output truncated"

  defp split({:ok, text}), do: {"ok", text}
  defp split({:error, text}), do: {"error", text}

  defp down_outcome("stopped", _reason), do: {"stopped", "stopped"}
  defp down_outcome("timeout", _reason), do: {"timeout", "timed out after #{timeout_ms()}ms"}
  defp down_outcome(_nil, reason), do: {"error", "process down: #{inspect(reason)}"}

  # Console watchdog timeout (ms), user-configurable via Settings; @timeout is the
  # fallback when a persisted settings map predates the field.
  defp timeout_ms, do: Map.get(Config.settings(), :console_timeout, @timeout)

  defp find_by_ref(running, ref) do
    Enum.find_value(running, fn {id, meta} -> if meta.ref == ref, do: {id, meta} end)
  end

  # --- persistence ---

  @doc "Absolute path of a session's persisted history file."
  def path(session_id) do
    Path.join([Path.dirname(Config.path()), "console", file_name(session_id)])
  end

  # `session_id` reaches us as a client-supplied mount param, so it never hits
  # the filesystem raw: hashing it yields a fixed-length name that can't contain
  # a separator or `..`. The id is opaque anyway, so nothing readable is lost.
  defp file_name(session_id) do
    digest = :sha256 |> :crypto.hash(session_id) |> Base.url_encode64(padding: false)
    digest <> ".json"
  end

  defp load(session_id) do
    with {:ok, body} <- File.read(path(session_id)),
         {:ok, list} when is_list(list) <- Jason.decode(body) do
      list |> Enum.map(&from_json/1) |> Enum.take(@keep)
    else
      _ -> []
    end
  end

  # The file holds code the user ran, so it gets the same 0600 treatment as the
  # config it sits next to.
  # Write-then-rename: a crash mid-write would otherwise leave truncated JSON,
  # which load/1 can only treat as "no history". chmod before the rename so the
  # file is never briefly world-readable.
  defp persist(state) do
    file = path(state.session_id)
    File.mkdir_p!(Path.dirname(file))
    tmp = file <> ".tmp"

    with :ok <- File.write(tmp, Jason.encode!(Enum.map(state.history, &Map.from_struct/1))),
         :ok <- File.chmod(tmp, 0o600) do
      File.rename(tmp, file)
    end

    state
  end

  defp from_json(j) do
    %ConsoleExec{
      id: Map.get(j, "id") || Config.gen_id(),
      name: Map.get(j, "name", ""),
      code: Map.get(j, "code", ""),
      # Nothing is running after a restart: a "running" row would spin forever.
      status: if(Map.get(j, "status") == "running", do: "stopped", else: Map.get(j, "status", "ok")),
      result: Map.get(j, "result", ""),
      output: Map.get(j, "output", ""),
      ts: Map.get(j, "ts", ""),
      duration_ms: Map.get(j, "duration_ms")
    }
  end

  defp cancel(%{ref: ref, timer: timer}) do
    Process.demonitor(ref, [:flush])
    if timer, do: Process.cancel_timer(timer)
  end

  # --- misc ---

  defp mono, do: System.monotonic_time(:millisecond)

  defp broadcast(state, message) do
    Phoenix.PubSub.broadcast(@pubsub, Server.Remote.topic(state.session_id), message)
  end
end
