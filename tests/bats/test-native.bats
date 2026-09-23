#!/usr/bin/env bats
#
# Integration tests for the native runtime in stubs/bin/test, using a fake
# `php` executable so no real database is needed.

load helpers

setup() {
    setup_docker_compose_worktree
    cat > "$WORKTREE_DIR/.worktree-isolation.env" <<ENV
WORKTREE_RUNTIME=native
WORKTREE_TEST_COMMAND="printenv DB_DATABASE"
ENV
    echo "TEST_DB_PER_WORKTREE=true" >> "$WORKTREE_DIR/.env.testing"

    cat > "$FAKE_BIN/php" <<'SCRIPT'
#!/usr/bin/env bash
echo "Deprecated: something in vendor/foo.php"
printf '\n%s existing' "$DB_DATABASE"
SCRIPT
    chmod +x "$FAKE_BIN/php"
}

@test "hands the derived database to the test command, ignoring PHP notices" {
    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = "testing_wt_feature-auth" ]
}

@test "does not pass the database name through a shared temp file" {
    rm -f /tmp/.test_db_name

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]
    [ ! -e /tmp/.test_db_name ]
}

@test "fails instead of running tests when the resolver output is unusable" {
    cat > "$FAKE_BIN/php" <<'SCRIPT'
#!/usr/bin/env bash
echo "PHP Warning: something went wrong"
SCRIPT

    run bash "$STUBS_DIR/test"
    [ "$status" -ne 0 ]
    [[ "$output" == *"could not derive the per-worktree test database"* ]]
    [ "${lines[-1]}" != "testing" ]
}

@test "refuses the main checkout's test database when per-worktree databases are off" {
    sed -i.bak '/^TEST_DB_PER_WORKTREE=/d' "$WORKTREE_DIR/.env.testing"
    cp "$WORKTREE_DIR/.env.testing" "$MAIN_REPO/.env.testing"

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"main checkout's test database (testing)"* ]]
}

@test "derives from the main checkout's test database name" {
    echo "DB_DATABASE=app-testing" > "$MAIN_REPO/.env.testing"
    sed -i.bak 's/^DB_DATABASE=.*/DB_DATABASE=/' "$WORKTREE_DIR/.env.testing"

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" = "app-testing_wt_feature-auth" ]
}

@test "refuses a test database name without \"test\" in it" {
    echo "DB_DATABASE=myapp" > "$MAIN_REPO/.env.testing"

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not derive the per-worktree test database from 'myapp'"* ]]
}
