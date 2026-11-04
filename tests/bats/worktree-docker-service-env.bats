#!/usr/bin/env bats
#
# The docker-image runtime passing on the environment of the compose service
# that uses the image, read from a fake `docker compose config`.

load helpers

setup() {
    setup_docker_compose_worktree
    printf 'WORKTREE_RUNTIME=docker-image\nWORKTREE_DOCKER_IMAGE=sail-8.4/app\n' > "$WORKTREE_DIR/.worktree-isolation.env"
    touch "$WORKTREE_DIR/docker-compose.yml"

    export FAKE_COMPOSE_CONFIG="$BATS_TEST_TMPDIR/compose-config.yml"
    cat > "$FAKE_COMPOSE_CONFIG" <<'YAML'
name: myapp
services:
  horizon:
    environment:
      HORIZON: "1"
    image: sail-8.4/app
  laravel.test:
    build:
      context: /x/vendor/laravel/sail/runtimes/8.4
      dockerfile: Dockerfile
    environment:
      EMPTY: ""
      HOME: /root
      IGNITION_LOCAL_SITES_PATH: /home/me/my app
      LARAVEL_SAIL: "1"
      NOTHING: null
      PATH: /nowhere
      PHPSTAN_MAX_PROCESSES: "4"
      QUOTED: "say \"hi\"\\there"
      SINGLE: 'it''s'
      XDEBUG_MODE: "off"
    image: sail-8.4/app
    networks:
      sail: null
  mysql:
    environment:
      MYSQL_ROOT_PASSWORD: secret
    image: mysql/mysql-server:8.0
networks:
  sail:
    name: myapp_sail
YAML
}

docker_run_log() {
    grep -- "^run " "$DOCKER_LOG"
}

@test "passes the environment of the service that builds the image, by name" {
    log_docker_argv

    run bash "$STUBS_DIR/worktree" php vendor/bin/phpstan analyse
    [ "$status" -eq 0 ]

    run docker_run_log
    [[ "$output" == *"-e EMPTY= -e IGNITION_LOCAL_SITES_PATH=/home/me/my app -e LARAVEL_SAIL=1 -e PHPSTAN_MAX_PROCESSES=4 -e QUOTED=say \"hi\"\\there -e SINGLE=it's -e XDEBUG_MODE=off -v "* ]]
    [[ "$output" != *"HORIZON"* ]]
    [[ "$output" != *"MYSQL_ROOT_PASSWORD"* ]]
    [[ "$output" != *"NOTHING"* ]]
    [[ "$output" != *"/nowhere"* ]]
    [[ "$output" == *"-e HOME=/tmp "* ]]
    [[ "$output" != *"HOME=/root"* ]]

    run grep -F -- "[-e] [PHPSTAN_MAX_PROCESSES] [-e] [QUOTED]" "$DOCKER_ARGV_LOG"
    [ "$status" -eq 0 ]
}

@test "reads the compose file once per command, for setup and test too" {
    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    run grep -c -- "compose config" "$DOCKER_LOG"
    [ "$output" -eq 1 ]
    run grep -c -- "-e PHPSTAN_MAX_PROCESSES=4 " "$DOCKER_LOG"
    [ "$output" -ge 2 ]

    : > "$DOCKER_LOG"
    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]
    run grep -c -- "compose config" "$DOCKER_LOG"
    [ "$output" -eq 1 ]
    run grep -c -- "-e PHPSTAN_MAX_PROCESSES=4 " "$DOCKER_LOG"
    [ "$output" -eq 1 ]
}

@test "works in the main checkout too" {
    use_main_checkout
    echo "WORKTREE_MAIN_CHECKOUT_PASSTHROUGH=true" >> .worktree-isolation.env
    touch docker-compose.yml

    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]
    run docker_run_log
    [[ "$output" == *"-e LARAVEL_SAIL=1 "* ]]
}

@test "WORKTREE_DOCKER_ENV and test's testing environment win over the service's" {
    echo 'WORKTREE_DOCKER_ENV="XDEBUG_MODE=debug DB_DATABASE=other"' >> .worktree-isolation.env
    sed -i.bak 's/      EMPTY: ""/      DB_DATABASE: fromservice/' "$FAKE_COMPOSE_CONFIG"

    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]
    run docker_run_log
    [[ "$output" == *"-e XDEBUG_MODE=debug "* ]]
    [[ "$output" == *"-e DB_DATABASE=other "* ]]
    [[ "$output" != *"XDEBUG_MODE=off"* ]]

    : > "$DOCKER_LOG"
    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]
    output="$(cat "$DOCKER_LOG")"
    [[ "$output" == *"-e DB_DATABASE=testing_wt_feature-auth"* ]]
    [[ "$output" != *"DB_DATABASE=other"* ]]
    [[ "$output" != *"DB_DATABASE=fromservice"* ]]
}

@test "WORKTREE_DOCKER_SERVICE picks another service" {
    echo "WORKTREE_DOCKER_SERVICE=horizon" >> .worktree-isolation.env

    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]
    run docker_run_log
    [[ "$output" == *"-e HORIZON=1 "* ]]
    [[ "$output" != *"LARAVEL_SAIL"* ]]
}

@test "an empty WORKTREE_DOCKER_SERVICE turns it off" {
    echo "WORKTREE_DOCKER_SERVICE=" >> .worktree-isolation.env

    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]
    run grep -- "compose config" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
    run docker_run_log
    [[ "$output" != *"LARAVEL_SAIL"* ]]
}

@test "warns about a WORKTREE_DOCKER_SERVICE that isn't in the compose file" {
    echo "WORKTREE_DOCKER_SERVICE=nope" >> .worktree-isolation.env

    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: no 'nope' service in the compose file"* ]]
}

@test "falls back to the first service using the image when none builds it" {
    sed -i.bak '/^    build:$/,/^      dockerfile:/d' "$FAKE_COMPOSE_CONFIG"

    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]
    run docker_run_log
    [[ "$output" == *"-e HORIZON=1 "* ]]
}

@test "passes nothing, quietly, when no service uses the image" {
    printf 'WORKTREE_RUNTIME=docker-image\nWORKTREE_DOCKER_IMAGE=other/app\n' > .worktree-isolation.env

    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]
    [[ "$output" != *"Warning"* ]]
    run docker_run_log
    [[ "$output" != *"LARAVEL_SAIL"* ]]
}

@test "skips the compose file read without a compose file" {
    rm docker-compose.yml

    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]
    [[ "$output" != *"Warning"* ]]
    run grep -- "compose config" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}

@test "reads WORKTREE_COMPOSE_FILE, or a COMPOSE_FILE set in .env" {
    rm docker-compose.yml
    echo "WORKTREE_COMPOSE_FILE=docker/compose.yml" >> .worktree-isolation.env

    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]
    run grep -- "compose -f docker/compose.yml config" "$DOCKER_LOG"
    [ "$status" -eq 0 ]

    sed -i.bak '/^WORKTREE_COMPOSE_FILE=/d' .worktree-isolation.env
    echo "COMPOSE_FILE=docker/compose.yml" > .env
    : > "$DOCKER_LOG"
    run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]
    run grep -- "compose config" "$DOCKER_LOG"
    [ "$status" -eq 0 ]
}

@test "warns and carries on when docker compose config fails" {
    FAKE_COMPOSE_CONFIG_FAILS=1 run bash "$STUBS_DIR/worktree" php -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: 'docker compose config' failed"* ]]
    run docker_run_log
    [[ "$output" == *"--entrypoint php sail-8.4/app -v"* ]]
}
