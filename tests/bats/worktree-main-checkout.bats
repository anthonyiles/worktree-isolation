#!/usr/bin/env bats
#
# Passthrough from the main checkout (WORKTREE_MAIN_CHECKOUT_PASSTHROUGH),
# running directly when already inside the runtime, and WORKTREE_DOCKER_ENV,
# using a fake `docker` executable so no real Docker daemon is needed.

load helpers

setup() {
    setup_docker_compose_worktree
    fake_php
    MAIN_REAL="$(cd "$MAIN_REPO" && pwd -P)"
    WORKTREE_REAL="$(pwd -P)"
}

use_runtime() {
    case "$1" in
        native) echo "WORKTREE_RUNTIME=native" ;;
        docker-compose) printf 'WORKTREE_RUNTIME=docker-compose\nWORKTREE_COMPOSE_SERVICE=app\nWORKTREE_COMPOSE_PROJECT_BASE=myapp\n' ;;
        docker-image) printf 'WORKTREE_RUNTIME=docker-image\nWORKTREE_DOCKER_IMAGE=myapp:latest\n' ;;
    esac > "$MAIN_REPO/.worktree-isolation.env"
}

enable_main_checkout() {
    echo "WORKTREE_MAIN_CHECKOUT_PASSTHROUGH=true" >> "$MAIN_REPO/.worktree-isolation.env"
}

@test "refuses in the main checkout by default, saying how to allow it" {
    for runtime in native docker-compose docker-image; do
        use_runtime "$runtime"
        use_main_checkout

        run bash "$STUBS_DIR/worktree" php -v
        [ "$status" -eq 1 ]
        [[ "$output" == *"this is the main checkout"* ]]
        [[ "$output" == *"set WORKTREE_MAIN_CHECKOUT_PASSTHROUGH=true in .worktree-isolation.env"* ]]
        [ ! -s "$DOCKER_LOG" ]
        [ ! -e "$PHP_RUN_LOG" ]
    done
}

@test "native: runs the command from the main checkout's root" {
    use_runtime native
    use_main_checkout
    enable_main_checkout
    mkdir sub && cd sub

    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]
    [ "$(cat "$PHP_RUN_LOG")" = "$MAIN_REAL: -v" ]
}

@test "the option can be set for one call from the environment" {
    use_runtime native
    use_main_checkout

    WORKTREE_MAIN_CHECKOUT_PASSTHROUGH=true run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]
    [ "$(cat "$PHP_RUN_LOG")" = "$MAIN_REAL: -v" ]
}

@test "docker-compose: execs into the main checkout's own stack without starting it" {
    use_runtime docker-compose
    use_main_checkout
    enable_main_checkout

    run bash "$STUBS_DIR/worktree" php vendor/bin/phpstan analyse
    [ "$status" -eq 0 ]

    run grep -- " exec " "$DOCKER_LOG"
    [[ "$output" != *"-p "* ]]
    [[ "$output" == *" app php vendor/bin/phpstan analyse" ]]
    run grep -- " up " "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}

@test "docker-compose: fails clearly when the main checkout's service isn't running" {
    use_runtime docker-compose
    use_main_checkout
    enable_main_checkout

    FAKE_RUNNING_SERVICES=mysql run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 1 ]
    [[ "$output" == *"the 'app' service isn't running in the main checkout's stack"* ]]
    run grep -E -- " (exec|up) " "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}

@test "docker-compose: a worktree's passthrough doesn't check its service first" {
    use_runtime docker-compose

    FAKE_RUNNING_SERVICES= run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]
    run grep -- " ps " "$DOCKER_LOG"
    [ "$status" -ne 0 ]
    run grep -- "-p myapp-feature-auth-c0de exec " "$DOCKER_LOG"
    [ "$status" -eq 0 ]
}

@test "docker-image: runs a fresh container with the main checkout mounted" {
    use_runtime docker-image
    use_main_checkout
    enable_main_checkout

    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]

    run grep -- "run " "$DOCKER_LOG"
    [[ "$output" == *"-v $MAIN_REAL:/var/www/html -w /var/www/html "* ]]
    [[ "$output" == *"--entrypoint php myapp:latest -v" ]]
}

