#!/usr/bin/env bash
# postStart: run `claude remote-control` in a detached tmux session ("claude")
# so it keeps going after the terminal closes. Attach with `tmux a -t claude`.
# Does nothing until Claude is logged in (`claude auth login`); run this script
# again after logging in. The first run in a fresh Claude volume asks to trust
# the folder and enable Remote Control: attach and answer once, the answers are
# kept in the volume.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v tmux >/dev/null || ! command -v claude >/dev/null; then
  echo "claude-rc: tmux or claude not installed yet, skipping"
  exit 0
fi
if tmux has-session -t claude 2>/dev/null; then
  echo "claude-rc: already running (tmux a -t claude)"
  exit 0
fi
if ! claude auth status 2>/dev/null | grep -q '"loggedIn": true'; then
  echo "claude-rc: not logged in; run 'claude auth login', then bash .devcontainer/claude-rc.sh"
  exit 0
fi

# Override with CLAUDE_RC_PERMISSION_MODE in the host secrets file
# (acceptEdits, auto, bypassPermissions, default, dontAsk, plan).
MODE="${CLAUDE_RC_PERMISSION_MODE:-auto}"

# The shell keeps the session open if remote-control exits, so errors stay visible.
tmux new-session -d -s claude -c "$ROOT" \
  "claude remote-control --name '$(basename "$ROOT")' --permission-mode '$MODE' --spawn=same-dir; exec bash"
echo "claude-rc: started (tmux a -t claude)"
