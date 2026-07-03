defmodule Server.SshTunnelTest do
  # Pure parsing/validation used to turn `docker inspect` + `epmd -names` output
  # into a dial target. The ssh/tunnel side is exercised by the machine e2e.
  use ExUnit.Case, async: true

  alias Server.SshTunnel

  describe "safe_container/1" do
    test "accepts kamal-style names and container ids" do
      assert SshTunnel.safe_container("my-app") == {:ok, "my-app"}
      assert SshTunnel.safe_container("web_1.2") == {:ok, "web_1.2"}
    end

    test "rejects shell metacharacters (no command injection into discovery)" do
      assert SshTunnel.safe_container("app; rm -rf /") == {:error, :bad_container}
      assert SshTunnel.safe_container("$(whoami)") == {:error, :bad_container}
      assert SshTunnel.safe_container("a b") == {:error, :bad_container}
    end

    test "nil / non-binary is a missing container, not a bad one" do
      assert SshTunnel.safe_container(nil) == {:error, :no_container}
    end
  end

  test "parse_ip pulls the first dotted-quad from mixed output" do
    out = "172.18.0.4\nepmd: up and running on port 4369 with data:\nname app at port 44001\n"
    assert SshTunnel.parse_ip(out) == {:ok, "172.18.0.4"}
    assert SshTunnel.parse_ip("no address here") == {:error, :no_ip}
  end

  test "parse_port reads the epmd node port" do
    out = "name app at port 44001\n"
    assert SshTunnel.parse_port(out) == {:ok, 44001}
    assert SshTunnel.parse_port("epmd: up and running on port 4369 with data:\n") ==
             {:error, :no_port}
  end

  test "parse_sname / host / cookie pull the sname atom parts from discovery output" do
    out = """
    172.18.0.4
    epmd: up and running on port 4369 with data:
    name muku at port 35017
    HOST=178
    COOKIE=VJ26O3ABC====
    """

    assert SshTunnel.parse_sname(out) == "muku"
    assert SshTunnel.parse_host(out) == "178"
    assert SshTunnel.parse_cookie(out) == "VJ26O3ABC===="
    # a full name in the epmd line still yields just the short name
    assert SshTunnel.parse_sname("name app at port 9100") == "app"
    # missing lines → nil, not a crash
    assert SshTunnel.parse_host("no host line") == nil
    assert SshTunnel.parse_cookie("no cookie line") == nil
  end
end
