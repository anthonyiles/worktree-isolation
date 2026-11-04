#!/usr/bin/env bats
#
# Integration tests for the docker-image runtime in stubs/bin/worktree's
# passthrough and stubs/bin/test, using a fake `docker` executable so no real
# Docker daemon is needed.

load helpers

setup() {
    setup_docker_compose_worktree
    cat > "$WORKTREE_DIR/.worktree-isolation.env" <<ENV
WORKTREE_RUNTIME=docker-image
WORKTREE_DOCKER_IMAGE=myapp:latest
ENV
    echo "APP_ENV=testing" >> "$WORKTREE_DIR/.env.testing"
}

@test "passthrough does not forward the testing environment into the container" {
    run bash "$STUBS_DIR/worktree" php artisan migrate
    [ "$status" -eq 0 ]

    run grep -- "run " "$DOCKER_LOG"
    [[ "$output" == *"--entrypoint php myapp:latest artisan migrate"* ]]
    [[ "$output" != *"APP_ENV="* ]]
    [[ "$output" != *"DB_DATABASE="* ]]
}

@test "passthrough keeps stdin open so piped input reaches the command" {
    run bash "$STUBS_DIR/worktree" mysql < /dev/null
    [ "$status" -eq 0 ]

    run grep -- "run " "$DOCKER_LOG"
    [[ "$output" == *" -i "* ]]
    [[ "$output" != *" -t "* ]]
}

@test "test still forwards the testing environment" {
    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]

    output="$(cat "$DOCKER_LOG")"
    [[ "$output" == *"-e APP_ENV=testing"* ]]
    [[ "$output" == *"-e DB_DATABASE=testing_wt_feature-auth"* ]]
}

@test "passthrough and test run as the host user so the worktree's files stay owned by it" {
    run bash "$STUBS_DIR/worktree" composer install
    [ "$status" -eq 0 ]
    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]

    run grep -c -- "run --rm -u $(id -u):$(id -g) -e HOME=/tmp " "$DOCKER_LOG"
    [ "$output" -eq 2 ]
}

@test "test passes credentials by name, keeping their values off the command line" {
    log_docker_argv
    echo "DB_PASSWORD=s3cret" >> "$WORKTREE_DIR/.env.testing"

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]

    run grep -F -- "[-e] [DB_PASSWORD]" "$DOCKER_ARGV_LOG"
    [ "$status" -eq 0 ]
    run grep -c -- "s3cret" "$DOCKER_ARGV_LOG"
    [ "$output" -eq 0 ]
    run grep -- "-e DB_PASSWORD=s3cret" "$DOCKER_LOG"
    [ "$status" -eq 0 ]
}

@test "mounts the main clone's git dir read-write where the worktree's .git file points" {
    common="$(git -C "$MAIN_REPO" rev-parse --path-format=absolute --git-common-dir)"

    run bash "$STUBS_DIR/worktree" git status
    [ "$status" -eq 0 ]

    run grep -- "run " "$DOCKER_LOG"
    [[ "$output" == *"-v $(pwd -P):/var/www/html -v $common:$common -w /var/www/html "* ]]
    [[ "$output" == *"-e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0=*"* ]]
    [[ "$output" == *"-e GIT_CONFIG_KEY_1=gc.worktreePruneExpire -e GIT_CONFIG_VALUE_1=never"* ]]
}

# Runs `docker run` on the host instead: the worktree's mount is copied to its
# target and any other mount is symlinked, so a .git pointer resolves only
# through the mounts.
fake_docker_run() {
    cat > "$FAKE_BIN/docker" <<'SCRIPT'
#!/usr/bin/env bash
[[ "$1" == run ]] || exit 0
shift
mounts=() workdir= entrypoint=
while [[ "$1" == -* ]]; do
    case "$1" in
        -v) mounts+=("$2"); shift 2 ;;
        -w) workdir="$2"; shift 2 ;;
        --entrypoint) entrypoint="$2"; shift 2 ;;
        -e) export "$2"; shift 2 ;;
        -u|--network) shift 2 ;;
        *) shift ;;
    esac
done
shift # image
for mount in "${mounts[@]}"; do
    mkdir -p "$(dirname "${mount#*:}")"
    if [[ "${mount#*:}" == "$workdir" ]]; then
        cp -R "${mount%%:*}" "$workdir"
    else
        ln -s "${mount%%:*}" "${mount#*:}"
    fi
done
cd "$workdir" && exec "$entrypoint" "$@"
SCRIPT
}

@test "git works in a worktree added with --relative-paths" {
    relative_dir="$BATS_TEST_TMPDIR/worktrees/relative"
    git -C "$MAIN_REPO" worktree add -q --relative-paths -b relative "$relative_dir"
    cp "$WORKTREE_DIR/.worktree-isolation.env" "$relative_dir/"
    container="$BATS_TEST_TMPDIR/container"
    echo "WORKTREE_DOCKER_WORKDIR=$container/var/www/html" >> "$relative_dir/.worktree-isolation.env"
    fake_docker_run
    cd "$relative_dir"

    run bash "$STUBS_DIR/worktree" git rev-parse --show-toplevel
    [ "$status" -eq 0 ]
    # pwd -P: git prints the resolved path, e.g. /private/var on macOS.
    [ "$output" = "$(cd "$container/var/www/html" && pwd -P)" ]
    [ -L "$container/var/main/.git" ]
}

@test "test takes database credentials the testing env file leaves out from .env, and passes no blanks" {
    sed -i.bak '/^DB_HOST=/d; /^DB_USERNAME=/d' "$WORKTREE_DIR/.env.testing"
    printf 'DB_HOST=mysql\n' > "$WORKTREE_DIR/.env"

    run bash "$STUBS_DIR/test"
    [ "$status" -eq 0 ]

    output="$(cat "$DOCKER_LOG")"
    [[ "$output" == *"-e DB_HOST=mysql "* ]]
    [[ "$output" == *"-e DB_PASSWORD= "* ]]
    [[ "$output" != *"DB_USERNAME="* ]]
}
