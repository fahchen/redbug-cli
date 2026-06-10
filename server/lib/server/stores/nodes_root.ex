defmodule Server.Stores.NodesRoot do
  @moduledoc """
  Root store for the S1 node▸session tree. Thin projection over `Server.Config`:
  reads the ETS-backed node list on mount, subscribes to config broadcasts, and
  re-reads on `{:config_updated}`. Commands forward intent to `Server.Config`;
  this store never touches distribution or persistence directly.
  """

  use Musubi.Store, root: true

  alias Server.Config

  state do
    field(:nodes, list(Server.Schema.Node.t()))
  end

  command :createNode do
    payload do
      field(:name, String.t())
      field(:cookie, String.t())
    end
  end

  command :editNode do
    payload do
      field(:id, String.t())
      field(:name, String.t() | nil)
      field(:cookie, String.t() | nil)
    end
  end

  command :deleteNode do
    payload do
      field(:id, String.t())
    end
  end

  command :createSession do
    payload do
      field(:node_id, String.t())
      field(:name, String.t())
      field(:from_preset_id, String.t() | nil)
    end
  end

  command :deleteSession do
    payload do
      field(:node_id, String.t())
      field(:session_id, String.t())
    end
  end

  command :connect do
    payload do
      field(:node_id, String.t())
    end
  end

  command :disconnect do
    payload do
      field(:node_id, String.t())
    end
  end

  @impl true
  def mount(_params, socket) do
    Config.subscribe()
    {:ok, assign(socket, :nodes, Config.nodes())}
  end

  @impl true
  def render(socket), do: %{nodes: socket.assigns.nodes}

  @impl true
  def handle_info({:config_updated}, socket) do
    {:noreply, assign(socket, :nodes, Config.nodes())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_command(:createNode, payload, socket) do
    Config.add_node(%{name: get(payload, "name", ""), cookie: get(payload, "cookie", "")})
    {:noreply, socket}
  end

  def handle_command(:editNode, payload, socket) do
    attrs =
      %{}
      |> put_if(payload, "name", :name)
      |> put_if(payload, "cookie", :cookie)

    Config.update_node(get(payload, "id"), attrs)
    {:noreply, socket}
  end

  def handle_command(:deleteNode, payload, socket) do
    id = get(payload, "id")

    case Config.fetch_node(id) do
      nil -> :ok
      node -> Enum.each(node.sessions, &Server.Trace.terminate(&1.id))
    end

    Config.delete_node(id)
    {:noreply, socket}
  end

  def handle_command(:createSession, payload, socket) do
    {traces, limits} = clone_from_preset(get(payload, "from_preset_id"))

    Config.add_session(get(payload, "node_id"), %{
      name: get(payload, "name", "session"),
      traces: traces,
      limits: limits
    })

    {:noreply, socket}
  end

  def handle_command(:deleteSession, payload, socket) do
    session_id = get(payload, "session_id")
    Server.Trace.terminate(session_id)
    Config.delete_session(get(payload, "node_id"), session_id)
    {:noreply, socket}
  end

  def handle_command(:connect, payload, socket) do
    Config.connect_node(get(payload, "node_id"))
    {:noreply, socket}
  end

  def handle_command(:disconnect, payload, socket) do
    Config.disconnect_node(get(payload, "node_id"))
    {:noreply, socket}
  end

  def handle_command(_name, _payload, socket), do: {:noreply, socket}

  # --- helpers ---

  defp clone_from_preset(nil), do: {[], Config.settings().default_limits}

  defp clone_from_preset(preset_id) do
    case Enum.find(Config.presets(), &(&1.id == preset_id)) do
      nil ->
        {[], Config.settings().default_limits}

      preset ->
        traces = Enum.map(preset.traces, fn t -> %{t | id: Config.gen_id()} end)
        {traces, preset.limits}
    end
  end

  defp get(payload, key, default \\ nil) do
    Map.get(payload, key, Map.get(payload, String.to_atom(key), default))
  end

  defp put_if(attrs, payload, key, target) do
    case get(payload, key) do
      nil -> attrs
      value -> Map.put(attrs, target, value)
    end
  end
end
