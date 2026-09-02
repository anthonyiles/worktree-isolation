#!/usr/bin/env bash
#
# post-checkout hook: automatically runs worktree-setup when a new worktree
# is created via `git worktree add`.
#
# This file itself lives in vendor/ (registered as hook.worktree-setup.command
# via an absolute path at install time — see stubs/bin/worktree-install) and
# is never copied into the project. It runs from the *new* worktree's cwd
# (git sets that before invoking post-checkout) but its own path stays
# anchored to the main clone's vendor/, since the new worktree has no
# vendor/ of its own yet — that's exactly what worktree-setup is about to
# create by running `composer install` there.
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

# We're in a fresh worktree. worktree-setup lives alongside this script in
# vendor/ (not in the new worktree, which has no vendor/ yet) — resolve it
# relative to this file, not relative to the worktree we're bootstrapping.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$HOOK_DIR/../bin/worktree-setup"

if [[ ! -x "$SETUP_SCRIPT" ]]; then
    echo "[post-checkout] worktree-setup not found or not executable at $SETUP_SCRIPT, skipping."
    exit 0
fi

echo ""
echo "[post-checkout] New worktree detected — running worktree-setup..."
echo ""

exec "$SETUP_SCRIPT"
