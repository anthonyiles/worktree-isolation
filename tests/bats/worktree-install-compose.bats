#!/usr/bin/env bats
#
# Integration tests for the docker-compose project-base handling in
# stubs/bin/worktree-install: default derivation from the project directory
# name, sanitization of an explicit --compose-project-base, and that the key
# is only written for the docker-compose runtime.

setup() {
    STUBS_DIR="$(cd "$BATS_TEST_DIRNAME/../../stubs" && pwd)"

    PROJECT_DIR="$BATS_TEST_TMPDIR/My Cool App"
    mkdir -p "$PROJECT_DIR"
    git -C "$PROJECT_DIR" init -q
    git -C "$PROJECT_DIR" -c user.email=test@example.com -c user.name=Test \
        commit -q --allow-empty -m init

    # worktree-install gates on `git --version` >= 2.54 (needed for
    # config-based hooks) before it ever touches compose-project-base — a
    # precondition unrelated to what these tests cover. Shim only
    # `--version` so the gate passes regardless of the git actually
    # installed; every other subcommand (git config, used by
    # configureGitHooks) still runs against the real git.
    REAL_GIT="$(command -v git)"
    FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
    mkdir -p "$FAKE_BIN"
    cat > "$FAKE_BIN/git" <<SCRIPT
#!/usr/bin/env bash
if [[ "\$1" == "--version" ]]; then
    echo "git version 2.54.0"
else
    exec "$REAL_GIT" "\$@"
fi
SCRIPT
    chmod +x "$FAKE_BIN/git"
    export PATH="$FAKE_BIN:$PATH"
}

run_install() {
    php "$STUBS_DIR/bin/worktree-install" \
        --project-dir="$PROJECT_DIR" --stubs-dir="$STUBS_DIR" "$@"
}

@test "derives WORKTREE_COMPOSE_PROJECT_BASE from the project directory name by default" {
    run run_install --runtime=docker-compose
    [ "$status" -eq 0 ]

    run grep '^WORKTREE_COMPOSE_PROJECT_BASE=' "$PROJECT_DIR/.worktree-isolation.env"
    [ "$output" = "WORKTREE_COMPOSE_PROJECT_BASE=my-cool-app" ]
}

@test "sanitizes an explicit --compose-project-base" {
    run run_install --runtime=docker-compose --compose-project-base='Weird/Name!!'
    [ "$status" -eq 0 ]

    run grep '^WORKTREE_COMPOSE_PROJECT_BASE=' "$PROJECT_DIR/.worktree-isolation.env"
    [ "$output" = "WORKTREE_COMPOSE_PROJECT_BASE=weird-name" ]
}

@test "does not write WORKTREE_COMPOSE_PROJECT_BASE for the native runtime" {
    run run_install --runtime=native
    [ "$status" -eq 0 ]

    run grep -c '^WORKTREE_COMPOSE_PROJECT_BASE=' "$PROJECT_DIR/.worktree-isolation.env"
    [ "$output" -eq 0 ]
}

@test "registers the post-checkout hook to run through bash" {
    run run_install --runtime=native
    [ "$status" -eq 0 ]

    run git -C "$PROJECT_DIR" config --local hook.worktree-setup.command
    [ "$output" = "bash '$STUBS_DIR/githooks/post-checkout-worktree-setup.sh'" ]
}
