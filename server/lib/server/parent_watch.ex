defmodule Server.ParentWatch do
  @moduledoc """
  Ties the controller's lifetime to the process that spawned it.

  The launcher sets `REDBUG_PARENT_PID` to the TUI's pid. On a clean quit the TUI
  signals the controller (SIGTERM) itself; but if the TUI is `SIGKILL`ed or
  crashes, its signal handlers never run and the controller would orphan — and
  keep its redbug traces alive on the targets until the time/msgs limits expire.

  So poll the parent and, when it's gone, `System.stop/0` cleanly: that runs the
  supervision-tree shutdown, whose `Server.Trace.Runner.terminate/2` calls
  `:redbug.stop`, tearing the traces off the targets. No parent pid set (e.g.
  tests) → the watcher stays idle.
  """

  use GenServer
  require Logger

  @interval 3_000

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    case System.get_env("REDBUG_PARENT_PID") do
      pid when is_binary(pid) and pid != "" ->
        schedule()
        {:ok, pid}

      _ ->
        :ignore
    end
  end

  @impl true
  def handle_info(:poll, pid) do
    if alive?(pid) do
      schedule()
      {:noreply, pid}
    else
      Logger.info("redbug: parent #{pid} gone, stopping controller")
      System.stop()
      {:noreply, pid}
    end
  end

  defp schedule, do: Process.send_after(self(), :poll, @interval)

  # `kill -0` probes existence without delivering a signal: exit 0 = alive. If the
  # probe itself can't run, assume alive (never kill the controller on a flaky probe).
  defp alive?(pid) do
    case System.cmd("kill", ["-0", pid], stderr_to_stdout: true) do
      {_out, 0} -> true
      _ -> false
    end
  rescue
    _ -> true
  end
end
