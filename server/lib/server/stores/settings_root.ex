defmodule Server.Stores.SettingsRoot do
  @moduledoc "Root store for global settings (S6). Thin projection over `Server.Config`."

  use Musubi.Store, root: true

  alias Server.Config

  state do
    field(:settings, Server.Schema.Settings.t())
  end

  command :updateSettings do
    payload do
      field(:theme, String.t() | nil)
      field(:default_sort, String.t() | nil)
      field(:columns, map() | nil)
      field(:default_limits, map() | nil)
      field(:show_hints, boolean() | nil)
    end
  end

  @impl true
  def mount(_params, socket) do
    Config.subscribe()
    {:ok, assign(socket, :settings, Config.settings())}
  end

  @impl true
  def render(socket), do: %{settings: socket.assigns.settings}

  @impl true
  def handle_info({:config_updated}, socket) do
    {:noreply, assign(socket, :settings, Config.settings())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_command(:updateSettings, payload, socket) do
    Config.update_settings(normalize(payload))
    {:noreply, socket}
  end

  def handle_command(_name, _payload, socket), do: {:noreply, socket}

  # Client sends string-keyed partial settings; convert top-level known keys to atoms.
  defp normalize(payload) do
    Enum.reduce(payload, %{}, fn {k, v}, acc ->
      case to_known_key(k) do
        nil -> acc
        key -> Map.put(acc, key, normalize_value(key, v))
      end
    end)
  end

  defp normalize_value(:columns, cols) when is_map(cols) do
    for {k, v} <- cols, key = column_key(k), key != nil, into: %{}, do: {key, v}
  end

  defp normalize_value(_key, v), do: v

  defp to_known_key(k) when is_atom(k), do: to_known_key(Atom.to_string(k))

  defp to_known_key(k) when is_binary(k) do
    case k do
      "columns" -> :columns
      "default_sort" -> :default_sort
      "default_limits" -> :default_limits
      "theme" -> :theme
      "show_hints" -> :show_hints
      _ -> nil
    end
  end

  defp column_key(k) when is_atom(k), do: column_key(Atom.to_string(k))

  defp column_key(k) when is_binary(k) do
    case k do
      "name" -> :name
      "pid" -> :pid
      "mfa" -> :mfa
      "info" -> :info
      _ -> nil
    end
  end
end
