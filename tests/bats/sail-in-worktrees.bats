#!/usr/bin/env bats
#
# A project's own `sail` and `docker compose` calls (e.g. in its git hooks)
# reach the worktree's runtime without changes: setup points Compose at a
# docker-compose worktree's stack, and Sail at stubs/bin/sail-docker in a
# docker-image worktree. Uses the fake `docker` from helpers.bash and a fake
# vendor/bin/sail that makes the same docker calls as laravel/sail's.

load helpers

setup() {
    setup_docker_compose_worktree
    echo "APP_NAME=main" > "$MAIN_REPO/.env"
}

use_docker_image_runtime() {
    cat > "$MAIN_REPO/.worktree-isolation.env" <<ENV
WORKTREE_RUNTIME=docker-image
WORKTREE_DOCKER_IMAGE=myapp:latest
WORKTREE_PRUNE_ON_SETUP=false
ENV
}

# Usage: fake_sail [old]
# Follows laravel/sail's bin/sail: it sources .env, checks docker and the
# stack through SAIL_DOCKER_BINARY (unless "old", from before Sail 1.55),
# then runs `compose exec -u sail [-T] <service> ...`.
fake_sail() {
    local docker='${SAIL_DOCKER_BINARY}' binary='export SAIL_DOCKER_BINARY=${SAIL_DOCKER_BINARY:-"docker"}'
    [[ "${1:-}" != old ]] || docker=docker binary=""
    mkdir -p vendor/laravel/sail/bin vendor/bin
    cat > vendor/laravel/sail/bin/sail <<SCRIPT
#!/usr/bin/env bash
[ ! -f ./.env ] || source ./.env
export APP_SERVICE=\${APP_SERVICE:-"laravel.test"}
$binary
$docker compose &> /dev/null || exit 9
$docker info > /dev/null 2>&1 || exit 8
if $docker compose ps "\$APP_SERVICE" 2>&1 | grep 'Exit\|exited'; then
    $docker compose down > /dev/null 2>&1
    exit 7
fi
if [ -z "\$($docker compose ps -q)" ]; then
    echo "Sail is not running." >&2
    exit 1
fi
ARGS=()
case "\$1" in
    pint) shift; ARGS+=(exec -u sail); [ ! -t 0 ] && ARGS+=(-T); ARGS+=("\$APP_SERVICE" php vendor/bin/pint) ;;
    debug) shift; ARGS+=(exec -u sail -e XDEBUG_TRIGGER=1); [ ! -t 0 ] && ARGS+=(-T); ARGS+=("\$APP_SERVICE" php artisan) ;;
    root-shell) shift; ARGS+=(exec -u root); [ ! -t 0 ] && ARGS+=(-T); ARGS+=("\$APP_SERVICE" bash) ;;
    mysql) shift; ARGS+=(exec); [ ! -t 0 ] && ARGS+=(-T); ARGS+=(mysql bash -c "mysql") ;;
esac
$docker compose "\${ARGS[@]}" "\$@"
SCRIPT
    chmod +x vendor/laravel/sail/bin/sail
    ln -sf ../laravel/sail/bin/sail vendor/bin/sail
}

# Points the worktree's Sail at sail-docker, as setup does.
use_sail_docker() {
    echo "SAIL_DOCKER_BINARY=$STUBS_DIR/sail-docker" >> .env
}

@test "docker-compose: setup points Compose at the worktree's own stack in its .env" {
    touch compose.yaml
    root="$(pwd -P)"
    override="$(git rev-parse --path-format=absolute --git-dir)/worktree-isolation.compose.yml"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    run grep '^COMPOSE_' .env
    [ "$output" = "$(printf 'COMPOSE_PROJECT_NAME=myapp-feature-auth-c0de\nCOMPOSE_FILE=%s/compose.yaml:%s' "$root" "$override")" ]
    [ "$(cat "$MAIN_REPO/.env")" = "APP_NAME=main" ]
}

@test "docker-compose: replaces a COMPOSE_PROJECT_NAME copied from the main checkout" {
    echo "COMPOSE_PROJECT_NAME=myapp" >> "$MAIN_REPO/.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    run grep -c '^COMPOSE_PROJECT_NAME=myapp-feature-auth-c0de$' .env
    [ "$output" -eq 1 ]
    run grep -c '^COMPOSE_PROJECT_NAME=myapp$' .env
    [ "$output" -eq 0 ]
}

@test "docker-compose: setup reads back its own COMPOSE_FILE without adding the override twice" {
    touch compose.yaml
    override="$(git rev-parse --path-format=absolute --git-dir)/worktree-isolation.compose.yml"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    first="$(grep '^COMPOSE_FILE=' .env)"
    : > "$DOCKER_LOG"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [ "$(grep '^COMPOSE_FILE=' .env)" = "$first" ]
    run grep -- "up -d" "$DOCKER_LOG"
    [[ "$output" == *"-f $(pwd -P)/compose.yaml -f $override up -d"* ]]
}

