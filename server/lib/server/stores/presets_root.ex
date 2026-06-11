defmodule Server.Stores.PresetsRoot do
  @moduledoc """
  Root store for preset management (S4). Thin projection over `Server.Config`:
  owns only `createPreset`; every preset-scoped command lives on the child
  `Server.Stores.PresetStore`. The config broadcast re-flows fresh presets down
  to those children via their `update/2`.
  """

  use Musubi.Store, root: true

  import Server.Stores.Payload, only: [get: 3]

  alias Server.Config
  alias Server.Stores.PresetStore

  state do
    field(:presets, list(PresetStore.state()))
  end

  command :createPreset do
    payload do
      field(:name, String.t())
    end
  end

  @impl true
  def mount(_params, socket) do
    Config.subscribe()
    {:ok, assign(socket, :presets, Config.presets())}
  end

  @impl true
  def render(socket) do
    %{presets: for(preset <- socket.assigns.presets, do: child(PresetStore, id: preset.id, preset: preset))}
  end

  @impl true
  def handle_info({:config_updated}, socket) do
    {:noreply, assign(socket, :presets, Config.presets())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_command(:createPreset, payload, socket) do
    Config.add_preset(%{name: get(payload, "name", "preset")})
    {:noreply, socket}
  end

  def handle_command(_name, _payload, socket), do: {:noreply, socket}
end
