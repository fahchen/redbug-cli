defmodule Server.Schema.Session do
  @moduledoc """
  A trace session under a node. `status` is runtime (stopped/running/draft),
  filled by the store; the rest is persisted config.
  """

  use Musubi.State

  alias Server.Schema.{Limits, Rtp}

  state do
    field(:id, String.t())
    field(:name, String.t())
    field(:status, String.t())
    field(:traces, list(Rtp.t()))
    field(:limits, Limits.t())
  end
end