@test "docker-compose: gives a SAIL_FILES the worktree's compose files too" {
    touch compose.yaml
    echo "SAIL_FILES=compose.yaml" >> "$MAIN_REPO/.env"
    override="$(git rev-parse --path-format=absolute --git-dir)/worktree-isolation.compose.yml"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [ "$(grep '^SAIL_FILES=' .env)" = "SAIL_FILES=$(pwd -P)/compose.yaml:$override" ]
}

@test "docker-compose: doesn't warn about hooks, which now reach the worktree's stack" {
    git config hook.pint.command "vendor/bin/sail pint --dirty"
    git config hook.test.command "docker compose exec -T app php artisan test"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" != *"git hooks call sail"* ]]
}

@test "docker-image: setup points Sail 1.55+ at sail-docker, and flags only raw docker compose hooks" {
    use_docker_image_runtime
    fake_sail
    git config hook.pint.command "vendor/bin/sail pint --dirty"
    git config hook.test.command "docker compose exec -T laravel.test php artisan test"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [ "$(grep '^SAIL_DOCKER_BINARY=' .env)" = "SAIL_DOCKER_BINARY=$STUBS_DIR/sail-docker" ]
    [[ "$output" == *"  git config hook.test.command"* ]]
    [[ "$output" != *"hook.pint.command"* ]]
    [[ "$output" != *"sail 1.55+"* ]]
    [ "$(cat "$MAIN_REPO/.env")" = "APP_NAME=main" ]
}

@test "docker-image: setup leaves older Sail alone and says to update it" {
    use_docker_image_runtime
    fake_sail old
    git config hook.pint.command "vendor/bin/sail pint --dirty"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"  git config hook.pint.command"* ]]
    [[ "$output" == *"With laravel/sail 1.55+, sail runs in worktrees unchanged."* ]]
    run grep SAIL_DOCKER_BINARY .env
    [ "$status" -ne 0 ]
}

@test "docker-image: setup writes nothing for Sail without Sail" {
    use_docker_image_runtime

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    run grep SAIL_DOCKER_BINARY .env
    [ "$status" -ne 0 ]
}

@test "docker-image: sail runs its command in a container of the worktree" {
    use_docker_image_runtime
    fake_sail
    use_sail_docker

    run vendor/bin/sail pint --dirty < /dev/null
    [ "$status" -eq 0 ]
    run grep -- "run " "$DOCKER_LOG"
    [[ "$output" == "run --rm -u $(id -u):$(id -g) -e HOME=/tmp "* ]]
    [[ "$output" == *"-v $(pwd -P):/var/www/html "* ]]
    [[ "$output" == *" -i --entrypoint php myapp:latest vendor/bin/pint --dirty" ]]
    [[ "$output" != *" -t "* ]]
}

@test "docker-image: sail's checks are answered without docker compose" {
    use_docker_image_runtime
    use_sail_docker

    run bash "$STUBS_DIR/sail-docker" compose ps -q
    [ "$output" = worktree-isolation ]
    run bash "$STUBS_DIR/sail-docker" compose -f compose.yaml ps laravel.test
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run bash "$STUBS_DIR/sail-docker" compose
    [ "$status" -eq 0 ]
    run grep compose "$DOCKER_LOG"
    [ "$status" -ne 0 ]

    run bash "$STUBS_DIR/sail-docker" info
    [ "$(cat "$DOCKER_LOG")" = info ]
}

@test "docker-image: sail's -e values reach the container and -u root runs as root" {
    use_docker_image_runtime
    fake_sail
    use_sail_docker

    run vendor/bin/sail debug migrate < /dev/null
    [ "$status" -eq 0 ]
    run vendor/bin/sail root-shell < /dev/null
    [ "$status" -eq 0 ]

    run grep -- "artisan migrate" "$DOCKER_LOG"
    [[ "$output" == *"-e XDEBUG_TRIGGER=1 -i --entrypoint php myapp:latest artisan migrate" ]]
    run grep -- "--entrypoint bash" "$DOCKER_LOG"
    [[ "$output" == "run --rm -u root "* ]]
}

@test "docker-image: other sail commands fail without reaching docker" {
    use_docker_image_runtime
    fake_sail
    use_sail_docker

    run vendor/bin/sail mysql < /dev/null
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error: this worktree has no Sail containers"* ]]
    run bash "$STUBS_DIR/sail-docker" compose up -d
    [ "$status" -eq 1 ]
    [[ "$output" == *"Run other sail commands in the main checkout."* ]]

    run grep -E -- "run |compose (up|exec)" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}

@test "sail-docker is plain docker in the main checkout and for other runtimes" {
    use_docker_image_runtime
    use_main_checkout

    run bash "$STUBS_DIR/sail-docker" compose exec -u sail -T laravel.test php -v
    [ "$status" -eq 0 ]
    [ "$(cat "$DOCKER_LOG")" = "compose exec -u sail -T laravel.test php -v" ]

    cd "$WORKTREE_DIR"
    : > "$DOCKER_LOG"
    printf 'WORKTREE_RUNTIME=docker-compose\n' > "$MAIN_REPO/.worktree-isolation.env"
    run bash "$STUBS_DIR/sail-docker" compose ps -q
    [ "$status" -eq 0 ]
    [ "$(cat "$DOCKER_LOG")" = "compose ps -q" ]
}
