#!/usr/bin/env bats
#
# stubs/githooks/post-checkout-worktree-setup.sh

setup() {
    VENDOR_DIR="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$VENDOR_DIR/githooks" "$VENDOR_DIR/bin"
    cp "$BATS_TEST_DIRNAME/../../stubs/githooks/post-checkout-worktree-setup.sh" "$VENDOR_DIR/githooks/"

    LOG="$BATS_TEST_TMPDIR/calls.log"
    # Not executable, as after a zip dist install without unzip.
    echo "echo setup-ran >> '$LOG'" > "$VENDOR_DIR/bin/worktree-setup"
}

@test "runs worktree-setup for a new worktree even when it isn't executable" {
    run bash "$VENDOR_DIR/githooks/post-checkout-worktree-setup.sh" \
        0000000000000000000000000000000000000000 abc123 1
    [ "$status" -eq 0 ]
    [ "$(cat "$LOG")" = "setup-ran" ]
}

@test "ignores ordinary branch checkouts" {
    run bash "$VENDOR_DIR/githooks/post-checkout-worktree-setup.sh" def456 abc123 1
    [ "$status" -eq 0 ]
    [ ! -e "$LOG" ]
}

@test "runs for a new worktree in a SHA-256 repository" {
    run bash "$VENDOR_DIR/githooks/post-checkout-worktree-setup.sh" \
        "$(printf '0%.0s' {1..64})" abc123 1
    [ "$status" -eq 0 ]
    [ "$(cat "$LOG")" = "setup-ran" ]
}

@test "skips setup with WORKTREE_SKIP_SETUP set" {
    WORKTREE_SKIP_SETUP=1 run bash "$VENDOR_DIR/githooks/post-checkout-worktree-setup.sh" \
        0000000000000000000000000000000000000000 abc123 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"WORKTREE_SKIP_SETUP is set"* ]]
    [ ! -e "$LOG" ]
}
