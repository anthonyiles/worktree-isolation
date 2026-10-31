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

@test "--stale refuses to guess when it can't list the worktrees" {
    not_a_repo="$BATS_TEST_TMPDIR/not-a-repo"
    mkdir -p "$not_a_repo"
    cp "$PROJECT_DIR/.worktree-isolation.env" "$PROJECT_DIR/.env" "$not_a_repo/"

    run php "$STUBS_DIR/worktree-clean" --project-dir="$not_a_repo" --stale --force
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not list this repository's worktrees"* ]]
    [[ "$output" != *"Dropped"* ]]
}

@test "rejects an unknown option instead of ignoring it" {
    printf 'DB_CONNECTION=mysql\nDB_HOST=127.0.0.1\nDB_PORT=1\nDB_DATABASE=testing\n' > "$PROJECT_DIR/.env.testing"

    run php "$STUBS_DIR/worktree-clean" --project-dir="$PROJECT_DIR" --stael --force
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option '--stael'"* ]]
    [[ "$output" == *"Usage: vendor/bin/worktree clean"* ]]
    [[ "$output" != *"Could not connect"* ]]
}

@test "takes --project-dir's value as a separate argument" {
    run php "$STUBS_DIR/worktree-clean" --project-dir "$PROJECT_DIR" --force
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not connect to the development database server"* ]]
}

@test "fails without .worktree-isolation.env" {
    rm "$PROJECT_DIR/.worktree-isolation.env"

    run run_clean
    [ "$status" -eq 1 ]
    [[ "$output" == *".worktree-isolation.env not found"* ]]
    [[ "$output" != *"Could not connect"* ]]
}

@test "takes database names from the main checkout, not the worktree" {
    git -C "$PROJECT_DIR" -c user.email=test@example.com -c user.name=Test commit -q --allow-empty -m init
    worktree="$BATS_TEST_TMPDIR/worktrees/feature"
    git -C "$PROJECT_DIR" worktree add -q -b feature "$worktree"
    cp "$PROJECT_DIR/.worktree-isolation.env" "$worktree/"
    printf 'DB_CONNECTION=mysql\nDB_HOST=127.0.0.1\nDB_PORT=1\nDB_DATABASE=testing_wt_feature\n' > "$worktree/.env.testing"

    run php "$STUBS_DIR/worktree-clean" --project-dir="$worktree" --force
    [[ "$output" == *"development database server"* ]]
    [[ "$output" != *"test database server"* ]]
}
