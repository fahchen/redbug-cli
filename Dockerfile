# Self-contained server release for the sidecar deployment.
# Build context = repo root:  docker build -t redbug-server .
# Erlang distribution to the target app node stays inside the app's network;
# only the WS port (REDBUG_PORT) is exposed for the local TUI.

ARG ELIXIR_IMAGE=hexpm/elixir:1.19.5-erlang-28.3-debian-bookworm-20260518-slim

FROM ${ELIXIR_IMAGE} AS build

RUN apt-get update -y && apt-get install -y build-essential git \
  && rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

WORKDIR /app/server
COPY server/mix.exs server/mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# musubi_ts codegen writes to ../tui/src/generated during compile; give it a home.
RUN mkdir -p /app/tui/src/generated
COPY server/config ./config
COPY server/lib ./lib
RUN mix release

FROM debian:bookworm-slim AS app

RUN apt-get update -y \
  && apt-get install -y libstdc++6 libncurses6 libssl3 ca-certificates openssl locales \
  && rm -rf /var/lib/apt/lists/*
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

WORKDIR /app
COPY --from=build /app/server/_build/prod/rel/server ./

# Bind to all interfaces inside the container; fixed WS port so kamal can publish it.
# Distribution identity (RELEASE_NODE/RELEASE_COOKIE) comes from the deploy env.
ENV REDBUG_IP=0.0.0.0 \
    REDBUG_PORT=4010 \
    RELEASE_DISTRIBUTION=name

EXPOSE 4010
CMD ["bin/server", "start"]
