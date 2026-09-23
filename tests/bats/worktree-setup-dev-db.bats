#!/usr/bin/env bats
#
# Per-worktree development database handling in stubs/bin/worktree-setup.

load helpers

setup() {
    setup_docker_compose_worktree
    DEV_DB_STATE=created
    DEV_DB_NOISE=
    fake_resolver_output
    echo "WORKTREE_DEV_DB_PER_WORKTREE=true" >> "$WORKTREE_DIR/.worktree-isolation.env"

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

# The fake docker answers the resolver's `php -r` call the way the real
# snippet would: "<name> created|existing".
fake_resolver_output() {
    cat > "$FAKE_BIN/docker" <<SCRIPT
#!/usr/bin/env bash
echo "\$*" >> "$DOCKER_LOG"
if [[ "\$*" == *"up -d"* ]]; then
    echo "up with \$(grep '^DB_DATABASE=' .env) \$(grep '^DB_DATABASE=' .env.testing)" >> "$DOCKER_LOG"
fi
if [[ "\$*" == *DevDatabaseResolver*"php -r"* ]]; then
    printf '%s' "$DEV_DB_NOISE"
    echo "myapp_wt_feature-auth $DEV_DB_STATE"
elif [[ "\$*" == *"php -r"* ]]; then
    echo "testing_wt_feature-auth created"
fi
exit 0
SCRIPT
}

@test "points .env at a new per-worktree database, then migrates and seeds it" {
    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=myapp_wt_feature-auth" ]

    run grep -- "-e DB_PASSWORD=secret" "$DOCKER_LOG"
    [ "$status" -eq 0 ]
    run grep -- "exec -T app php artisan migrate --no-interaction" "$DOCKER_LOG"
    [ "$status" -eq 0 ]
    run grep -- "exec -T app php artisan db:seed --no-interaction" "$DOCKER_LOG"
    [ "$status" -eq 0 ]
}

@test "points both env files at the worktree's databases before the stack starts" {
    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep "^up with" "$DOCKER_LOG"
    [ "$output" = "up with DB_DATABASE=myapp_wt_feature-auth DB_DATABASE=testing_wt_feature-auth" ]
}

@test "derives from the main checkout's name when .env holds an old or blank one" {
    sed -i.bak 's/^DB_DATABASE=.*/DB_DATABASE=/' "$WORKTREE_DIR/.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=myapp_wt_feature-auth" ]
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
    cat >> "$WORKTREE_DIR/.worktree-isolation.env" <<ENV
WORKTREE_DEV_DB_MIGRATE_COMMAND=
WORKTREE_DEV_DB_SEED_COMMAND="php bin/seed --demo"
ENV

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep -- "artisan migrate" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
    run grep -- "exec -T app php bin/seed --demo" "$DOCKER_LOG"
    [ "$status" -eq 0 ]
}

@test "ignores PHP notices printed before the resolver's result" {
    DEV_DB_NOISE=$'Deprecated: something in vendor/foo.php\n'
    fake_resolver_output

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=myapp_wt_feature-auth" ]
}

@test "keeps .env on the worktree's database when the resolver prints something unexpected" {
    DEV_DB_STATE="and then a warning"
    fake_resolver_output

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Could not create the development database"* ]]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=myapp_wt_feature-auth" ]
    run grep -- "artisan migrate" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}

@test "stays off when the setting is absent, as in configs from earlier versions" {
    sed -i.bak '/^WORKTREE_DEV_DB_PER_WORKTREE=/d' "$WORKTREE_DIR/.worktree-isolation.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=myapp" ]
    run grep -- "DevDatabaseResolver" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}

@test "leaves .env alone when disabled" {
    echo "WORKTREE_DEV_DB_PER_WORKTREE=false" >> "$WORKTREE_DIR/.worktree-isolation.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=myapp" ]
    run grep -- "DevDatabaseResolver" "$DOCKER_LOG"
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
    [ "$output" = "DB_DATABASE=testing_wt_feature-auth" ]
}

@test "keeps .env.testing on the worktree's database when creating it fails" {
    cat > "$FAKE_BIN/docker" <<SCRIPT
#!/usr/bin/env bash
echo "\$*" >> "$DOCKER_LOG"
[[ "\$*" != *"php -r"* ]]
SCRIPT

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"vendor/bin/worktree test will create it on first run"* ]]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env.testing"
    [ "$output" = "DB_DATABASE=testing_wt_feature-auth" ]
}

@test "blanks .env.testing when the main test database name has no \"test\" in it" {
    sed -i.bak 's/^DB_DATABASE=.*/DB_DATABASE=myapp/' "$MAIN_REPO/.env.testing" "$WORKTREE_DIR/.env.testing"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Could not derive a test database name"* ]]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env.testing"
    [ "$output" = "DB_DATABASE=" ]
}

@test "blanks .env when no safe development database name can be derived" {
    sed -i.bak "s/^DB_DATABASE=.*/DB_DATABASE=$(printf 'a%.0s' {1..60})/" "$MAIN_REPO/.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Could not derive a development database name"* ]]

    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env"
    [ "$output" = "DB_DATABASE=" ]
    run grep -- "DevDatabaseResolver" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}
