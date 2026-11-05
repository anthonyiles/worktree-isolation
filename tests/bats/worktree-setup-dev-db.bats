#!/usr/bin/env bats
#
# Per-worktree development database handling in stubs/bin/worktree-setup.

load helpers

setup() {
    setup_docker_compose_worktree
    DEV_DB_STATE=created
    DEV_DB_NOISE=
    fake_resolver_output
    echo "WORKTREE_DEV_DB_PER_WORKTREE=true" >> "$MAIN_REPO/.worktree-isolation.env"

    cat > "$WORKTREE_DIR/.env" <<ENV
APP_NAME="My App"
DB_CONNECTION=mysql
DB_HOST=mysql
DB_DATABASE=myapp
DB_USERNAME=root
DB_PASSWORD="secret"
ENV
    cp "$WORKTREE_DIR/.env" "$MAIN_REPO/.env"
    cp "$WORKTREE_DIR/.env.testing" "$MAIN_REPO/.env.testing"
}

# The fake docker answers the `php -r` call that creates a database the way
# the real snippet would: "<name> created|existing".
fake_resolver_output() {
    cat > "$FAKE_BIN/docker" <<SCRIPT
#!/usr/bin/env bash
[[ " \$* " != *" compose version "* ]] || echo 2.29.0
[[ " \$* " != *" config --services"* ]] || echo app
args="\$("$FAKE_BIN/docker-args" "\$@")"
echo "\$args" >> "$DOCKER_LOG"
if [[ "\$args" == *"up -d"* ]]; then
    echo "up with \$(grep '^DB_DATABASE=' .env) \$(grep '^DB_DATABASE=' .env.testing)" >> "$DOCKER_LOG"
fi
if [[ "\$args" == *"DB_DATABASE=myapp_wt_"*"php -r"* ]]; then
    printf '%s' "$DEV_DB_NOISE"
    echo "myapp_wt_feature-auth-c0de $DEV_DB_STATE"
elif [[ "\$args" == *"php -r"* ]]; then
    echo "myapp_test_wt_feature-auth-c0de created"
fi
exit 0
SCRIPT
}

@test "points .env at a new per-worktree database, then migrates and seeds it" {
    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=myapp_wt_feature-auth-c0de" ]

    run grep -- "-e DB_PASSWORD=secret" "$DOCKER_LOG"
    [ "$status" -eq 0 ]
    run grep -- "-T app sh -c php artisan migrate --no-interaction" "$DOCKER_LOG"
    [ "$status" -eq 0 ]
    run grep -- "-T app sh -c php artisan db:seed --no-interaction" "$DOCKER_LOG"
    [ "$status" -eq 0 ]
}

@test "points both env files at the worktree's databases before the stack starts" {
    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep "^up with" "$DOCKER_LOG"
    [ "$output" = "up with DB_DATABASE=myapp_wt_feature-auth-c0de DB_DATABASE=myapp_test_wt_feature-auth-c0de" ]
}

@test "derives from the main checkout's name when .env holds an old or blank one" {
    sed -i.bak 's/^DB_DATABASE=.*/DB_DATABASE=/' "$WORKTREE_DIR/.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=myapp_wt_feature-auth-c0de" ]
    run grep -- "-e MAIN_DB_DATABASE=myapp " "$DOCKER_LOG"
    [ "$status" -eq 0 ]
}

@test "migrates but does not re-seed a database that already existed" {
    DEV_DB_STATE=existing
    fake_resolver_output

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep -- "artisan migrate" "$DOCKER_LOG"
    [ "$status" -eq 0 ]
    run grep -- "db:seed" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}

@test "uses configured migrate and seed commands, and skips an empty one" {
    cat >> "$MAIN_REPO/.worktree-isolation.env" <<ENV
WORKTREE_DEV_DB_MIGRATE_COMMAND=
WORKTREE_DEV_DB_SEED_COMMAND="php bin/seed --demo"
ENV

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep -- "artisan migrate" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
    run grep -- "-T app sh -c php bin/seed --demo" "$DOCKER_LOG"
    [ "$status" -eq 0 ]
}

@test "ignores PHP notices printed before the resolver's result" {
    DEV_DB_NOISE=$'Deprecated: something in vendor/foo.php\n'
    fake_resolver_output

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=myapp_wt_feature-auth-c0de" ]
}

@test "keeps .env on the worktree's database when the resolver prints something unexpected" {
    DEV_DB_STATE="and then a warning"
    fake_resolver_output

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Could not create the development database"* ]]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=myapp_wt_feature-auth-c0de" ]
    run grep -- "artisan migrate" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}

@test "stays off when the setting is absent" {
    sed -i.bak '/^WORKTREE_DEV_DB_PER_WORKTREE=/d' "$MAIN_REPO/.worktree-isolation.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=myapp" ]
    run grep -E -- "-e DB_DATABASE=myapp( |_wt_)" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}

@test "leaves .env alone when disabled" {
    echo "WORKTREE_DEV_DB_PER_WORKTREE=false" >> "$MAIN_REPO/.worktree-isolation.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=myapp" ]
    run grep -E -- "-e DB_DATABASE=myapp( |_wt_)" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}

@test "skips non-MySQL connections" {
    sed -i.bak 's/^DB_CONNECTION=.*/DB_CONNECTION=sqlite/' "$WORKTREE_DIR/.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"only MySQL/MariaDB are supported"* ]]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=myapp" ]
}

@test "writes the derived test database into .env.testing" {
    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env.testing"
    [ "$output" = "DB_DATABASE=myapp_test_wt_feature-auth-c0de" ]
    run grep -- "-e DB_DATABASE=myapp_test_wt_feature-auth-c0de .* php -r" "$DOCKER_LOG"
    [ "$status" -eq 0 ]
}

