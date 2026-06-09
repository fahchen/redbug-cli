defmodule ServerWeb.Endpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :server

  socket("/socket", ServerWeb.UserSocket,
    websocket: true,
    longpoll: false
  )

  plug(Plug.RequestId)
end
