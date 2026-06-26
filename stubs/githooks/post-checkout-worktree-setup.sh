#!/usr/bin/env bash
#
# post-checkout hook: automatically runs bin/worktree-setup when a new
# worktree is created via `git worktree add`.
#
# post-checkout receives three arguments:
#   $1 = previous HEAD (0{40} for new worktrees)
#   $2 = new HEAD
#   $3 = flag: 1 = branch checkout, 0 = file checkout
#
set -euo pipefail

PREV_HEAD="$1"
FLAG="${3:-0}"

# Only act on branch checkouts (flag=1)
if [[ "$FLAG" != "1" ]]; then
    exit 0
fi

# Detect new worktree: previous HEAD is the null ref (all zeros)
NULL_REF="0000000000000000000000000000000000000000"
if [[ "$PREV_HEAD" != "$NULL_REF" ]]; then
    exit 0
fi

# We're in a fresh worktree — find the project root
PROJECT_ROOT="$(git rev-parse --show-toplevel)"

SETUP_SCRIPT="$PROJECT_ROOT/bin/worktree-setup"

if [[ ! -x "$SETUP_SCRIPT" ]]; then
    echo "[post-checkout] bin/worktree-setup not found or not executable, skipping."
    exit 0
fi

echo ""
echo "[post-checkout] New worktree detected — running bin/worktree-setup..."
echo ""

exec "$SETUP_SCRIPT"
