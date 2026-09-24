#!/usr/bin/env bats
#
# Integration tests for the docker-compose runtime's generic passthrough in
# stubs/bin/worktree, using a fake `docker` executable so no real Docker
# daemon is needed.

load helpers

setup() {
    setup_docker_compose_worktree
}

@test "passes an arbitrary command straight through to docker compose exec, threading -p" {
    run bash "$STUBS_DIR/worktree" composer require guzzlehttp/guzzle
    [ "$status" -eq 0 ]

    run grep -- " exec " "$DOCKER_LOG"
    [[ "$output" == *"-p myapp-feature-auth"* ]]
    [[ "$output" == *"composer require guzzlehttp/guzzle"* ]]
}

@test "forwards npm subcommands and their own flags untouched" {
    run bash "$STUBS_DIR/worktree" npm run dev
    [ "$status" -eq 0 ]

    run grep -- " exec " "$DOCKER_LOG"
    [[ "$output" == *"-p myapp-feature-auth"* ]]
    [[ "$output" == *"npm run dev"* ]]
}

@test "known subcommand 'setup' still delegates rather than being treated as passthrough" {
    run bash "$STUBS_DIR/worktree" setup
    [ "$status" -eq 0 ]

    # worktree-setup brings up its own stack (up -d) — proof the dispatcher
    # delegated to the real script instead of exec'ing "setup" as a literal
    # command inside the container.
    run grep -c -- "up -d" "$DOCKER_LOG"
    [ "$output" -ge 1 ]
}

@test "keeps a compose file path with spaces as a single argument" {
    log_docker_argv
    echo "WORKTREE_COMPOSE_FILE=\"my compose.yml\"" >> "$WORKTREE_DIR/.worktree-isolation.env"

    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]

    run grep -F -- "[-f] [my compose.yml]" "$DOCKER_ARGV_LOG"
    [ "$status" -eq 0 ]
}

@test "disables the pseudo-tty when stdin/stdout aren't terminals" {
    run bash "$STUBS_DIR/worktree" php -v < /dev/null
    [ "$status" -eq 0 ]

    run grep -- " -T app php -v" "$DOCKER_LOG"
    [ "$status" -eq 0 ]
}

@test "falls back to the main checkout's directory name when WORKTREE_COMPOSE_PROJECT_BASE is unset" {
    sed -i.bak '/^WORKTREE_COMPOSE_PROJECT_BASE=/d' "$WORKTREE_DIR/.worktree-isolation.env"

    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]

    run grep -- " exec " "$DOCKER_LOG"
    [[ "$output" == *"-p main-feature-auth"* ]]
}

@test "refuses to run in the main checkout" {
    cp "$WORKTREE_DIR/.worktree-isolation.env" "$MAIN_REPO/"
    cd "$MAIN_REPO"

    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 1 ]
    [[ "$output" == *"main checkout"* ]]
    [ ! -s "$DOCKER_LOG" ]

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"main checkout"* ]]
}

@test "native passthrough runs from the worktree root" {
    echo "WORKTREE_RUNTIME=native" > "$WORKTREE_DIR/.worktree-isolation.env"
    mkdir -p "$WORKTREE_DIR/app/Models"
    cd "$WORKTREE_DIR/app/Models"

    run bash "$STUBS_DIR/worktree" pwd
    [ "$status" -eq 0 ]
    [ "$output" = "$(cd "$WORKTREE_DIR" && pwd -P)" ]
}

@test "runs commands as the host user so the worktree's files stay owned by it" {
    run bash "$STUBS_DIR/worktree" composer install
    [ "$status" -eq 0 ]

    run grep -- " exec " "$DOCKER_LOG"
    [[ "$output" == *"exec -u $(id -u):$(id -g) -e HOME=/tmp "* ]]
}

@test "setup passes the host user to Sail's compose file as WWWUSER/WWWGROUP" {
    cat > "$FAKE_BIN/docker" <<SCRIPT
#!/usr/bin/env bash
echo "\$* WWWUSER=\$WWWUSER WWWGROUP=\$WWWGROUP" >> "$DOCKER_LOG"
SCRIPT

    run bash "$STUBS_DIR/worktree" setup
    [ "$status" -eq 0 ]

    run grep -- "up -d" "$DOCKER_LOG"
    [[ "$output" == *"WWWUSER=$(id -u) WWWGROUP=$(id -g)"* ]]
}

@test "keeps a WWWUSER that's already set" {
    cat > "$FAKE_BIN/docker" <<SCRIPT
#!/usr/bin/env bash
echo "\$* WWWUSER=\$WWWUSER" >> "$DOCKER_LOG"
SCRIPT

    WWWUSER=4242 run bash "$STUBS_DIR/worktree" setup
    [ "$status" -eq 0 ]

    run grep -- "up -d" "$DOCKER_LOG"
    [[ "$output" == *"WWWUSER=4242"* ]]
}

install_stubs_in_vendor() {
    VENDOR_BIN="$1/vendor/anthonyiles/worktree-isolation/stubs/bin"
    mkdir -p "$VENDOR_BIN"
    cp "$STUBS_DIR"/* "$VENDOR_BIN/"
}

@test "runs clean inside the worktree's stack, where DB_HOST resolves" {
    install_stubs_in_vendor "$WORKTREE_DIR"

    run bash "$VENDOR_BIN/worktree" clean --force
    [ "$status" -eq 0 ]

    run grep -- " exec " "$DOCKER_LOG"
    [[ "$output" == *"-p myapp-feature-auth"* ]]
    [[ "$output" == *"app php vendor/anthonyiles/worktree-isolation/stubs/bin/worktree-clean --force"* ]]
}

@test "runs clean from the main checkout inside its default-project stack" {
    install_stubs_in_vendor "$MAIN_REPO"
    cp "$WORKTREE_DIR/.worktree-isolation.env" "$MAIN_REPO/"
    cd "$MAIN_REPO"

    run bash "$VENDOR_BIN/worktree" clean
    [ "$status" -eq 0 ]

    run grep -- " exec " "$DOCKER_LOG"
    [[ "$output" != *"-p "* ]]
    [[ "$output" == *"app php vendor/anthonyiles/worktree-isolation/stubs/bin/worktree-clean"* ]]
}

@test "refuses to run clean in the runtime when the package is outside the project" {
    run bash "$STUBS_DIR/worktree" clean
    [ "$status" -ne 0 ]
    [[ "$output" == *"is outside the project"* ]]
}
