#!/usr/bin/env bash
# Starts a local soketi (Pusher protocol) server, runs the integration tests
# against it and always stops the server again.
#
# Usage: integration_test/run.sh [device-id]   (default: macos)
#   DEVICE=<id>   same as the argument
#   NODE18=<path> path to a Node 18 `node` binary (soketi needs Node 18)
#   USE_DOCKER=1  run soketi from docker instead of Node
#   PUSHER_HOST   host the *app* uses to reach soketi (default: 127.0.0.1,
#                 or 10.0.2.2 for Android emulators)
#   PORT          soketi port (default 6001)
#   SOKETI_DIR    where soketi 1.6.1 is installed (default ~/.cache/pusher_client_soketi)
#   SOKETI_STOCK=1 do not patch soketi (see below)
#
# soketi 1.6.1 sends pusher_internal:subscription_succeeded for public/private
# channels without the "data" field that Pusher always includes ("{}"). That
# makes PusherSwift (iOS/macOS) drop the event and crashes pusher-java on
# private-encrypted channels (NPE). Unless SOKETI_STOCK=1, this script patches
# its installed copy to send data:"{}" so the tests exercise the plugin and not
# that server quirk. (Not possible with USE_DOCKER=1.)
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE="${1:-${DEVICE:-macos}}"
PORT="${PORT:-6001}"

# Refuse to run against a server we did not start (results would be meaningless).
if curl -fsS "http://127.0.0.1:${PORT}/" >/dev/null 2>&1 || lsof -iTCP:"${PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port ${PORT} is already in use. Stop the process listening on it (or set PORT=...) and retry." >&2
  exit 1
fi
APP_ID=app-id
APP_KEY=app-key
APP_SECRET=app-secret

case "$DEVICE" in
  emulator-*) DEFAULT_HOST=10.0.2.2 ;;
  *) DEFAULT_HOST=127.0.0.1 ;;
esac
PUSHER_HOST="${PUSHER_HOST:-$DEFAULT_HOST}"

SOKETI_PID=""
DOCKER_NAME=""
cleanup() {
  if [[ -n "$SOKETI_PID" ]]; then
    kill "$SOKETI_PID" 2>/dev/null || true
    wait "$SOKETI_PID" 2>/dev/null || true
  fi
  if [[ -n "$DOCKER_NAME" ]]; then
    docker rm -f "$DOCKER_NAME" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

export SOKETI_DEFAULT_APP_ID="$APP_ID"
export SOKETI_DEFAULT_APP_KEY="$APP_KEY"
export SOKETI_DEFAULT_APP_SECRET="$APP_SECRET"
export SOKETI_DEFAULT_APP_ENABLE_CLIENT_MESSAGES=true
export SOKETI_PORT="$PORT"

LOG="$(mktemp -t soketi.XXXXXX)"

if [[ "${USE_DOCKER:-}" == "1" ]]; then
  command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }
  DOCKER_NAME="soketi-pusher-client-$$"
  docker run -d --rm --name "$DOCKER_NAME" -p "$PORT:6001" \
    -e SOKETI_DEFAULT_APP_ID -e SOKETI_DEFAULT_APP_KEY \
    -e SOKETI_DEFAULT_APP_SECRET -e SOKETI_DEFAULT_APP_ENABLE_CLIENT_MESSAGES \
    quay.io/soketi/soketi:1.6-16-alpine >/dev/null
else
  # soketi's uWebSockets.js has no binary for Node >= 20, so it needs Node 18.
  if [[ -z "${NODE18:-}" ]]; then
    for candidate in "$HOME"/.nvm/versions/node/v18.*/bin/node; do
      [[ -x "$candidate" ]] && NODE18="$candidate"
    done
  fi
  if [[ -z "${NODE18:-}" || ! -x "${NODE18}" ]]; then
    cat >&2 <<MSG
Node 18 not found. soketi 1.6.1 needs Node 18 (uWebSockets.js has no Node 20+
binary). Either:
  * install it:  nvm install 18   (then re-run), or
  * point NODE18 at a Node 18 binary:  NODE18=/path/to/node $0, or
  * use docker:  USE_DOCKER=1 $0
MSG
    exit 1
  fi
  NODE_DIR="$(dirname "$NODE18")"
  SOKETI_DIR="${SOKETI_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/pusher_client_soketi}"
  SOKETI_BIN="$SOKETI_DIR/node_modules/@soketi/soketi/bin/server.js"
  if [[ ! -f "$SOKETI_BIN" ]]; then
    mkdir -p "$SOKETI_DIR"
    PATH="$NODE_DIR:$PATH" npm install --prefix "$SOKETI_DIR" --no-audit --no-fund @soketi/soketi@1.6.1
  fi
  if [[ "${SOKETI_STOCK:-}" != "1" ]]; then
    "$NODE18" -e '
      const fs = require("fs");
      const f = process.argv[1] + "/node_modules/@soketi/soketi/dist/ws-handler.js";
      let s = fs.readFileSync(f, "utf8");
      const from = "event: \x27pusher_internal:subscription_succeeded\x27,\n                    channel,\n                };";
      if (s.includes(from)) {
        s = s.replace(from, from.replace("channel,", "channel,\n                    data: \x27{}\x27,"));
        fs.writeFileSync(f, s);
        console.log("Patched soketi to send data:\"{}\" on subscription_succeeded");
      }
    ' "$SOKETI_DIR"
  fi
  PATH="$NODE_DIR:$PATH" "$NODE18" "$SOKETI_BIN" start >"$LOG" 2>&1 &
  SOKETI_PID=$!
fi

echo "Waiting for soketi on 127.0.0.1:$PORT (log: $LOG) ..."
for _ in $(seq 1 120); do
  if curl -fsS "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
    READY=1
    break
  fi
  if [[ -n "$SOKETI_PID" ]] && ! kill -0 "$SOKETI_PID" 2>/dev/null; then
    echo "soketi exited early:" >&2
    cat "$LOG" >&2
    exit 1
  fi
  sleep 1
done
if [[ "${READY:-}" != "1" ]]; then
  echo "soketi did not become healthy in time:" >&2
  cat "$LOG" >&2
  exit 1
fi
echo "soketi is up. Running integration tests on '$DEVICE' (app host $PUSHER_HOST)."

flutter test integration_test -d "$DEVICE" \
  --dart-define=PUSHER_HOST="$PUSHER_HOST" \
  --dart-define=PUSHER_PORT="$PORT" \
  --dart-define=PUSHER_KEY="$APP_KEY" \
  --dart-define=PUSHER_SECRET="$APP_SECRET" \
  --dart-define=PUSHER_APP_ID="$APP_ID"
