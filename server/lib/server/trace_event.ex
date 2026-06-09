defmodule Server.TraceEvent do
  @moduledoc """
  One redbug trace event row: kind (call/retn/send/recv), originating pid,
  registered name, the MFA, a kind-specific info blob, and a timestamp.
  """

  use Musubi.State

  state do
    field(:id, String.t())
    field(:kind, String.t())
    field(:pid, String.t())
    field(:name, String.t())
    field(:mfa, String.t())
    field(:info, String.t())
    field(:ts, String.t())
  end
end
