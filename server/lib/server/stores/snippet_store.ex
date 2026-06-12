defmodule Server.Stores.SnippetStore do
  @moduledoc """
  Per-snippet child of `Server.Stores.SnippetsRoot`. Identity is the store path
  `(SnippetsRoot, SnippetStore, snippet.id)`, so snippet-scoped commands drop
  the `snippet_id` — the target is the child reached. Mutations forward to
  `Server.Config`; the broadcast re-flows the fresh snippet via `update/2`.

  Code is auto-formatted (`Server.Code.Format`) whenever it is saved or the
  explicit `formatSnippet` command runs.
  """

  use Musubi.Store

  import Server.Stores.Payload, only: [get: 3, put_if: 4]

  alias Server.Code.Format
  alias Server.Config

  attr(:snippet, map(), required: true)

  state do
    field(:id, String.t())
    field(:name, String.t())
    field(:code, String.t())
  end

  command :updateSnippet do
    payload do
      field(:code, String.t())
    end
  end

  command :renameSnippet do
    payload do
      field(:name, String.t())
    end
  end

  command :formatSnippet do
    payload do
    end
  end

  command :deleteSnippet do
    payload do
    end
  end

  @impl true
  def mount(socket), do: {:ok, socket}

  @impl true
  def update(params, socket), do: {:ok, assign(socket, params)}

  @impl true
  def render(socket) do
    s = socket.assigns.snippet
    %{id: s.id, name: s.name, code: s.code}
  end

  @impl true
  def handle_command(:updateSnippet, payload, socket) do
    save_formatted(socket, get(payload, "code", ""))
    {:noreply, socket}
  end

  def handle_command(:renameSnippet, payload, socket) do
    attrs = %{} |> put_if(payload, "name", :name)
    Config.update_snippet(socket.assigns.snippet.id, attrs)
    {:noreply, socket}
  end

  def handle_command(:formatSnippet, _payload, socket) do
    save_formatted(socket, socket.assigns.snippet.code)
    {:noreply, socket}
  end

  def handle_command(:deleteSnippet, _payload, socket) do
    Config.delete_snippet(socket.assigns.snippet.id)
    {:noreply, socket}
  end

  def handle_command(_name, _payload, socket), do: {:noreply, socket}

  defp save_formatted(socket, code) do
    Config.update_snippet(socket.assigns.snippet.id, %{code: Format.run(code)})
  end
end
