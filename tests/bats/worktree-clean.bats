#!/usr/bin/env bats
#
# stubs/bin/worktree-clean target selection and connection failures. Port 1
# refuses connections, so no database server is needed.

setup() {
    STUBS_DIR="$(cd "$BATS_TEST_DIRNAME/../../stubs/bin" && pwd)"
    PROJECT_DIR="$BATS_TEST_TMPDIR/project"
    mkdir -p "$PROJECT_DIR"
    git -C "$PROJECT_DIR" init -q

    echo "WORKTREE_DEV_DB_PER_WORKTREE=true" > "$PROJECT_DIR/.worktree-isolation.env"
    printf 'DB_CONNECTION=mysql\nDB_HOST=127.0.0.1\nDB_PORT=1\nDB_DATABASE=myapp\n' > "$PROJECT_DIR/.env"
}

run_clean() {
    php "$STUBS_DIR/worktree-clean" --project-dir="$PROJECT_DIR" --force
}

@test "skips a SQLite test database and still tries the development one" {
    printf 'DB_CONNECTION=sqlite\nDB_DATABASE=:memory:\n' > "$PROJECT_DIR/.env.testing"

    run run_clean
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not connect to the development database server"* ]]
    [[ "$output" != *"test database server"* ]]
}

@test "moves on to the development target when the test server is unreachable" {
    printf 'DB_CONNECTION=mysql\nDB_HOST=127.0.0.1\nDB_PORT=1\nDB_DATABASE=testing\n' > "$PROJECT_DIR/.env.testing"

    run run_clean
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not connect to the test database server"* ]]
    [[ "$output" == *"Could not connect to the development database server"* ]]
}

@test "falls back to the testing env example" {
    printf 'DB_CONNECTION=mysql\nDB_HOST=127.0.0.1\nDB_PORT=1\nDB_DATABASE=myapp_test\n' > "$PROJECT_DIR/.env.testing.example"

    run run_clean
    [[ "$output" == *"Could not connect to the test database server at 127.0.0.1:1"* ]]
}
