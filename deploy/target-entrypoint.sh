#!/bin/sh
# Demo target node: a distributed Erlang node running a loop redbug can trace.
#
# Distribution is pinned to a single, fixed port so it can be reached through a
# published docker port (local sim) or an SSH -L tunnel (real kamal host). The
# node binds dist on all interfaces ({0,0,0,0}) so the published/forwarded port
# actually reaches it, while the node *name* host (DIST_HOST) is what the
# controller dials — both sides must agree on it.
set -e

# Default to the container's own IP so the controller can dial the node directly
# (OrbStack routes host -> container IP, so no port publishing or loopback alias
# is needed for local sim). Override DIST_HOST for the SSH-tunnel / kamal path.
DIST_HOST="${DIST_HOST:-$(hostname -i | awk '{print $1}')}"
DIST_PORT="${DIST_PORT:-9100}"
COOKIE="${COOKIE:-poc}"

exec erl \
  -name "target@${DIST_HOST}" \
  -setcookie "$COOKIE" \
  -kernel inet_dist_listen_min "$DIST_PORT" \
          inet_dist_listen_max "$DIST_PORT" \
          inet_dist_use_interface '{0,0,0,0}' \
  -noshell \
  -eval 'F = fun Loop() -> lists:seq(1, 5), timer:sleep(500), Loop() end, spawn(F).'
