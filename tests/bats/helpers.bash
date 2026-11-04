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

    # Prints its arguments as docker would see them: a bare "-e NAME" takes
    # NAME's value from the environment.
    cat > "$FAKE_BIN/docker-args" <<'SCRIPT'
#!/usr/bin/env bash
out=()
prev=
for arg in "$@"; do
    if [[ "$prev" == -e && "$arg" != *=* ]]; then
        arg="$arg=${!arg-}"
    fi
    out+=("$arg")
    prev="$arg"
done
echo "${out[*]}"
SCRIPT
    chmod +x "$FAKE_BIN/docker-args"

    cat > "$FAKE_BIN/docker" <<SCRIPT
#!/usr/bin/env bash
"$FAKE_BIN/docker-args" "\$@" >> "$DOCKER_LOG"
[[ " \$* " != *" ps --status running "* ]] || echo "\${FAKE_RUNNING_SERVICES-app}"
if [[ " \$* " == *" compose "*"config "* ]]; then
    [[ -z "\${FAKE_COMPOSE_CONFIG_FAILS:-}" ]] || exit 1
    cat "\${FAKE_COMPOSE_CONFIG:-/dev/null}"
fi
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
WORKTREE_DB_WAIT_SECONDS=0
ENV

    cat > "$WORKTREE_DIR/.env.testing" <<ENV
DB_CONNECTION=mysql
DB_DATABASE=testing
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USERNAME=root
DB_PASSWORD=
ENV

    cd "$WORKTREE_DIR" || return 1
}

# Also logs argv as "[arg] [arg]" so tests can detect word-splitting.
log_docker_argv() {
    DOCKER_ARGV_LOG="$BATS_TEST_TMPDIR/docker-argv.log"
    : > "$DOCKER_ARGV_LOG"
    cat > "$FAKE_BIN/docker" <<SCRIPT
#!/usr/bin/env bash
"$FAKE_BIN/docker-args" "\$@" >> "$DOCKER_LOG"
[[ " \$* " != *" ps --status running "* ]] || echo "\${FAKE_RUNNING_SERVICES-app}"
if [[ " \$* " == *" compose "*"config "* ]]; then
    [[ -z "\${FAKE_COMPOSE_CONFIG_FAILS:-}" ]] || exit 1
    cat "\${FAKE_COMPOSE_CONFIG:-/dev/null}"
fi
printf '[%s] ' "\$@" >> "$DOCKER_ARGV_LOG"
echo >> "$DOCKER_ARGV_LOG"
exit 0
SCRIPT
}

# Moves the worktree's config into the main checkout and works from there.
use_main_checkout() {
    cp "$WORKTREE_DIR/.worktree-isolation.env" "$MAIN_REPO/"
    cd "$MAIN_REPO" || return 1
}

# A fake `php` that logs where it ran and with what, for commands run directly
# on the host or inside the runtime.
fake_php() {
    PHP_RUN_LOG="$BATS_TEST_TMPDIR/php-run.log"
    cat > "$FAKE_BIN/php" <<SCRIPT
#!/usr/bin/env bash
echo "\$(pwd -P): \$*" >> "$PHP_RUN_LOG"
SCRIPT
    chmod +x "$FAKE_BIN/php"
}

# A PATH with the fakes and the basics but no docker, as inside a container.
path_without_docker() {
    local dir="$BATS_TEST_TMPDIR/nodocker" tool
    mkdir -p "$dir"
    for tool in bash git env sed grep cat dirname basename id tr cut mktemp awk readlink pwd; do
        [[ -e "$dir/$tool" ]] || ln -s "$(command -v "$tool")" "$dir/$tool"
    done
    [[ ! -e "$FAKE_BIN/php" ]] || ln -sf "$FAKE_BIN/php" "$dir/php"
    echo "$dir"
}
