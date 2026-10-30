defmodule Server.PubSubTest do
  # The topics are unique to this test, so the app's Server.PubSub is shared safely.
  use ExUnit.Case, async: true

  alias Server.PubSub

  test "broadcast reaches each subscribe, and unsubscribe drops all of them" do
    topic = "pub_sub_test:#{System.unique_integer([:positive])}"

    :ok = PubSub.subscribe(topic)
    :ok = PubSub.subscribe(topic)
    :ok = PubSub.broadcast(topic, :hello)
    assert_received :hello
    assert_received :hello

    :ok = PubSub.unsubscribe(topic)
    :ok = PubSub.broadcast(topic, :again)
    refute_received :again
  end

  test "broadcast to a topic with no subscriber is :ok" do
    assert :ok = PubSub.broadcast("pub_sub_test:none", :x)
  end
end
