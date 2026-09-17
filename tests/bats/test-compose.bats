#!/usr/bin/env bats
#
# Integration tests for the docker-compose runtime in stubs/bin/test, using a
# fake `docker` executable so no real Docker daemon is needed.

load helpers

setup() {
    setup_docker_compose_worktree
}

@test "threads -p through the per-worktree-database branch" {
    echo "TEST_DB_PER_WORKTREE=true" >> "$WORKTREE_DIR/.env.testing"

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]

    # "docker compose version" (the runtime prerequisite check) has no
    # project scope and legitimately carries no -p — only the exec call
    # (running the test command) matters here.
    run grep -- " exec " "$DOCKER_LOG"
    [[ "$output" == *"-p myapp-feature-auth"* ]]
}

@test "threads -p through the plain (no per-worktree database) branch" {
    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]

    run grep -- " exec " "$DOCKER_LOG"
    [[ "$output" == *"-p myapp-feature-auth"* ]]
}
