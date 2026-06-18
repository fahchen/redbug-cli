defmodule Server.Schema.Node do
  @moduledoc """
  A target Erlang node. `connected` is runtime (controller↔target distribution
  link). `cookie` is sent to the client in plaintext so it can be edited;
  treat the WS channel as trusted (local-only). `source` is `"config"` for
  user-managed nodes or `"env"` for nodes injected via `REDBUG_NODES`
  (read-only: the client only lets you add sessions under them).
  """

  use Musubi.State

  alias Server.Schema.Session

  state do
    field(:id, String.t())
    field(:name, String.t())
    field(:cookie, String.t())
    field(:connected, boolean())
    field(:source, String.t())
    field(:sessions, list(Session.t()))
  end
end
