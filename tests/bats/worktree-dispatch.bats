#!/usr/bin/env bats
#
# Unit tests for stubs/bin/worktree's subcommand dispatch: verifies each
# known subcommand delegates to its sibling script with args forwarded.
# Sibling scripts are faked out here since they already have their own test
# suites (worktree-setup-compose.bats, test-compose.bats, etc.) — this file
# only covers the dispatcher's own routing logic.

setup() {
    REAL_STUBS_DIR="$(cd "$BATS_TEST_DIRNAME/../../stubs/bin" && pwd)"

    DISPATCH_DIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$DISPATCH_DIR"
    cp "$REAL_STUBS_DIR/worktree" "$DISPATCH_DIR/worktree"
    chmod +x "$DISPATCH_DIR/worktree"

    LOG="$BATS_TEST_TMPDIR/calls.log"
    : > "$LOG"

    for name in worktree-install worktree-setup test worktree-clean; do
        cat > "$DISPATCH_DIR/$name" <<SCRIPT
#!/usr/bin/env bash
echo "$name \$*" >> "$LOG"
exit 0
SCRIPT
        chmod +x "$DISPATCH_DIR/$name"
    done
}

@test "delegates 'install' to worktree-install with args forwarded" {
    run "$DISPATCH_DIR/worktree" install --runtime=docker-compose --force
    [ "$status" -eq 0 ]
    [ "$(cat "$LOG")" = "worktree-install --runtime=docker-compose --force" ]
}

@test "delegates 'setup' to worktree-setup" {
    run "$DISPATCH_DIR/worktree" setup
    [ "$status" -eq 0 ]
    [ "$(cat "$LOG")" = "worktree-setup " ]
}

@test "delegates 'test' to test with args forwarded" {
    run "$DISPATCH_DIR/worktree" test --filter=MyTest tests/Feature/MyTest.php
    [ "$status" -eq 0 ]
    [ "$(cat "$LOG")" = "test --filter=MyTest tests/Feature/MyTest.php" ]
}

@test "delegates 'clean' to worktree-clean with args forwarded" {
    run "$DISPATCH_DIR/worktree" clean --force
    [ "$status" -eq 0 ]
    [ "$(cat "$LOG")" = "worktree-clean --force" ]
}

@test "prints usage and exits non-zero with no arguments" {
    run "$DISPATCH_DIR/worktree"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage: vendor/bin/worktree"* ]]
}
