defmodule Server.Tui.Bridge do
  @moduledoc """
  Sends the controller state to the Terra runtime of the TUI. It subscribes to
  the config broadcasts and, for each burst of `{:config_updated}` messages,
  casts one `{:event, {:nodes, nodes, settings}}` to the runtime. It stops when
  the runtime stops.
  """

  alias Server.Config

  @doc """
  Starts the bridge for `runtime`. With `query_size: true`, it first asks the
  runtime to read the terminal size, which gives the app a `{:resize, w, h}`.
  """
  @spec start_link(pid(), keyword()) :: pid()
  def start_link(runtime, opts) do
    spawn_link(fn ->
      Process.monitor(runtime)
      Config.subscribe()
      # The runtime handles this call after its init/1, which starts the bridge.
      if Keyword.fetch!(opts, :query_size), do: Terra.Runtime.resize(runtime)
      loop(runtime)
    end)
  end

  defp loop(runtime) do
    receive do
      {:config_updated} ->
        flush()
        GenServer.cast(runtime, {:event, {:nodes, Config.nodes(), Config.settings()}})
        loop(runtime)

      {:DOWN, _ref, :process, ^runtime, _reason} ->
        :ok

      _other ->
        loop(runtime)
    end
  end

  # One batch for each burst: drop the updates that are already queued.
  defp flush do
    receive do
      {:config_updated} -> flush()
    after
      0 -> :ok
    end
  end
end
