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
