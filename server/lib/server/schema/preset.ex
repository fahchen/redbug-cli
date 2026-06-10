defmodule Server.Schema.Preset do
  @moduledoc "A reusable trace template (traces + limits), cloned into sessions."

  use Musubi.State

  alias Server.Schema.{Limits, Rtp}

  state do
    field(:id, String.t())
    field(:name, String.t())
    field(:traces, list(Rtp.t()))
    field(:limits, Limits.t())
  end
end
