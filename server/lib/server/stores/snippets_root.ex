defmodule Server.Stores.SnippetsRoot do
  @moduledoc """
  Root store for the global snippet library (S9). Thin projection over
  `Server.Config`: owns only `createSnippet`; every snippet-scoped command lives
  on the child `Server.Stores.SnippetStore`. The config broadcast re-flows fresh
  snippets down to those children via their `update/2`.
  """

  use Musubi.Store, root: true

  import Server.Stores.Payload, only: [get: 3]

  alias Server.Config
  alias Server.Stores.SnippetStore

  state do
    field(:snippets, list(SnippetStore.state()))
  end

  command :createSnippet do
    payload do
      field(:name, String.t())
    end
  end

  @impl true
  def mount(_params, socket) do
    Config.subscribe()
    {:ok, assign(socket, :snippets, Config.snippets())}
  end

  @impl true
  def render(socket) do
    %{
      snippets:
        for(s <- socket.assigns.snippets, do: child(SnippetStore, id: s.id, snippet: s))
    }
  end

  @impl true
  def handle_info({:config_updated}, socket) do
    {:noreply, assign(socket, :snippets, Config.snippets())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_command(:createSnippet, payload, socket) do
    Config.add_snippet(%{name: get(payload, "name", "snippet")})
    {:noreply, socket}
  end

  def handle_command(_name, _payload, socket), do: {:noreply, socket}
end
