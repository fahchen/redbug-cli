import Config

config :phoenix, :json_library, Jason

config :musubi, :ts_codegen_output_path, "../tui/src/generated/musubi.d.ts"

config :server, ServerWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  pubsub_server: Server.PubSub,
  secret_key_base: "redbug_cli_secret_key_base_for_poc_only_0123456789abcdefghijkl",
  server: true,
  http: [ip: {127, 0, 0, 1}, port: 0]

if config_env() == :dev do
  import_config "dev.exs"
end

if config_env() == :test do
  import_config "test.exs"
end
