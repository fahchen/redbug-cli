defmodule Server.Stores.SessionRoot do
  @moduledoc """
  Root store for one session's S3 screen (RTP editing + live trace).

  Mounted with `node_id`/`session_id` params. Reads session config (traces,
  limits) from `Server.Config` and live trace events/status from the session's
  `Server.Trace.Runner` via the `Server.Trace.topic/1` PubSub topic. RTP/limit
  commands forward to `Server.Config` (persisted); start/stop/apply/clear
  forward to `Server.Trace` (runtime side-effects). The store itself never
  touches `:redbug`.

  `dirty` means the running trace's compiled patterns/limits differ from the
  current (edited) config — surfaced as the "unapplied" marker, computed via
  the shared `Server.Trace.Signature`.
  """

  use Musubi.Store, root: true

  import Server.Stores.Payload, only: [get: 2, get: 3, put_if: 4, map_trace: 3]

  alias Server.{Config, Trace}

  state do
    field(:node_id, String.t())
    field(:session_id, String.t())
    field(:name, String.t())
    field(:status, String.t())
    field(:node_status, String.t())
    field(:node_error, Server.Schema.AppError.t() | nil)
    field(:dirty, boolean())
    field(:ended, String.t() | nil)
    field(:error, Server.Schema.AppError.t() | nil)
    field(:traces, list(Server.Schema.Rtp.t()))
    field(:limits, Server.Schema.Limits.t())
    stream(:events, Server.Schema.TraceEvent.t(), item_key: & &1.id, limit: 2000)
  end

  command :addTrace do
    payload do
      field(:text, String.t())
    end
  end

  command :updateTrace do
    payload do
      field(:trace_id, String.t())
      field(:text, String.t())
    end
  end

  command :deleteTrace do
    payload do
      field(:trace_id, String.t())
    end
  end

  command :toggleTrace do
    payload do
      field(:trace_id, String.t())
    end
  end

  command :updateLimits do
    payload do
      field(:keep, integer() | nil)
      field(:time, integer() | nil)
      field(:msgs, integer() | nil)
    end
  end

  command :startTrace do
    payload do
    end
  end

  command :stopTrace do
    payload do
    end
  end

  command :applyRestart do
    payload do
    end
  end

  command :clearEvents do
    payload do
    end
  end

  command :deleteEvent do
    payload do
      field(:id, String.t())
    end
  end

  command :reconnect do
    payload do
    end
  end

  command :saveAsPreset do
    payload do
      field(:name, String.t())
    end
  end

  @impl true
  def mount(params, socket) do
    node_id = Map.get(params, "node_id")
    session_id = Map.get(params, "session_id")

    Config.subscribe()
    Trace.subscribe(session_id)

    # Entering a session auto-connects its node (unless already connected). The
    # async request drives status + retry in Config and broadcasts each step,
    # which reflows through {:config_updated} into node_status/node_error below.
    if Config.node_connection(node_id).status != "connected",
      do: Config.request_connect(node_id)

    snap = Trace.snapshot(session_id)

    socket =
      socket
      |> assign(:node_id, node_id)
      |> assign(:session_id, session_id)
      |> assign(:applied_sig, snap.applied_sig)
      |> load_session()
      |> put_node_conn()
      |> put_status(snap.status)
      |> stream(:events, snap.events, reset: true)

    {:ok, socket}
  end

  # Leaving the session screen stops its trace (the client confirms first when
  # running — see the exit prompt). Trace.stop is a no-op when nothing is running.
  @impl true
  def terminate(_reason, socket) do
    Trace.stop(socket.assigns.session_id)
    :ok
  end

  @impl true
  def render(socket) do
    a = socket.assigns

    %{
      node_id: a.node_id,
      session_id: a.session_id,
      name: a.name,
      status: a.status,
      node_status: a.node_status,
      node_error: Map.get(a, :node_error),
      dirty: a.dirty,
      ended: Map.get(a, :ended),
      error: Map.get(a, :error),
      traces: a.traces,
      limits: a.limits,
      events: stream(:events)
    }
  end

  @impl true
  def handle_info({:config_updated}, socket) do
    # config_updated also fires on node connection status changes; refresh the
    # node conn assigns so the banner/glyph re-render (render reads assigns, so
    # storing it here is what makes musubi re-render on a status-only change).
    {:noreply, socket |> load_session() |> put_node_conn() |> recompute_dirty()}
  end

  def handle_info({:trace_event, event}, socket) do
    {:noreply, stream_insert(socket, :events, event, at: 0, limit: keep(socket))}
  end

  def handle_info({:trace_reset}, socket) do
    {:noreply, stream(socket, :events, [], reset: true)}
  end

  def handle_info({:trace_status, %{status: status, applied_sig: applied_sig} = payload}, socket) do
    socket =
      socket
      |> assign(:applied_sig, applied_sig)
      |> assign(:ended, Map.get(payload, :ended))
      |> put_status(status)

    {:noreply, socket}
  end

  def handle_info({:trace_error, error}, socket) do
    {:noreply, socket |> assign(:error, error) |> put_status("stopped")}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_command(:addTrace, payload, socket) do
    text = get(payload, "text", "")

    if text == "" do
      {:noreply, socket}
    else
      rtp = %{id: Config.gen_id(), text: text, enabled: true}
      update_traces(socket, fn traces -> traces ++ [rtp] end)
      {:noreply, socket}
    end
  end

  def handle_command(:updateTrace, payload, socket) do
    id = get(payload, "trace_id")
    text = get(payload, "text", "")
    update_traces(socket, fn traces -> map_trace(traces, id, &%{&1 | text: text}) end)
    {:noreply, socket}
  end

  def handle_command(:deleteTrace, payload, socket) do
    id = get(payload, "trace_id")
    update_traces(socket, fn traces -> Enum.reject(traces, &(&1.id == id)) end)
    {:noreply, socket}
  end

  def handle_command(:toggleTrace, payload, socket) do
    id = get(payload, "trace_id")
    update_traces(socket, fn traces -> map_trace(traces, id, &%{&1 | enabled: not &1.enabled}) end)
    {:noreply, socket}
  end

  def handle_command(:updateLimits, payload, socket) do
    limits =
      socket.assigns.limits
      |> put_if(payload, "keep", :keep)
      |> put_if(payload, "time", :time)
      |> put_if(payload, "msgs", :msgs)

    Config.update_session(socket.assigns.node_id, socket.assigns.session_id, %{limits: limits})
    {:noreply, socket}
  end

  def handle_command(:startTrace, _payload, socket) do
    result = Trace.start(socket.assigns.node_id, socket.assigns.session_id)
    {:noreply, put_error(socket, result)}
  end

  def handle_command(:stopTrace, _payload, socket) do
    Trace.stop(socket.assigns.session_id)
    {:noreply, assign(socket, :error, nil)}
  end

  def handle_command(:applyRestart, _payload, socket) do
    result = Trace.apply_restart(socket.assigns.session_id)
    {:noreply, put_error(socket, result)}
  end

  def handle_command(:clearEvents, _payload, socket) do
    Trace.clear(socket.assigns.session_id)
    {:noreply, assign(socket, :error, nil)}
  end

  def handle_command(:deleteEvent, payload, socket) do
    id = get(payload, "id")
    {:noreply, stream_delete_by_item_key(socket, :events, id)}
  end

  # Manual retry after the node connect gave up (:error). request_connect resets
  # the retry counter and re-drives the status machine.
  def handle_command(:reconnect, _payload, socket) do
    Config.request_connect(socket.assigns.node_id)
    {:noreply, socket}
  end

  def handle_command(:saveAsPreset, payload, socket) do
    name = get(payload, "name", "")

    if name != "" do
      traces = Enum.map(socket.assigns.traces, fn t -> %{t | id: Config.gen_id()} end)
      Config.add_preset(%{name: name, traces: traces, limits: socket.assigns.limits})
    end

    {:noreply, socket}
  end

  def handle_command(_name, _payload, socket), do: {:noreply, socket}

  # --- helpers ---

  defp put_node_conn(socket) do
    conn = Config.node_connection(socket.assigns.node_id)

    socket
    |> assign(:node_status, conn.status)
    |> assign(:node_error, conn.error)
  end

  defp put_error(socket, :ok), do: assign(socket, :error, nil)
  defp put_error(socket, {:error, reason}), do: assign(socket, :error, Server.Errors.humanize(reason))

  defp load_session(socket) do
    case current_session(socket) do
      nil ->
        socket
        |> assign(:name, "")
        |> assign(:traces, [])
        |> assign(:limits, Config.settings().default_limits)
        |> assign_new(:status, fn -> "stopped" end)
        |> assign_new(:dirty, fn -> false end)
        |> assign_new(:ended, fn -> nil end)

      session ->
        socket
        |> assign(:name, session.name)
        |> assign(:traces, session.traces)
        |> assign(:limits, session.limits)
        |> assign_new(:status, fn -> "stopped" end)
        |> assign_new(:dirty, fn -> false end)
        |> assign_new(:ended, fn -> nil end)
    end
  end

  defp put_status(socket, status) do
    socket |> assign(:status, status) |> recompute_dirty()
  end

  defp recompute_dirty(socket) do
    a = socket.assigns
    dirty =
      a.status == "running" and
        Server.Trace.Signature.compute(a.traces, a.limits) != a.applied_sig

    assign(socket, :dirty, dirty)
  end

  defp update_traces(socket, fun) do
    case current_session(socket) do
      nil ->
        :ok

      session ->
        Config.update_session(socket.assigns.node_id, socket.assigns.session_id, %{
          traces: fun.(session.traces)
        })
    end
  end

  defp current_session(socket) do
    case Config.fetch_node(socket.assigns.node_id) do
      nil -> nil
      node -> Enum.find(node.sessions, &(&1.id == socket.assigns.session_id))
    end
  end

  defp keep(socket), do: socket.assigns.limits.keep
end
