defmodule Server.Stores.Payload do
  @moduledoc """
  Helpers shared by the root stores for working with command payloads and
  trace lists. Command payloads arrive string-keyed off the wire, so `get/3`
  accepts either string or atom keys; `put_if/4` builds sparse attr maps that
  forward only the fields a client actually sent.
  """

  @doc "Fetch `key` from a payload, tolerating string- or atom-keyed maps."
  def get(payload, key, default \\ nil) do
    Map.get(payload, key, Map.get(payload, String.to_atom(key), default))
  end

  @doc "Put `target => value` into `map` only when `key` is present in `payload`."
  def put_if(map, payload, key, target) do
    case get(payload, key) do
      nil -> map
      value -> Map.put(map, target, value)
    end
  end

  @doc "Apply `fun` to the trace whose `id` matches, leaving the rest untouched."
  def map_trace(traces, id, fun) do
    Enum.map(traces, fn t -> if t.id == id, do: fun.(t), else: t end)
  end
end
