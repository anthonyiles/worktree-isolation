#!/usr/bin/env bats
#
# stubs/bin/worktree-clean: dropping the databases setup and test recorded
# for worktrees that no longer exist. A fake php answers for the database
# server, except where the real snippet is run against port 1, which refuses
# connections.

setup() {
    STUBS_DIR="$(cd "$BATS_TEST_DIRNAME/../../stubs/bin" && pwd)"
    export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
    export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com

    MAIN_REPO="$BATS_TEST_TMPDIR/main"
    git init -q "$MAIN_REPO"
    cd "$MAIN_REPO"
    git commit -q --allow-empty -m init
    git worktree add -q -b live "$BATS_TEST_TMPDIR/worktrees/live"
    printf 'WORKTREE_RUNTIME=native\nWORKTREE_DEV_DB_PER_WORKTREE=true\n' > .worktree-isolation.env
    printf 'DB_CONNECTION=mysql\nDB_HOST=devhost\nDB_DATABASE=myapp\n' > .env

    LEDGER="$MAIN_REPO/.git/worktree-isolation/databases"
    mkdir -p "$LEDGER"
    printf 'test\tmyapp_wt_gone-c0de_test\ndevelopment\tmyapp_wt_gone-c0de\n' > "$LEDGER/gone"
    printf 'test\tmyapp_wt_live-c0de_test\n' > "$LEDGER/live"

    FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
    mkdir -p "$FAKE_BIN"
    PHP_LOG="$BATS_TEST_TMPDIR/php.log"
    cat > "$FAKE_BIN/php" <<SCRIPT
#!/usr/bin/env bash
echo "\$DB_HOST \$DROP_DATABASES" >> "$PHP_LOG"
for name in \$DROP_DATABASES; do echo "dropped \$name"; done
SCRIPT
    chmod +x "$FAKE_BIN/php"
}

clean() {
    PATH="$FAKE_BIN:$PATH" bash "$STUBS_DIR/worktree-clean" "$@"
}

@test "drops only the databases of worktrees that no longer exist" {
    run clean --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dropped: myapp_wt_gone-c0de_test"*"Dropped: myapp_wt_gone-c0de"* ]]
    [[ "$output" != *"live"* ]]
    [ ! -e "$LEDGER/gone" ]
    [ -e "$LEDGER/live" ]
}

@test "connects with the tests' settings for test databases and .env's for development ones" {
    printf 'DB_CONNECTION=mysql\nDB_HOST=testhost\n' > .env.testing

    run clean --force
    [ "$status" -eq 0 ]
    [ "$(cat "$PHP_LOG")" = "testhost myapp_wt_gone-c0de_test
devhost myapp_wt_gone-c0de" ]
}

@test "--all drops existing worktrees' databases too" {
    run clean --all --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dropped: myapp_wt_live-c0de_test"* ]]
    [ ! -e "$LEDGER/live" ]
}

@test "never drops the main checkout's databases, even if recorded" {
    printf 'development\tmyapp\n' >> "$LEDGER/gone"

    run clean --force
    [ "$status" -eq 0 ]
    [[ "$(cat "$PHP_LOG")" != *" myapp"$'\n'* && "$(cat "$PHP_LOG")" != *" myapp" ]]
}

@test "asks before dropping" {
    run bash -c "printf 'n\n' | PATH='$FAKE_BIN:$PATH' bash '$STUBS_DIR/worktree-clean'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Drop these databases? [y/N]"*"Aborted."* ]]
    [ ! -e "$PHP_LOG" ]

    run bash -c "printf 'y\n' | PATH='$FAKE_BIN:$PATH' bash '$STUBS_DIR/worktree-clean'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dropped: myapp_wt_gone-c0de"* ]]
}

@test "says when there's nothing to drop" {
    rm "$LEDGER/gone"

    run clean --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"No databases of removed worktrees to drop."* ]]
    [ ! -e "$PHP_LOG" ]
}

@test "rejects an unknown option instead of ignoring it" {
    run clean --alll --force
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option '--alll'"*"Usage: vendor/bin/worktree clean"* ]]
    [ ! -e "$PHP_LOG" ]
}

@test "fails without .worktree-isolation.env" {
    rm .worktree-isolation.env

    run clean --force
    [ "$status" -eq 1 ]
    [[ "$output" == *".worktree-isolation.env not found"* ]]
}

@test "keeps a database it couldn't drop recorded, to try again" {
    printf 'DB_CONNECTION=mysql\nDB_HOST=127.0.0.1\nDB_PORT=1\nDB_DATABASE=myapp\n' > .env
    printf 'development\tmyapp_wt_gone-c0de\n' > "$LEDGER/gone"

    run bash "$STUBS_DIR/worktree-clean" --force
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not drop the development databases"*"Could not connect to the database server"* ]]
    [ -s "$LEDGER/gone" ]
}

@test "drops PostgreSQL databases with the pgsql connection" {
    printf 'DB_CONNECTION=pgsql\nDB_HOST=pghost\nDB_DATABASE=myapp\n' > .env
    printf '#!/usr/bin/env bash\necho "$DB_CONNECTION $DB_HOST $DROP_DATABASES" >> "%s"\nfor name in $DROP_DATABASES; do echo "dropped $name"; done\n' "$PHP_LOG" > "$FAKE_BIN/php"

    run clean --force
    [ "$status" -eq 0 ]
    [ "$(cat "$PHP_LOG")" = "pgsql pghost myapp_wt_gone-c0de_test
pgsql pghost myapp_wt_gone-c0de" ]
}
