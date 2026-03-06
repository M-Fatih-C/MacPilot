#!/usr/bin/env bash
set -euo pipefail

PORT=8443
PIDS="$(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null || true)"

if [[ -z "$PIDS" ]]; then
  echo "[MacPilot] No process listening on port $PORT."
  exit 0
fi

echo "[MacPilot] Stopping process(es): $PIDS"
kill $PIDS
sleep 1

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "[MacPilot] Failed to stop all listeners on port $PORT."
  exit 1
fi

echo "[MacPilot] MacPilotAgent stopped."
