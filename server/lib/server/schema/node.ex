defmodule Server.Schema.Node do
  @moduledoc """
  A target Erlang node. `status` is runtime (controller↔target distribution
  link): `"idle" | "connecting" | "connected" | "error"`. `cookie` is sent to
  the client in plaintext so it can be edited;
  treat the WS channel as trusted (local-only). `source` is `"config"` for
  user-managed nodes or `"env"` for nodes injected via `REDBUG_NODES`
  (read-only: the client only lets you add sessions under them).

  The optional `ssh_*`/`container` fields make a node SSH-reachable: when
  `ssh_host` is set, connecting opens an `ssh` tunnel to the host, discovers the
  named `container`'s distribution port, and dials the node through it (see
  `Server.SshTunnel`). Absent, the node is dialed directly.
  """

  use Musubi.State

  alias Server.Schema.Session

  state do
    field(:id, String.t())
    field(:name, String.t())
    field(:cookie, String.t())
    field(:status, String.t())
    field(:source, :config | :env)
    field(:sessions, list(Session.t()))
    field(:ssh_host, String.t() | nil)
    field(:ssh_user, String.t() | nil)
    field(:container, String.t() | nil)
  end
end
