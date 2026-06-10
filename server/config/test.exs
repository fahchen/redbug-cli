import Config

# Endpoint must not bind the port in tests; the store/runner paths under test
# do not exercise the HTTP/WS layer.
config :server, ServerWeb.Endpoint, server: false

# Isolate persistence away from the user's real XDG config.json.
config :server, :config_path, Path.join(System.tmp_dir!(), "redbug_test_config.json")
