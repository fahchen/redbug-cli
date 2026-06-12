defmodule Server.Schema.Snippet do
  @moduledoc "A global, node-agnostic reusable code snippet, cloned into the Console."

  use Musubi.State

  state do
    field(:id, String.t())
    field(:name, String.t())
    field(:code, String.t())
  end
end
