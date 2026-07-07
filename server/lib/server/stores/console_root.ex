defmodule Server.Stores.ConsoleRoot do
  @moduledoc """
  Root store for one session's Console tab (S8).

  Mounted with `node_id`/`session_id`. Owns the live execution history (a
  server-held, capped stream that survives ws reconnects) plus a read-only view
  of the global snippet library used to seed new executions. Execution
  side-effects forward to `Server.Remote`; the snippet library comes from
  `Server.Config`. The store itself never spawns remote work.
  """

  use Musubi.Store, root: true

  import Server.Stores.Payload, only: [get: 2, get: 3]

  alias Server.{Config, Remote}

  state do
    field(:node_id, String.t())
    field(:session_id, String.t())
    field(:snippets, list(Server.Schema.Snippet.t()))
    stream(:history, Server.Schema.ConsoleExec.t(), item_key: & &1.id, limit: 200)
  end

  command :run do
    payload do
      field(:code, String.t())
      field(:name, String.t() | nil)
    end
  end

  command :stopExecution do
    payload do
      field(:id, String.t())
    end
  end

  command :clearHistory do
    payload do
    end
  end

  command :deleteExec do
    payload do
      field(:id, String.t())
    end
  end

  command :connect do
    payload do
    end
  end

  @impl true
  def mount(params, socket) do
    node_id = Map.get(params, "node_id")
    session_id = Map.get(params, "session_id")

    Config.subscribe()
    Remote.subscribe(session_id)

    snap = Remote.snapshot(session_id)

    socket =
      socket
      |> assign(:node_id, node_id)
      |> assign(:session_id, session_id)
      |> assign(:snippets, Config.snippets())
      |> stream(:history, snap.history, reset: true)

    {:ok, socket}
  end

  @impl true
  def render(socket) do
    a = socket.assigns

    %{
      node_id: a.node_id,
      session_id: a.session_id,
      snippets: a.snippets,
      history: stream(:history)
    }
  end

  @impl true
  def handle_info({:config_updated}, socket) do
    {:noreply, assign(socket, :snippets, Config.snippets())}
  end

  def handle_info({:console_insert, entry}, socket) do
    {:noreply, stream_insert(socket, :history, entry, at: 0, limit: 200)}
  end

  def handle_info({:console_update, entry}, socket) do
    # Same item_key → client upserts in place; at: 0 keeps the row at the top
    # (stream_insert defaults to at: -1, which would move it to the bottom).
    {:noreply, stream_insert(socket, :history, entry, at: 0, limit: 200)}
  end

  def handle_info({:console_reset}, socket) do
    {:noreply, stream(socket, :history, [], reset: true)}
  end

  def handle_info({:console_delete, exec_id}, socket) do
    {:noreply, stream_delete(socket, :history, exec_id)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_command(:run, payload, socket) do
    code = get(payload, "code", "")

    if String.trim(code) == "" do
      {:noreply, socket}
    else
      Remote.run(socket.assigns.node_id, socket.assigns.session_id, code, get(payload, "name"))
      {:noreply, socket}
    end
  end

  def handle_command(:stopExecution, payload, socket) do
    Remote.stop(socket.assigns.session_id, get(payload, "id"))
    {:noreply, socket}
  end

  def handle_command(:clearHistory, _payload, socket) do
    Remote.clear(socket.assigns.session_id)
    {:noreply, socket}
  end

  def handle_command(:deleteExec, payload, socket) do
    Remote.delete_exec(socket.assigns.session_id, get(payload, "id"))
    {:noreply, socket}
  end

  def handle_command(:connect, _payload, socket) do
    Config.connect_node(socket.assigns.node_id)
    {:noreply, socket}
  end

  def handle_command(_name, _payload, socket), do: {:noreply, socket}
end
