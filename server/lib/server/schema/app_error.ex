defmodule Server.Schema.AppError do
  @moduledoc """
  A user-facing error surfaced in the TUI: `message` is one glanceable line,
  `detail` is the full raw text (or `nil`) for the `e` detail overlay. Built by
  `Server.Errors.humanize/1`.
  """

  use Musubi.State

  state do
    field(:message, String.t())
    field(:detail, String.t() | nil)
  end
end
