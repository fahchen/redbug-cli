defmodule Server.Schema.Settings do
  @moduledoc "Global UI settings: event column visibility, default sort/limits, theme."

  use Musubi.State

  alias Server.Schema.Limits

  state do
    field(:columns, %{
      name: boolean(),
      pid: boolean(),
      mfa: boolean(),
      info: boolean()
    })

    field(:default_sort, String.t())
    field(:default_limits, Limits.t())
    field(:theme, String.t())
    field(:show_hints, boolean())
    field(:console_timeout, integer())
  end
end
