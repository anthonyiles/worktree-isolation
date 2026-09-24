#!/usr/bin/env bats
#
# Integration tests for Laravel Sail detection in stubs/bin/worktree-install.

setup() {
    STUBS_DIR="$(cd "$BATS_TEST_DIRNAME/../../stubs" && pwd)"

    PROJECT_DIR="$BATS_TEST_TMPDIR/My App"
    mkdir -p "$PROJECT_DIR/vendor/bin"
    git -C "$PROJECT_DIR" init -q

    # Pass worktree-install's git >= 2.54 gate; everything else hits real git.
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
    unset LARAVEL_SAIL
}

add_sail() {
    touch "$PROJECT_DIR/vendor/bin/sail"
    cat > "$PROJECT_DIR/compose.yaml" <<'YAML'
services:
    laravel.test:
        build:
            context: './vendor/laravel/sail/runtimes/8.4'
        image: 'sail-8.4/app'
        networks:
            - sail
    mysql:
        image: 'mysql/mysql-server:8.0'
networks:
    sail:
        driver: bridge
YAML
}

run_install() {
    php "$STUBS_DIR/bin/worktree-install" \
        --project-dir="$PROJECT_DIR" --stubs-dir="$STUBS_DIR" "$@"
}

config_value() {
    grep "^$1=" "$PROJECT_DIR/.worktree-isolation.env"
}

@test "uses the docker-image runtime with Sail's image and network when Sail is detected" {
    add_sail
    run run_install
    [ "$status" -eq 0 ]
    [[ "$output" == *"Detected Laravel Sail"* ]]

    [ "$(config_value WORKTREE_RUNTIME)" = "WORKTREE_RUNTIME=docker-image" ]
    [ "$(config_value WORKTREE_DOCKER_IMAGE)" = "WORKTREE_DOCKER_IMAGE=sail-8.4/app" ]
    [ "$(config_value WORKTREE_DOCKER_NETWORK)" = "WORKTREE_DOCKER_NETWORK=myapp_sail" ]
}

@test "derives the Sail network from COMPOSE_PROJECT_NAME in .env" {
    add_sail
    echo 'COMPOSE_PROJECT_NAME="Shop"' > "$PROJECT_DIR/.env"
    run run_install
    [ "$status" -eq 0 ]
    [ "$(config_value WORKTREE_DOCKER_NETWORK)" = "WORKTREE_DOCKER_NETWORK=shop_sail" ]
}

@test "explicit options override Sail detection" {
    add_sail
    run run_install --docker-network=custom
    [ "$status" -eq 0 ]
    [ "$(config_value WORKTREE_DOCKER_NETWORK)" = "WORKTREE_DOCKER_NETWORK=custom" ]

    run run_install --runtime=native --force
    [ "$status" -eq 0 ]
    [ "$(config_value WORKTREE_RUNTIME)" = "WORKTREE_RUNTIME=native" ]
}

@test "defaults to native without Sail" {
    run run_install
    [ "$status" -eq 0 ]
    [[ "$output" != *"Detected Laravel Sail"* ]]
    [ "$(config_value WORKTREE_RUNTIME)" = "WORKTREE_RUNTIME=native" ]
}

@test "refuses to run inside a Sail container" {
    add_sail
    LARAVEL_SAIL=1 run run_install
    [ "$status" -eq 1 ]
    [[ "$output" == *"on the host"* ]]
    [ ! -f "$PROJECT_DIR/.worktree-isolation.env" ]
}
