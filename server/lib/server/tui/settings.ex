defmodule Server.Tui.Settings do
  @moduledoc false
  # Stub: the owner of this file replaces it (fahchen/pbeam#1425).

  alias Server.Tui.Ui

  def new, do: %{}
  def key(:esc, _s), do: :close
  def key(_key, s), do: {:ok, s}
  def view(_s, width, height), do: Ui.page(width, height, "Settings", [])
end
