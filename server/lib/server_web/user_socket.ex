defmodule ServerWeb.UserSocket do
  @moduledoc false

  use Musubi.Socket,
    roots: [
      Server.Stores.TraceStore
    ]
end
