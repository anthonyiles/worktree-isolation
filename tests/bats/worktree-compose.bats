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

    run grep -- " exec -T app php -v" "$DOCKER_LOG"
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
