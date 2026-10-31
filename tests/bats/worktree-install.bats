#!/usr/bin/env bats
#
# Integration tests for stubs/bin/worktree-install's option handling, the
# config file it writes, git hook registration and agent block edge cases.
# Sail detection, the compose project base and the agent file selection
# have their own worktree-install-*.bats files.

setup() {
    STUBS_DIR="$(cd "$BATS_TEST_DIRNAME/../../stubs" && pwd)"

    PROJECT_DIR="$BATS_TEST_TMPDIR/Bob's App"
    mkdir -p "$PROJECT_DIR"
    git -C "$PROJECT_DIR" init -q

    # Same git --version shim as worktree-install-compose.bats, overridable
    # per test via FAKE_GIT_VERSION.
    REAL_GIT="$(command -v git)"
    FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
    mkdir -p "$FAKE_BIN"
    cat > "$FAKE_BIN/git" <<SCRIPT
#!/usr/bin/env bash
if [[ "\$1" == "--version" ]]; then
    echo "\${FAKE_GIT_VERSION:-git version 2.54.0}"
else
    exec "$REAL_GIT" "\$@"
fi
SCRIPT
    chmod +x "$FAKE_BIN/git"

    # Install must never need PHP on the host.
    PHP_LOG="$BATS_TEST_TMPDIR/php.log"
    cat > "$FAKE_BIN/php" <<SCRIPT
#!/usr/bin/env bash
echo "php \$*" >> "$PHP_LOG"
exit 1
SCRIPT
    chmod +x "$FAKE_BIN/php"
    export PATH="$FAKE_BIN:$PATH"
    unset LARAVEL_SAIL
}

run_install() {
    bash "$STUBS_DIR/bin/worktree-install" \
        --project-dir="$PROJECT_DIR" --stubs-dir="$STUBS_DIR" "$@"
}

config_file() {
    cat "$PROJECT_DIR/.worktree-isolation.env"
}

common_settings() {
    cat <<'ENV'

# Testing env file copied into each worktree, and its fallback
# WORKTREE_TESTING_ENV_FILE=.env.testing
# WORKTREE_TESTING_ENV_EXAMPLE=.env.testing.example

# Additional env vars to pass to the test container (space-separated, docker-image only)
# WORKTREE_EXTRA_ENV_VARS=

# Per-worktree development database (MySQL/MariaDB)
WORKTREE_DEV_DB_PER_WORKTREE=true
# WORKTREE_DEV_DB_MIGRATE_COMMAND=php artisan migrate --no-interaction
# WORKTREE_DEV_DB_SEED_COMMAND=php artisan db:seed --no-interaction
ENV
}

@test "installs through vendor/bin/worktree without calling php" {
    cd "$PROJECT_DIR"
    run bash "$STUBS_DIR/bin/worktree" install
    [ "$status" -eq 0 ]
    [ ! -e "$PHP_LOG" ]
    [ -f "$PROJECT_DIR/.worktree-isolation.env" ]
    run git -C "$PROJECT_DIR" config --local hook.worktree-setup.command
    [ "$output" = "bash '$STUBS_DIR/githooks/post-checkout-worktree-setup.sh'" ]
}

@test "prints usage for --help" {
    run run_install --help
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "Usage: vendor/bin/worktree install [OPTIONS]" ]]
    [[ "$output" == *"--agents[=FILES]"* ]]
    [ ! -f "$PROJECT_DIR/.worktree-isolation.env" ]
}

@test "rejects an invalid runtime" {
    run run_install --runtime=podman
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid runtime 'podman'. Use: native, docker-compose, docker-image"* ]]
}

@test "rejects unknown options" {
    run run_install --runtme=native
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown option '--runtme=native'"* ]]
    [ ! -f "$PROJECT_DIR/.worktree-isolation.env" ]
}

@test "rejects an option missing its value" {
    run run_install --runtime
    [ "$status" -eq 1 ]
    [[ "$output" == *"--runtime requires a value"* ]]
}

@test "requires git 2.54 or newer" {
    FAKE_GIT_VERSION="git version 2.9.5" run run_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"Git 2.54+ is required"*"You have Git 2.9."* ]]
    [ ! -f "$PROJECT_DIR/.worktree-isolation.env" ]

    FAKE_GIT_VERSION="git version 3.0.1" run run_install
    [ "$status" -eq 0 ]
    [[ "$output" == *"Git version: 3.0 (OK)"* ]]
}

@test "writes the native config" {
    run run_install
    [ "$status" -eq 0 ]
    [ "$(config_file)" = "$(cat <<'ENV'
# Worktree Isolation Configuration
# These values are used by vendor/bin/worktree setup and vendor/bin/worktree test

# Runtime driver: native | docker-compose | docker-image
WORKTREE_RUNTIME=native

# Test command (default: php artisan test)
# WORKTREE_TEST_COMMAND=php vendor/bin/phpunit
ENV
common_settings)" ]
    [ "$(tail -c 1 "$PROJECT_DIR/.worktree-isolation.env")" = "" ]
}

