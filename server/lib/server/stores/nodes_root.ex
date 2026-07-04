defmodule Server.Stores.NodesRoot do
  @moduledoc """
  Root store for the S1 node▸session tree. Thin projection over `Server.Config`:
  reads the ETS-backed node list on mount, subscribes to config broadcasts, and
  re-reads on `{:config_updated}`. Owns only `createNode` (the one mutation with
  no node to target); every node/session-scoped command lives on the child
  `Server.Stores.NodeStore` / `Server.Stores.SessionItemStore`. The broadcast
  re-render flows fresh node maps down to those children via their `update/2`.
  """

  use Musubi.Store, root: true

  import Server.Stores.Payload, only: [get: 3]

  alias Server.Config
  alias Server.Stores.NodeStore

  state do
    field(:nodes, list(NodeStore.state()))
  end

  command :createNode do
    payload do
      field(:name, String.t())
      field(:cookie, String.t())
      field(:port, String.t() | nil)
      field(:ssh_host, String.t() | nil)
      field(:ssh_port, String.t() | nil)
      field(:ssh_user, String.t() | nil)
      field(:container, String.t() | nil)
    end
  end

  @impl true
  def mount(_params, socket) do
    Config.subscribe()
    {:ok, assign(socket, :nodes, Config.nodes())}
  end

  @impl true
  def render(socket) do
    %{nodes: for(node <- socket.assigns.nodes, do: child(NodeStore, id: node.id, node: node))}
  end

  @impl true
  def handle_info({:config_updated}, socket) do
    {:noreply, assign(socket, :nodes, Config.nodes())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_command(:createNode, payload, socket) do
    # env-injected nodes are the whole list in env mode; manual creation is off.
    unless Config.env_mode?() do
      Config.add_node(%{
        name: get(payload, "name", ""),
        cookie: get(payload, "cookie", ""),
        port: get(payload, "port", nil),
        ssh_host: get(payload, "ssh_host", nil),
        ssh_port: get(payload, "ssh_port", nil),
        ssh_user: get(payload, "ssh_user", nil),
        container: get(payload, "container", nil)
      })
    end

    {:noreply, socket}
  end

  def handle_command(_name, _payload, socket), do: {:noreply, socket}
end