@test "keeps .env.testing on the worktree's database when creating it fails" {
    cat > "$FAKE_BIN/docker" <<SCRIPT
#!/usr/bin/env bash
[[ " \$* " != *" compose version "* ]] || echo 2.29.0
[[ " \$* " != *" config --services"* ]] || echo app
args="\$("$FAKE_BIN/docker-args" "\$@")"
echo "\$args" >> "$DOCKER_LOG"
[[ "\$args" != *"php -r"* ]]
SCRIPT

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"vendor/bin/worktree test will create it on first run"* ]]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env.testing"
    [ "$output" = "DB_DATABASE=myapp_test_wt_feature-auth-c0de" ]
}

@test "names the test database after the main checkout's .env, not the testing env file" {
    sed -i.bak 's/^DB_DATABASE=.*/DB_DATABASE=other_testing/' "$MAIN_REPO/.env.testing" "$WORKTREE_DIR/.env.testing"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env.testing"
    [ "$output" = "DB_DATABASE=myapp_test_wt_feature-auth-c0de" ]
}

@test "blanks .env when no safe development database name can be derived" {
    sed -i.bak "s/^DB_DATABASE=.*/DB_DATABASE=$(printf 'a%.0s' {1..60})/" "$MAIN_REPO/.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Could not derive a development database name"* ]]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=" ]
    run grep -E -- "-e DB_DATABASE=myapp( |_wt_)" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}

@test "leaves a SQLite .env.testing untouched" {
    printf 'DB_CONNECTION=sqlite\nDB_DATABASE=database/testing.sqlite\n' > "$WORKTREE_DIR/.env.testing"
    cp "$WORKTREE_DIR/.env.testing" "$MAIN_REPO/.env.testing"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    [ "$(cat "$WORKTREE_DIR/.env.testing")" = "$(cat "$MAIN_REPO/.env.testing")" ]
    run grep -- "-e DB_DATABASE=testing" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}

@test "waits for a Compose database that isn't accepting connections yet" {
    sed -i.bak 's/^WORKTREE_DB_WAIT_SECONDS=.*/WORKTREE_DB_WAIT_SECONDS=10/' "$MAIN_REPO/.worktree-isolation.env"
    ATTEMPTS="$BATS_TEST_TMPDIR/attempts"
    echo 0 > "$ATTEMPTS"
    cat > "$FAKE_BIN/docker" <<SCRIPT
#!/usr/bin/env bash
[[ " \$* " != *" compose version "* ]] || echo 2.29.0
[[ " \$* " != *" config --services"* ]] || echo app
args="\$("$FAKE_BIN/docker-args" "\$@")"
echo "\$args" >> "$DOCKER_LOG"
if [[ "\$args" == *"php -r"* ]]; then
    n=\$((\$(cat "$ATTEMPTS") + 1))
    echo "\$n" > "$ATTEMPTS"
    (( n > 2 )) || exit 1
    if [[ "\$args" == *"DB_DATABASE=myapp_wt_"* ]]; then
        echo "myapp_wt_feature-auth-c0de created"
    else
        echo "myapp_test_wt_feature-auth-c0de created"
    fi
fi
exit 0
SCRIPT

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Could not create the test database"* ]]
    run grep -- "-T app sh -c php artisan db:seed --no-interaction" "$DOCKER_LOG"
    [ "$status" -eq 0 ]
}

@test "creates the test database without a testing env file, taking its settings from .env" {
    rm "$WORKTREE_DIR/.env.testing" "$MAIN_REPO/.env.testing"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Using test database myapp_test_wt_feature-auth-c0de"* ]]
    [[ "$output" != *"not found"* ]]
    [ ! -e "$WORKTREE_DIR/.env.testing" ]

    run grep -- "-e DB_HOST=mysql .*-e DB_PASSWORD=secret .*-e DB_DATABASE=myapp_test_wt_feature-auth-c0de app php -r" "$DOCKER_LOG"
    [ "$status" -eq 0 ]
}

@test "warns when phpunit.xml overrides the worktree's test database with <server>" {
    echo '<phpunit><php><server name="DB_DATABASE" value="testing"/></php></phpunit>' > "$WORKTREE_DIR/phpunit.xml"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"so tests ignore this"* ]]
}

@test "passes a socket, TLS CA, charset and collation to database creation" {
    printf 'DB_SOCKET=/run/mysqld/mysqld.sock\nDB_CHARSET=utf8mb4\nDB_COLLATION=utf8mb4_unicode_ci\nMYSQL_ATTR_SSL_CA=/ca.pem\n' >> "$WORKTREE_DIR/.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    run grep -- "-e DB_DATABASE=myapp_wt_feature-auth-c0de app php -r" "$DOCKER_LOG"
    [[ "$output" == *"-e DB_SOCKET=/run/mysqld/mysqld.sock "* ]]
    [[ "$output" == *"-e DB_CHARSET=utf8mb4 -e DB_COLLATION=utf8mb4_unicode_ci -e MYSQL_ATTR_SSL_CA=/ca.pem "* ]]
}

@test "records the worktree's databases for clean" {
    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [ "$(cat "$MAIN_REPO/.git/worktree-isolation/databases/feature-auth")" = "$(printf 'development\tmyapp_wt_feature-auth-c0de\ntest\tmyapp_test_wt_feature-auth-c0de')" ]

    run bash "$STUBS_DIR/worktree-setup"
    [ "$(wc -l < "$MAIN_REPO/.git/worktree-isolation/databases/feature-auth")" -eq 2 ]
}
