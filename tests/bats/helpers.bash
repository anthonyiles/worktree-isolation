#!/usr/bin/env bash
#
# Shared fixture for the docker-compose bats tests: a real temp git repo +
# worktree, a fake `docker` executable that logs every invocation instead of
# touching real Docker, and a minimal .worktree-isolation.env / .env.testing.

setup_docker_compose_worktree() {
    STUBS_DIR="$(cd "$BATS_TEST_DIRNAME/../../stubs/bin" && pwd)"

    FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
    mkdir -p "$FAKE_BIN"
    DOCKER_LOG="$BATS_TEST_TMPDIR/docker.log"
    : > "$DOCKER_LOG"

    cat > "$FAKE_BIN/docker" <<SCRIPT
#!/usr/bin/env bash
echo "\$*" >> "$DOCKER_LOG"
exit 0
SCRIPT
    chmod +x "$FAKE_BIN/docker"
    export PATH="$FAKE_BIN:$PATH"
    export DOCKER_LOG

    MAIN_REPO="$BATS_TEST_TMPDIR/main"
    mkdir -p "$MAIN_REPO"
    git -C "$MAIN_REPO" init -q
    git -C "$MAIN_REPO" -c user.email=test@example.com -c user.name=Test \
        commit -q --allow-empty -m init

    WORKTREE_DIR="$BATS_TEST_TMPDIR/worktrees/feature-auth"
    mkdir -p "$(dirname "$WORKTREE_DIR")"
    git -C "$MAIN_REPO" worktree add -q -b feature-auth "$WORKTREE_DIR"

    cat > "$WORKTREE_DIR/.worktree-isolation.env" <<ENV
WORKTREE_RUNTIME=docker-compose
WORKTREE_COMPOSE_SERVICE=app
WORKTREE_COMPOSE_PROJECT_BASE=myapp
ENV

    cat > "$WORKTREE_DIR/.env.testing" <<ENV
DB_DATABASE=testing
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USERNAME=root
DB_PASSWORD=
ENV

    cd "$WORKTREE_DIR" || return 1
}
