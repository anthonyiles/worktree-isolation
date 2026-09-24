#!/usr/bin/env bats
#
# Unit tests for stubs/bin/worktree's subcommand dispatch: verifies each
# known subcommand delegates to its sibling script with args forwarded.
# Sibling scripts are faked out here since they already have their own test
# suites (worktree-setup-compose.bats, test-compose.bats, etc.) — this file
# only covers the dispatcher's own routing logic. The fakes are deliberately
# not executable: Composer doesn't always keep the sub-scripts' executable
# bit, so the dispatcher must run them through their interpreter.

setup() {
    REAL_STUBS_DIR="$(cd "$BATS_TEST_DIRNAME/../../stubs/bin" && pwd)"

    DISPATCH_DIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$DISPATCH_DIR"
    cp "$REAL_STUBS_DIR/worktree" "$REAL_STUBS_DIR/_worktree-lib.sh" "$DISPATCH_DIR/"
    chmod +x "$DISPATCH_DIR/worktree"

    LOG="$BATS_TEST_TMPDIR/calls.log"
    : > "$LOG"

    for name in worktree-setup test; do
        cat > "$DISPATCH_DIR/$name" <<SCRIPT
#!/usr/bin/env bash
echo "$name \$*" >> "$LOG"
SCRIPT
    done
    for name in worktree-install worktree-clean; do
        cat > "$DISPATCH_DIR/$name" <<SCRIPT
#!/usr/bin/env php
<?php
file_put_contents('$LOG', '$name ' . implode(' ', array_slice(\$argv, 1)) . "\\n", FILE_APPEND);
SCRIPT
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

@test "prints usage and exits zero for --help and -h" {
    for flag in --help -h; do
        run "$DISPATCH_DIR/worktree" "$flag"
        [ "$status" -eq 0 ]
        [[ "$output" == *"Usage: vendor/bin/worktree"* ]]
    done
    [ ! -s "$LOG" ]
}
