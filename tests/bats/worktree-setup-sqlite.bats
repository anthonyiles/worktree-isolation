#!/usr/bin/env bats
#
# SQLite in stubs/bin/worktree-setup and stubs/bin/test: each worktree keeps
# its own database file.

load helpers

setup() {
    setup_docker_compose_worktree
    fake_php
    echo "WORKTREE_DEV_DB_PER_WORKTREE=true" >> "$MAIN_REPO/.worktree-isolation.env"
    rm "$WORKTREE_DIR/.env.testing"
    MAIN_REAL="$(cd -P "$MAIN_REPO" && pwd)"
    WORKTREE_REAL="$(cd -P "$WORKTREE_DIR" && pwd)"
}

use_native() {
    sed -i.bak 's/^WORKTREE_RUNTIME=.*/WORKTREE_RUNTIME=native/' "$MAIN_REPO/.worktree-isolation.env"
}

@test "natively, moves a path into the main checkout to the worktree's own file, then migrates and seeds it" {
    use_native
    printf 'DB_CONNECTION=sqlite\nDB_DATABASE=%s/database/database.sqlite\n' "$MAIN_REAL" > "$MAIN_REPO/.env"
    mkdir -p "$MAIN_REPO/database" && echo main > "$MAIN_REPO/database/database.sqlite"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Using SQLite database database/database.sqlite"* ]]
    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=$WORKTREE_REAL/database/database.sqlite" ]
    [ -f "$WORKTREE_DIR/database/database.sqlite" ]
    [ ! -s "$WORKTREE_DIR/database/database.sqlite" ]
    [ "$(cat "$MAIN_REPO/database/database.sqlite")" = main ]
    grep -q "artisan migrate --no-interaction" "$PHP_RUN_LOG"
    grep -q "artisan db:seed --no-interaction" "$PHP_RUN_LOG"

    # An existing file is migrated, not seeded again.
    : > "$PHP_RUN_LOG"
    run bash "$STUBS_DIR/worktree-setup"
    grep -q "artisan migrate" "$PHP_RUN_LOG"
    run grep "db:seed" "$PHP_RUN_LOG"
    [ "$status" -ne 0 ]
}

@test "creates Laravel's default file when .env names none" {
    printf 'DB_CONNECTION=sqlite\n' > "$MAIN_REPO/.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [ -f "$WORKTREE_DIR/database/database.sqlite" ]
    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$status" -ne 0 ]
}

@test "in a Docker runtime, keeps a path under the mount, creating the worktree's file" {
    printf 'DB_CONNECTION=sqlite\nDB_DATABASE=/var/www/html/database/app.sqlite\n' > "$MAIN_REPO/.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=/var/www/html/database/app.sqlite" ]
    [ -f "$WORKTREE_DIR/database/app.sqlite" ]
    run grep -- "-T app sh -c php artisan migrate" "$DOCKER_LOG"
    [ "$status" -eq 0 ]
}

@test "in a Docker runtime, warns about a path outside the mount" {
    printf 'DB_CONNECTION=sqlite\nDB_DATABASE=/data/app.sqlite\n' > "$MAIN_REPO/.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"outside /var/www/html, so this worktree shares that file"* ]]
    run grep "artisan migrate" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}

@test "leaves an in-memory database alone" {
    printf 'DB_CONNECTION=sqlite\nDB_DATABASE=:memory:\n' > "$MAIN_REPO/.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [ ! -e "$WORKTREE_DIR/database" ]
    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=:memory:" ]
}

@test "test passes the worktree's own SQLite file for a path into the main checkout" {
    use_native
    printf 'DB_CONNECTION=sqlite\n' > "$WORKTREE_DIR/.env"
    printf '<phpunit><php><env name="DB_CONNECTION" value="sqlite"/><env name="DB_DATABASE" value="%s/database/testing.sqlite"/></php></phpunit>' "$MAIN_REAL" > "$WORKTREE_DIR/phpunit.xml"
    printf '#!/usr/bin/env bash\necho "DB_DATABASE=$DB_DATABASE"\n' > "$FAKE_BIN/php"

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DB_DATABASE=$WORKTREE_REAL/database/testing.sqlite"* ]]
    [ -f "$WORKTREE_DIR/database/testing.sqlite" ]
}

@test "test leaves an in-memory SQLite database alone" {
    use_native
    printf 'DB_CONNECTION=sqlite\nDB_DATABASE=:memory:\n' > "$WORKTREE_DIR/.env"
    printf '#!/usr/bin/env bash\necho "DB_DATABASE=$DB_DATABASE"\n' > "$FAKE_BIN/php"

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]
    # Nothing passed: Laravel reads .env's value itself.
    [[ "$output" == *"DB_DATABASE="$'\n'* || "$output" == *"DB_DATABASE=" ]]
    [ ! -e "$WORKTREE_DIR/database" ]
}
