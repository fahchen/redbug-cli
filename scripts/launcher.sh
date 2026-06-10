#!/usr/bin/env sh
# redbug launcher: start the self-contained server release on a free port, then
# run the TUI binary pointed at that port. Stops the server when the TUI exits.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
server_bin="$here/server/bin/server"
tui_bin="$here/redbug-tui"

cookie="${RB_COOKIE:-rbtest}"
port_file=$(mktemp -u "${TMPDIR:-/tmp}/redbug.port.XXXXXX")

export RELEASE_DISTRIBUTION=name
export RELEASE_NODE="${REDBUG_NODE:-redbug_controller@127.0.0.1}"
export RELEASE_COOKIE="$cookie"
export REDBUG_PORT_FILE="$port_file"

cleanup() {
  "$server_bin" stop >/dev/null 2>&1 || true
  rm -f "$port_file"
}
trap cleanup EXIT INT TERM

"$server_bin" daemon

i=0
while [ ! -f "$port_file" ]; do
  i=$((i + 1))
  [ "$i" -gt 100 ] && { echo "server did not announce a port" >&2; exit 1; }
  sleep 0.2
done
port=$(cat "$port_file")

REDBUG_PORT="$port" "$tui_bin"
