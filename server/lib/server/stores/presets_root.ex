defmodule Server.Stores.PresetsRoot do
  @moduledoc "Root store for preset management (S4). Thin projection over `Server.Config`."

  use Musubi.Store, root: true

  alias Server.Config

  state do
    field(:presets, list(Server.Schema.Preset.t()))
  end

  command :createPreset do
    payload do
      field(:name, String.t())
    end
  end

  command :updatePreset do
    payload do
      field(:id, String.t())
      field(:name, String.t() | nil)
    end
  end

  command :deletePreset do
    payload do
      field(:id, String.t())
    end
  end

  command :addPresetTrace do
    payload do
      field(:preset_id, String.t())
      field(:text, String.t())
    end
  end

  command :updatePresetTrace do
    payload do
      field(:preset_id, String.t())
      field(:trace_id, String.t())
      field(:text, String.t())
    end
  end

  command :deletePresetTrace do
    payload do
      field(:preset_id, String.t())
      field(:trace_id, String.t())
    end
  end

  command :togglePresetTrace do
    payload do
      field(:preset_id, String.t())
      field(:trace_id, String.t())
    end
  end

  command :updatePresetLimits do
    payload do
      field(:preset_id, String.t())
      field(:keep, integer() | nil)
      field(:time, integer() | nil)
      field(:msgs, integer() | nil)
    end
  end

  @impl true
  def mount(_params, socket) do
    Config.subscribe()
    {:ok, assign(socket, :presets, Config.presets())}
  end

  @impl true
  def render(socket), do: %{presets: socket.assigns.presets}

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

  def handle_command(:updatePreset, payload, socket) do
    attrs = %{} |> put_if(payload, "name", :name)
    Config.update_preset(get(payload, "id"), attrs)
    {:noreply, socket}
  end

  def handle_command(:deletePreset, payload, socket) do
    Config.delete_preset(get(payload, "id"))
    {:noreply, socket}
  end

  def handle_command(:addPresetTrace, payload, socket) do
    text = get(payload, "text", "")

    if text != "" do
      rtp = %{id: Config.gen_id(), text: text, enabled: true}
      update_traces(socket, get(payload, "preset_id"), fn traces -> traces ++ [rtp] end)
    end

    {:noreply, socket}
  end

  def handle_command(:updatePresetTrace, payload, socket) do
    id = get(payload, "trace_id")
    text = get(payload, "text", "")

    update_traces(socket, get(payload, "preset_id"), fn traces ->
      map_trace(traces, id, &%{&1 | text: text})
    end)

    {:noreply, socket}
  end

  def handle_command(:deletePresetTrace, payload, socket) do
    id = get(payload, "trace_id")

    update_traces(socket, get(payload, "preset_id"), fn traces ->
      Enum.reject(traces, &(&1.id == id))
    end)

    {:noreply, socket}
  end

  def handle_command(:togglePresetTrace, payload, socket) do
    id = get(payload, "trace_id")

    update_traces(socket, get(payload, "preset_id"), fn traces ->
      map_trace(traces, id, &%{&1 | enabled: not &1.enabled})
    end)

    {:noreply, socket}
  end

  def handle_command(:updatePresetLimits, payload, socket) do
    case find_preset(socket, get(payload, "preset_id")) do
      nil ->
        :ok

      preset ->
        limits =
          preset.limits
          |> put_if(payload, "keep", :keep)
          |> put_if(payload, "time", :time)
          |> put_if(payload, "msgs", :msgs)

        Config.update_preset(preset.id, %{limits: limits})
    end

    {:noreply, socket}
  end

  def handle_command(_name, _payload, socket), do: {:noreply, socket}

  # --- helpers ---

  defp update_traces(socket, preset_id, fun) do
    case find_preset(socket, preset_id) do
      nil -> :ok
      preset -> Config.update_preset(preset.id, %{traces: fun.(preset.traces)})
    end
  end

  defp find_preset(socket, preset_id) do
    Enum.find(socket.assigns.presets, &(&1.id == preset_id))
  end

  defp map_trace(traces, id, fun) do
    Enum.map(traces, fn t -> if t.id == id, do: fun.(t), else: t end)
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
