defmodule Server.Tui do
  @moduledoc """
  Starts the Terra TUI (`Server.Tui.App`) in the controller BEAM when
  `REDBUG_TUI=terra`. Without it, the controller serves the Bun TUI over the
  WebSocket as before.

  While the TUI holds the terminal, the logger writes to `REDBUG_SERVER_LOG`
  (default `/tmp/redbug-server.log`), not to the screen. When the TUI quits,
  the VM stops.
  """

  require Logger

  @spec enabled?() :: boolean()
  def enabled?, do: System.get_env("REDBUG_TUI") == "terra"

  def child_spec(_arg) do
    %{id: __MODULE__, start: {Task, :start_link, [&run/0]}, restart: :temporary}
  end

  @spec run() :: no_return()
  def run do
    log_to_file()
    # Terra reads keys with IO.binread/2, which needs stdio in binary mode.
    :ok = :io.setopts(:standard_io, [:binary])

    status =
      try do
        {:ok, _state} =
          Terra.run(Server.Tui.App, app: [query_size: true], theme: Server.Tui.Theme.terra())

        0
      rescue
        error ->
          Logger.error("TUI crashed: " <> Exception.format(:error, error, __STACKTRACE__))
          1
      end

    System.stop(status)
    Process.sleep(:infinity)
  end

  defp log_to_file do
    file = System.get_env("REDBUG_SERVER_LOG", "/tmp/redbug-server.log")
    :ok = :logger.remove_handler(:default)

    :ok =
      :logger.add_handler(:default, :logger_std_h, %{
        config: %{file: String.to_charlist(file)},
        formatter: Logger.default_formatter()
      })
  end
end
