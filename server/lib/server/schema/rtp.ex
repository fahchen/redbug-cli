defmodule Server.Schema.Rtp do
  @moduledoc "One redbug trace pattern: free-text spec plus an enabled toggle."

  use Musubi.State

  state do
    field(:id, String.t())
    field(:text, String.t())
    field(:enabled, boolean())
  end
end
