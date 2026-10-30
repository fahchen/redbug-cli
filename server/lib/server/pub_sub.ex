defmodule Server.PubSub do
  @moduledoc """
  Local topic broadcasts from the controller processes (`Server.Config`, the
  trace runners, and the console runners) to the TUI bridge. A process that
  subscribes gets each message of the topic until it unsubscribes or exits.

  It is a `Registry` with duplicate keys: the topic is the key, and each
  subscriber registers once for each subscribe.
  """

  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(_arg), do: Registry.child_spec(keys: :duplicate, name: __MODULE__)

  @spec subscribe(String.t()) :: :ok
  def subscribe(topic) do
    {:ok, _owner} = Registry.register(__MODULE__, topic, nil)
    :ok
  end

  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(topic), do: Registry.unregister(__MODULE__, topic)

  @spec broadcast(String.t(), term()) :: :ok
  def broadcast(topic, message) do
    Registry.dispatch(__MODULE__, topic, fn entries ->
      for {pid, _value} <- entries, do: send(pid, message)
    end)
  end
end
