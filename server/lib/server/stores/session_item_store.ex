defmodule Server.Stores.SessionItemStore do
  @moduledoc """
  Per-session child of `Server.Stores.NodeStore`. Identity is the store path
  `(node, NodeStore, session.id)`, so commands carry no ids — the session a
  command targets is the child it was dispatched to. Owns the one session-level
  mutation (`deleteSession`); display fields mirror the `:session` attr supplied
  by the parent on every render.
  """

  use Musubi.Store

  alias Server.{Config, Trace}

  attr(:session, map(), required: true)
  attr(:node_id, String.t(), required: true)

  state do
    field(:id, String.t())
    field(:name, String.t())
    field(:status, String.t())
    field(:traces, list(Server.Schema.Rtp.t()))
    field(:limits, Server.Schema.Limits.t())
  end

  command :renameSession do
    payload do
      field(:name, String.t())
    end
  end

  command :deleteSession do
    payload do
    end
  end

  @impl true
  def mount(socket), do: {:ok, socket}

  @impl true
  def update(params, socket), do: {:ok, assign(socket, params)}

  @impl true
  def render(socket) do
    s = socket.assigns.session

    %{
      id: s.id,
      name: s.name,
      status: s.status,
      traces: s.traces,
      limits: s.limits
    }
  end

  @impl true
  def handle_command(:renameSession, payload, socket) do
    name = Server.Stores.Payload.get(payload, "name", "")
    if name != "" do
      Config.update_session(socket.assigns.node_id, socket.assigns.session.id, %{name: name})
    end
    {:noreply, socket}
  end

  def handle_command(:deleteSession, _payload, socket) do
    s = socket.assigns.session
    Trace.terminate(s.id)
    Config.delete_session(socket.assigns.node_id, s.id)
    {:noreply, socket}
  end

  def handle_command(_name, _payload, socket), do: {:noreply, socket}
end
