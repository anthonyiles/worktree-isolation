#!/usr/bin/env bats
#
# Integration tests for the docker-compose runtime in stubs/bin/worktree-setup,
# using a fake `docker` executable so no real Docker daemon is needed.

load helpers

setup() {
    setup_docker_compose_worktree
}

@test "brings up its own stack and threads -p through every docker compose call" {
    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [ -s "$DOCKER_LOG" ]

    # "docker compose version" (the runtime prerequisite check) has no
    # project scope and legitimately carries no -p — only the up/exec calls
    # matter here. 4 expected: up -d, composer install exec, DB-derivation
    # exec, npm install exec.
    scoped_log="$BATS_TEST_TMPDIR/scoped.log"
    grep -E -- 'up -d| exec ' "$DOCKER_LOG" > "$scoped_log"

    run grep -c . "$scoped_log"
    [ "$output" -eq 4 ]

    run grep -vc -- "-p myapp-feature-auth" "$scoped_log"
    [ "$output" -eq 0 ]

    # up -d must run before the first exec (own-stack-per-worktree, not
    # assuming one is already running)
    first_up_line="$(grep -n -- 'up -d' "$DOCKER_LOG" | head -1 | cut -d: -f1)"
    first_exec_line="$(grep -n -- ' exec ' "$DOCKER_LOG" | head -1 | cut -d: -f1)"
    [ -n "$first_up_line" ]
    [ -n "$first_exec_line" ]
    [ "$first_up_line" -lt "$first_exec_line" ]
}

@test "resolves _worktree-lib.sh when invoked through a symlink (mirrors vendor/bin/)" {
    symlink_dir="$BATS_TEST_TMPDIR/vendor-bin"
    mkdir -p "$symlink_dir"
    ln -s "$STUBS_DIR/worktree-setup" "$symlink_dir/worktree-setup"

    run bash "$symlink_dir/worktree-setup"
    [ "$status" -eq 0 ]

    run grep -- "up -d" "$DOCKER_LOG"
    [[ "$output" == *"-p myapp-feature-auth"* ]]
}

@test "keeps a compose file path with spaces as a single argument" {
    log_docker_argv
    echo "WORKTREE_COMPOSE_FILE=\"my compose.yml\"" >> "$WORKTREE_DIR/.worktree-isolation.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    # up -d, composer install, DB derivation, npm install
    run grep -cF -- "[-f] [my compose.yml]" "$DOCKER_ARGV_LOG"
    [ "$output" -eq 4 ]
}

@test "copies env files into a worktree that uses relative gitdir paths, run from a subdirectory" {
    echo "APP_NAME=main" > "$MAIN_REPO/.env"
    relative_dir="$BATS_TEST_TMPDIR/worktrees/relative"
    git -C "$MAIN_REPO" worktree add -q --relative-paths -b relative "$relative_dir"
    cp "$WORKTREE_DIR/.worktree-isolation.env" "$WORKTREE_DIR/.env.testing" "$relative_dir/"
    mkdir -p "$relative_dir/app"
    cd "$relative_dir/app"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [ "$(cat "$relative_dir/.env")" = "APP_NAME=main" ]
}

@test "does nothing in the main checkout" {
    cd "$MAIN_REPO"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to set up"* ]]
    run grep -- "up -d" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}
