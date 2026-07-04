defmodule Server.Stores.NodeStore do
  @moduledoc """
  Per-node child of `Server.Stores.NodesRoot`. Identity is the store path
  `(NodesRoot, NodeStore, node.id)`, so node-scoped commands
  (`editNode`/`deleteNode`/`connect`/`disconnect`/`createSession`) carry no node
  id — the target is the child they reach. Renders one `SessionItemStore` per
  session. Like the root, it only forwards intent to `Server.Config`; the config
  broadcast re-flows the fresh node down through `update/2`.
  """

  use Musubi.Store

  import Server.Stores.Payload, only: [get: 2, get: 3, put_if: 4]

  alias Server.Config
  alias Server.Stores.SessionItemStore

  attr(:node, map(), required: true)

  state do
    field(:id, String.t())
    field(:name, String.t())
    field(:cookie, String.t())
    field(:status, String.t())
    field(:source, :config | :env)
    field(:port, String.t() | nil)
    field(:ssh_host, String.t() | nil)
    field(:ssh_port, String.t() | nil)
    field(:ssh_user, String.t() | nil)
    field(:container, String.t() | nil)
    field(:error, Server.Schema.AppError.t() | nil)
    field(:sessions, list(SessionItemStore.state()))
  end

  command :editNode do
    payload do
      field(:name, String.t() | nil)
      field(:cookie, String.t() | nil)
      field(:port, String.t() | nil)
      field(:ssh_host, String.t() | nil)
      field(:ssh_port, String.t() | nil)
      field(:ssh_user, String.t() | nil)
      field(:container, String.t() | nil)
    end
  end

  command :deleteNode do
    payload do
    end
  end

  command :connect do
    payload do
    end
  end

  command :disconnect do
    payload do
    end
  end

  command :dismissError do
    payload do
    end
  end

  command :createSession do
    payload do
      field(:name, String.t())
      field(:from_preset_id, String.t() | nil)
    end
  end

  @impl true
  def mount(socket), do: {:ok, socket}

  @impl true
  def update(params, socket), do: {:ok, assign(socket, params)}

  @impl true
  def render(socket) do
    n = socket.assigns.node

    %{
      id: n.id,
      name: n.name,
      cookie: n.cookie,
      status: Map.get(n, :status, "idle"),
      source: Map.get(n, :source, "config"),
      port: Map.get(n, :port),
      ssh_host: Map.get(n, :ssh_host),
      ssh_port: Map.get(n, :ssh_port),
      ssh_user: Map.get(n, :ssh_user),
      container: Map.get(n, :container),
      error: Map.get(n, :error),
      sessions:
        for s <- n.sessions do
          child(SessionItemStore, id: s.id, session: s, node_id: n.id)
        end
    }
  end

  @impl true
  def handle_command(:editNode, payload, socket) do
    unless env?(socket) do
      attrs =
        %{}
        |> put_if(payload, "name", :name)
        |> put_if(payload, "cookie", :cookie)
        |> put_if(payload, "port", :port)
        |> put_if(payload, "ssh_host", :ssh_host)
        |> put_if(payload, "ssh_port", :ssh_port)
        |> put_if(payload, "ssh_user", :ssh_user)
        |> put_if(payload, "container", :container)

      Config.update_node(socket.assigns.node.id, attrs)
    end

    {:noreply, socket}
  end

  def handle_command(:deleteNode, _payload, socket) do
    unless env?(socket) do
      node = socket.assigns.node
      Enum.each(node.sessions, &Server.Trace.terminate(&1.id))
      Config.delete_node(node.id)
    end

    {:noreply, socket}
  end

  def handle_command(:connect, _payload, socket) do
    # async: Config drives :connecting → :connected/:error (with retry) and
    # broadcasts each step, which reflows the fresh status down through update/2.
    Config.request_connect(socket.assigns.node.id)
    {:noreply, socket}
  end

  def handle_command(:disconnect, _payload, socket) do
    Config.disconnect_node(socket.assigns.node.id)
    {:noreply, socket}
  end

  def handle_command(:dismissError, _payload, socket) do
    Config.dismiss_node_error(socket.assigns.node.id)
    {:noreply, socket}
  end

  def handle_command(:createSession, payload, socket) do
    {traces, limits} = clone_from_preset(get(payload, "from_preset_id"))

    Config.add_session(socket.assigns.node.id, %{
      name: get(payload, "name", "session"),
      traces: traces,
      limits: limits
    })

    {:noreply, socket}
  end

  def handle_command(_name, _payload, socket), do: {:noreply, socket}

  # --- helpers ---

  defp env?(socket), do: Map.get(socket.assigns.node, :source) == "env"

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
end
