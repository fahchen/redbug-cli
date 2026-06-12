defmodule ServerWeb.UserSocket do
  @moduledoc false

  use Musubi.Socket,
    roots: [
      Server.Stores.NodesRoot,
      Server.Stores.PresetsRoot,
      Server.Stores.SettingsRoot,
      Server.Stores.SessionRoot,
      Server.Stores.ConsoleRoot,
      Server.Stores.SnippetsRoot
    ]
end
