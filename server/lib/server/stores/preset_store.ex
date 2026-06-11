defmodule Server.Stores.PresetStore do
  @moduledoc """
  Per-preset child of `Server.Stores.PresetsRoot`. Identity is the store path
  `(PresetsRoot, PresetStore, preset.id)`, so preset-scoped commands drop the
  `preset_id` — the target is the child reached. Traces stay plain state, keyed
  by `trace_id` in the payload (they have no per-trace store). Mutations forward
  to `Server.Config`; the broadcast re-flows the fresh preset via `update/2`.
  """

  use Musubi.Store

  import Server.Stores.Payload, only: [get: 2, get: 3, put_if: 4, map_trace: 3]

  alias Server.Config

  attr(:preset, map(), required: true)

  state do
    field(:id, String.t())
    field(:name, String.t())
    field(:traces, list(Server.Schema.Rtp.t()))
    field(:limits, Server.Schema.Limits.t())
  end

  command :updatePreset do
    payload do
      field(:name, String.t() | nil)
    end
  end

  command :deletePreset do
    payload do
    end
  end

  command :addPresetTrace do
    payload do
      field(:text, String.t())
    end
  end

  command :updatePresetTrace do
    payload do
      field(:trace_id, String.t())
      field(:text, String.t())
    end
  end

  command :deletePresetTrace do
    payload do
      field(:trace_id, String.t())
    end
  end

  command :togglePresetTrace do
    payload do
      field(:trace_id, String.t())
    end
  end

  command :updatePresetLimits do
    payload do
      field(:keep, integer() | nil)
      field(:time, integer() | nil)
      field(:msgs, integer() | nil)
    end
  end

  @impl true
  def mount(socket), do: {:ok, socket}

  @impl true
  def update(params, socket), do: {:ok, assign(socket, params)}

  @impl true
  def render(socket) do
    p = socket.assigns.preset

    %{
      id: p.id,
      name: p.name,
      traces: p.traces,
      limits: p.limits
    }
  end

  @impl true
  def handle_command(:updatePreset, payload, socket) do
    attrs = %{} |> put_if(payload, "name", :name)
    Config.update_preset(socket.assigns.preset.id, attrs)
    {:noreply, socket}
  end

  def handle_command(:deletePreset, _payload, socket) do
    Config.delete_preset(socket.assigns.preset.id)
    {:noreply, socket}
  end

  def handle_command(:addPresetTrace, payload, socket) do
    text = get(payload, "text", "")

    if text != "" do
      rtp = %{id: Config.gen_id(), text: text, enabled: true}
      update_traces(socket, fn traces -> traces ++ [rtp] end)
    end

    {:noreply, socket}
  end

  def handle_command(:updatePresetTrace, payload, socket) do
    id = get(payload, "trace_id")
    text = get(payload, "text", "")
    update_traces(socket, fn traces -> map_trace(traces, id, &%{&1 | text: text}) end)
    {:noreply, socket}
  end

  def handle_command(:deletePresetTrace, payload, socket) do
    id = get(payload, "trace_id")
    update_traces(socket, fn traces -> Enum.reject(traces, &(&1.id == id)) end)
    {:noreply, socket}
  end

  def handle_command(:togglePresetTrace, payload, socket) do
    id = get(payload, "trace_id")
    update_traces(socket, fn traces -> map_trace(traces, id, &%{&1 | enabled: not &1.enabled}) end)
    {:noreply, socket}
  end

  def handle_command(:updatePresetLimits, payload, socket) do
    limits =
      socket.assigns.preset.limits
      |> put_if(payload, "keep", :keep)
      |> put_if(payload, "time", :time)
      |> put_if(payload, "msgs", :msgs)

    Config.update_preset(socket.assigns.preset.id, %{limits: limits})
    {:noreply, socket}
  end

  def handle_command(_name, _payload, socket), do: {:noreply, socket}

  # --- helpers ---

  defp update_traces(socket, fun) do
    preset = socket.assigns.preset
    Config.update_preset(preset.id, %{traces: fun.(preset.traces)})
  end
end
