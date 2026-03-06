#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MacPilot.xcodeproj"
SCHEME="MacPilotAgent"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="platform=macOS,arch=arm64"
PORT=8443

echo "[MacPilot] Building $SCHEME ($CONFIGURATION)..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  build >/tmp/macpilot_agent_build.log

BUILD_DIR="$(
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -showBuildSettings 2>/dev/null | awk -F' = ' '/TARGET_BUILD_DIR =/{print $2; exit}'
)"

if [[ -z "${BUILD_DIR:-}" ]]; then
  echo "[MacPilot] Could not resolve TARGET_BUILD_DIR."
  exit 1
fi

AGENT_BIN="$BUILD_DIR/MacPilotAgent"
if [[ ! -x "$AGENT_BIN" ]]; then
  echo "[MacPilot] Agent binary not found: $AGENT_BIN"
  exit 1
fi

if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "[MacPilot] Port $PORT is already in use. Stop the running instance first."
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN
  exit 1
fi

echo "[MacPilot] Starting MacPilotAgent on port $PORT..."
exec env \
  DYLD_FRAMEWORK_PATH="$BUILD_DIR" \
  DYLD_LIBRARY_PATH="$BUILD_DIR" \
  "$AGENT_BIN"
