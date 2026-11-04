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
    [ "${lines[${#lines[@]}-1]}" = "testing_wt_feature-auth" ]
}

@test "does not pass the database name through a shared temp file" {
    rm -f /tmp/.test_db_name

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]
    [ ! -e /tmp/.test_db_name ]
}

@test "shows PHP's error and runs no tests when the test database can't be created" {
    cat > "$FAKE_BIN/php" <<'SCRIPT'
#!/usr/bin/env bash
echo "PHP Fatal error: Uncaught PDOException: could not find driver"
exit 255
SCRIPT

    run bash "$STUBS_DIR/test"
    [ "$status" -ne 0 ]
    [[ "$output" == *"could not find driver"* ]]
    [[ "$output" == *"could not create the test database testing_wt_feature-auth"* ]]
    [[ "$output" != *$'\ntesting_wt_feature-auth'* ]]
}

@test "names the test database after the main checkout's development database" {
    printf 'DB_CONNECTION=mysql\nDB_DATABASE=myapp\n' > "$MAIN_REPO/.env"
    echo "DB_DATABASE=myapp_wt_feature-auth" > "$WORKTREE_DIR/.env"

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "myapp_test_wt_feature-auth" ]
}

@test "shortens a long development database name to fit the worktree's" {
    printf 'DB_CONNECTION=mysql\nDB_DATABASE=a_very_long_application_name\n' > "$MAIN_REPO/.env"

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "a_very_long_appl_test_wt_feature-auth" ]
}

@test "keeps quoted arguments in the test command together" {
    echo "WORKTREE_TEST_COMMAND='printf \"[%s]\" \"a b\"'" >> "$WORKTREE_DIR/.worktree-isolation.env"

    run bash "$STUBS_DIR/test" "c d"
    [ "$status" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "[a b][c d]" ]
}

@test "needs no testing env file" {
    rm "$WORKTREE_DIR/.env.testing"
    echo "DB_CONNECTION=mysql" > "$WORKTREE_DIR/.env"
    printf 'DB_CONNECTION=mysql\nDB_DATABASE=myapp\n' > "$MAIN_REPO/.env"

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]
    [ "${lines[${#lines[@]}-1]}" = "myapp_test_wt_feature-auth" ]
    [ ! -e "$WORKTREE_DIR/.env.testing" ]
}

@test "warns when phpunit.xml forces DB_DATABASE" {
    echo '<phpunit><php><env name="DB_DATABASE" value="app_testing" force="true"/></php></phpunit>' > "$WORKTREE_DIR/phpunit.xml"

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: phpunit.xml sets DB_DATABASE with <server> or force=\"true\""* ]]
}

@test "leaves a database alone when phpunit.xml makes the tests use SQLite" {
    echo '<phpunit><php><env name="DB_CONNECTION" value="sqlite"/></php></phpunit>' > "$WORKTREE_DIR/phpunit.xml"
    echo "WORKTREE_TEST_COMMAND='echo ran'" >> "$WORKTREE_DIR/.worktree-isolation.env"

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]
    [ "$output" = ran ]
}