@test "writes the docker-compose config, taking option values as separate arguments" {
    run run_install --runtime docker-compose --compose-service web --test-command "php vendor/bin/phpunit --colors"
    [ "$status" -eq 0 ]
    [ "$(config_file)" = "$(cat <<'ENV'
# Worktree Isolation Configuration
# These values are used by vendor/bin/worktree setup and vendor/bin/worktree test

# Runtime driver: native | docker-compose | docker-image
WORKTREE_RUNTIME=docker-compose

# Test command (default: php artisan test)
WORKTREE_TEST_COMMAND=php vendor/bin/phpunit --colors

# docker-compose runtime settings
WORKTREE_COMPOSE_SERVICE=web
# WORKTREE_COMPOSE_FILE=docker-compose.yml
WORKTREE_COMPOSE_PROJECT_BASE=bob-s-app
ENV
common_settings)" ]
}

@test "writes the docker-image config and tips for missing settings" {
    run run_install --runtime=docker-image
    [ "$status" -eq 0 ]
    [[ "$output" == *"Tip: Set WORKTREE_DOCKER_IMAGE"* ]]
    [[ "$output" == *"Tip: Set WORKTREE_DOCKER_NETWORK"* ]]

    run run_install --runtime=docker-image --docker-image=app-img --docker-network=app-net --force
    [ "$status" -eq 0 ]
    [[ "$output" != *"Tip:"* ]]
    [ "$(config_file)" = "$(cat <<'ENV'
# Worktree Isolation Configuration
# These values are used by vendor/bin/worktree setup and vendor/bin/worktree test

# Runtime driver: native | docker-compose | docker-image
WORKTREE_RUNTIME=docker-image

# Test command (default: php artisan test)
# WORKTREE_TEST_COMMAND=php vendor/bin/phpunit

# docker-image runtime settings
WORKTREE_DOCKER_IMAGE=app-img
WORKTREE_DOCKER_NETWORK=app-net
# WORKTREE_DOCKER_WORKDIR=/var/www/html
ENV
common_settings)" ]
}

@test "keeps an existing config unless --force is passed" {
    echo "WORKTREE_RUNTIME=custom" > "$PROJECT_DIR/.worktree-isolation.env"

    run run_install
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping: .worktree-isolation.env (already exists)"* ]]
    [ "$(config_file)" = "WORKTREE_RUNTIME=custom" ]

    run run_install --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"Created: .worktree-isolation.env"* ]]
    grep -q '^WORKTREE_RUNTIME=native$' "$PROJECT_DIR/.worktree-isolation.env"
}

@test "quotes the hook path like escapeshellarg" {
    STUBS_COPY="$BATS_TEST_TMPDIR/it's stubs"
    cp -R "$STUBS_DIR" "$STUBS_COPY"

    run bash "$STUBS_DIR/bin/worktree-install" --project-dir="$PROJECT_DIR" --stubs-dir="$STUBS_COPY"
    [ "$status" -eq 0 ]
    run git -C "$PROJECT_DIR" config --local hook.worktree-setup.command
    [ "$output" = "bash '$BATS_TEST_TMPDIR/it'\\''s stubs/githooks/post-checkout-worktree-setup.sh'" ]
    run git -C "$PROJECT_DIR" config --local --get-all hook.worktree-setup.event
    [ "$output" = "post-checkout" ]
}

@test "replaces only the first agent block" {
    printf 'a <!-- worktree-isolation:start -->one<!-- worktree-isolation:end --> b\n<!-- worktree-isolation:start -->two<!-- worktree-isolation:end -->' \
        > "$PROJECT_DIR/AGENTS.md"

    run run_install --agents
    [ "$status" -eq 0 ]
    [[ "$output" == *"Updated: AGENTS.md"* ]]
    [ "$(head -c 37 "$PROJECT_DIR/AGENTS.md")" = "a <!-- worktree-isolation:start -->"$'\n#' ]
    ! grep -q 'one' "$PROJECT_DIR/AGENTS.md"
    [ "$(tail -1 "$PROJECT_DIR/AGENTS.md")" = "<!-- worktree-isolation:start -->two<!-- worktree-isolation:end -->" ]
}

@test "appends a new agent block when the existing one has no end marker" {
    printf 'x\n<!-- worktree-isolation:start -->\nno end\n' > "$PROJECT_DIR/AGENTS.md"

    run run_install --agents
    [ "$status" -eq 0 ]
    [[ "$output" == *"Added: AI agent instructions to AGENTS.md"* ]]
    [ "$(grep -c '<!-- worktree-isolation:start -->' "$PROJECT_DIR/AGENTS.md")" -eq 2 ]
    [ "$(sed -n 4p "$PROJECT_DIR/AGENTS.md")" = "" ]
    [ "$(tail -1 "$PROJECT_DIR/AGENTS.md")" = "<!-- worktree-isolation:end -->" ]
}

@test "keeps a file's missing trailing newline separated from the agent block" {
    printf '# Mine' > "$PROJECT_DIR/AGENTS.md"

    run run_install --agents
    [ "$status" -eq 0 ]
    [ "$(sed -n 1,3p "$PROJECT_DIR/AGENTS.md")" = "$(printf '# Mine\n\n<!-- worktree-isolation:start -->')" ]
}
