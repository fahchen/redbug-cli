import Config

# The tests drive the TUI headless with Terra.Test, so the app does not start
# Server.Tui (it would take the terminal of mix test).
config :server, :tui, false

# Isolate persistence away from the user's real XDG config.json.
config :server, :config_path, Path.join(System.tmp_dir!(), "redbug_test_config.json")