@test "inside Sail, runs the command directly in a worktree and the main checkout" {
    for runtime in docker-compose docker-image; do
        use_runtime "$runtime"
        : > "$PHP_RUN_LOG"
        cd "$WORKTREE_DIR"
        LARAVEL_SAIL=1 run bash "$STUBS_DIR/worktree" php -v
        [ "$status" -eq 0 ]

        use_main_checkout
        enable_main_checkout
        LARAVEL_SAIL=1 run bash "$STUBS_DIR/worktree" php -v
        [ "$status" -eq 0 ]

        [ "$(cat "$PHP_RUN_LOG")" = "$WORKTREE_REAL: -v
$MAIN_REAL: -v" ]
        [ ! -s "$DOCKER_LOG" ]
    done
}

@test "inside a container this package started, runs the command directly" {
    for runtime in docker-compose docker-image; do
        use_runtime "$runtime"
        : > "$PHP_RUN_LOG"

        WORKTREE_IN_RUNTIME=1 run bash "$STUBS_DIR/worktree" php -v
        [ "$status" -eq 0 ]
        [ "$(cat "$PHP_RUN_LOG")" = "$WORKTREE_REAL: -v" ]
    done
    [ ! -s "$DOCKER_LOG" ]
}

@test "without docker on PATH, fails instead of running on the host" {
    nodocker="$(path_without_docker)"
    for runtime in docker-compose docker-image; do
        use_runtime "$runtime"
        : > "$PHP_RUN_LOG"

        PATH="$nodocker" run bash "$STUBS_DIR/worktree" php -v
        [ "$status" -eq 1 ]
        [[ "$output" == *"not found"* ]]
        [ ! -s "$PHP_RUN_LOG" ]
    done
}

@test "inside the runtime, the main checkout still needs the option" {
    use_runtime docker-image
    use_main_checkout

    LARAVEL_SAIL=1 run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 1 ]
    [[ "$output" == *"WORKTREE_MAIN_CHECKOUT_PASSTHROUGH=true"* ]]
    [ ! -e "$PHP_RUN_LOG" ]
}

@test "setup and test still refuse the main checkout with the option set" {
    for runtime in native docker-compose docker-image; do
        use_runtime "$runtime"
        use_main_checkout
        enable_main_checkout
        cp "$WORKTREE_DIR/.env.testing" "$MAIN_REPO/"

        run bash "$STUBS_DIR/test"
        [ "$status" -eq 1 ]
        [[ "$output" == *"this is the main checkout"* ]]
        [[ "$output" != *"WORKTREE_MAIN_CHECKOUT_PASSTHROUGH"* ]]

        run bash "$STUBS_DIR/worktree-setup"
        [[ "$output" == *"Nothing to set up"* ]]
        [ ! -s "$DOCKER_LOG" ]
        [ ! -e "$PHP_RUN_LOG" ]
        [ "$(cat "$MAIN_REPO/.env.testing")" = "$(cat "$WORKTREE_DIR/.env.testing")" ]
    done
}

@test "WORKTREE_DOCKER_ENV reaches every container by name, in worktrees and the main checkout" {
    use_runtime docker-image
    echo 'WORKTREE_DOCKER_ENV="PHPSTAN_MAX_PROCESSES=4 FOO=a=b"' >> "$MAIN_REPO/.worktree-isolation.env"
    log_docker_argv

    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]
    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]
    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    use_main_checkout
    enable_main_checkout
    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]

    run grep -c -- "run " "$DOCKER_LOG"
    runs="$output"
    [ "$runs" -ge 4 ]
    run grep -c -- "-e PHPSTAN_MAX_PROCESSES=4 -e FOO=a=b " "$DOCKER_LOG"
    [ "$output" -eq "$runs" ]
    run grep -c -F -- "[-e] [PHPSTAN_MAX_PROCESSES] [-e] [FOO]" "$DOCKER_ARGV_LOG"
    [ "$output" -eq "$runs" ]
}

@test "test's testing environment wins over WORKTREE_DOCKER_ENV" {
    use_runtime docker-image
    echo 'WORKTREE_DOCKER_ENV="DB_DATABASE=other"' >> "$MAIN_REPO/.worktree-isolation.env"

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]

    output="$(cat "$DOCKER_LOG")"
    [[ "$output" == *"-e DB_DATABASE=testing_wt_feature-auth-c0de"* ]]
    [[ "$output" != *"DB_DATABASE=other"* ]]
}

@test "rejects a WORKTREE_DOCKER_ENV entry that isn't KEY=value" {
    use_runtime docker-image
    echo 'WORKTREE_DOCKER_ENV="FOO=1 BAR"' >> "$MAIN_REPO/.worktree-isolation.env"

    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 1 ]
    [[ "$output" == *"WORKTREE_DOCKER_ENV entry 'BAR' isn't KEY=value"* ]]
    run grep -- "run " "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}
