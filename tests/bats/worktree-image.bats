#!/usr/bin/env bats
#
# Integration tests for the docker-image runtime in stubs/bin/worktree's
# passthrough and stubs/bin/test, using a fake `docker` executable so no real
# Docker daemon is needed.

load helpers

setup() {
    setup_docker_compose_worktree
    cat > "$WORKTREE_DIR/.worktree-isolation.env" <<ENV
WORKTREE_RUNTIME=docker-image
WORKTREE_DOCKER_IMAGE=myapp:latest
ENV
    echo "APP_ENV=testing" >> "$WORKTREE_DIR/.env.testing"
}

@test "passthrough does not forward the testing environment into the container" {
    run bash "$STUBS_DIR/worktree" php artisan migrate
    [ "$status" -eq 0 ]

    run grep -- "run " "$DOCKER_LOG"
    [[ "$output" == *"--entrypoint php myapp:latest artisan migrate"* ]]
    [[ "$output" != *"APP_ENV="* ]]
    [[ "$output" != *"DB_DATABASE="* ]]
}

@test "passthrough keeps stdin open so piped input reaches the command" {
    run bash "$STUBS_DIR/worktree" mysql < /dev/null
    [ "$status" -eq 0 ]

    run grep -- "run " "$DOCKER_LOG"
    [[ "$output" == *" -i "* ]]
    [[ "$output" != *" -t "* ]]
}

@test "test still forwards the testing environment" {
    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]

    run grep -- "run " "$DOCKER_LOG"
    [[ "$output" == *"-e APP_ENV=testing"* ]]
    [[ "$output" == *"-e DB_DATABASE=testing"* ]]
}

@test "test forwards a custom resolver class into the container" {
    cat >> "$WORKTREE_DIR/.worktree-isolation.env" <<'ENV'
WORKTREE_RESOLVER_CLASS='App\Testing\MyResolver'
ENV
    echo "TEST_DB_PER_WORKTREE=true" >> "$WORKTREE_DIR/.env.testing"

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]

    run grep -F -- "-e RESOLVER_CLASS=App\Testing\MyResolver" "$DOCKER_LOG"
    [ "$status" -eq 0 ]
}
