#!/usr/bin/env bash
#
# Shared helpers sourced by stubs/bin/worktree-setup and stubs/bin/test.
# Not a standalone executable — never added to composer.json's "bin" list.

# Derives a Docker Compose project name from a base name and a worktree
# directory name, using the same sanitization pattern as
# TestDatabaseResolver::derive() (src/TestDatabaseResolver.php): lowercase,
# collapse anything outside [a-z0-9] into a single hyphen, trim leading/
# trailing hyphens.
derive_compose_project_name() {
    local base="$1" wt="$2"
    local suffix
    suffix="$(echo "$wt" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
    echo "${base}-${suffix:-worktree}"
}

# Builds the base `docker run` args (bind mount, workdir, network, forwarded
# env vars) shared by every docker-image invocation. Reads PROJECT_ROOT,
# WORKDIR, NETWORK, DB_PER_WORKTREE_KEY, and WORKTREE_EXTRA_ENV_VARS from the
# caller's environment and appends to a DOCKER_ARGS array the caller declared.
build_docker_image_args() {
    DOCKER_ARGS=(
        docker run --rm
        -v "$PROJECT_ROOT:$WORKDIR"
        -w "$WORKDIR"
    )

    if [[ -n "$NETWORK" ]]; then
        DOCKER_ARGS+=(--network "$NETWORK")
    fi

    local DEFAULT_ENV_VARS=(
        APP_ENV APP_KEY APP_DEBUG
        DB_CONNECTION DB_HOST DB_PORT DB_DATABASE DB_USERNAME DB_PASSWORD DB_SSL_VERIFY_SERVER_CERT
        BCRYPT_ROUNDS CACHE_DRIVER MAIL_MAILER QUEUE_CONNECTION SESSION_DRIVER
        TELESCOPE_ENABLED
        "$DB_PER_WORKTREE_KEY"
    )

    local EXTRA_VARS
    IFS=' ' read -ra EXTRA_VARS <<< "${WORKTREE_EXTRA_ENV_VARS:-}"
    local ENV_VARS=("${DEFAULT_ENV_VARS[@]}" "${EXTRA_VARS[@]}")

    for var in "${ENV_VARS[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            DOCKER_ARGS+=(-e "$var=${!var}")
        fi
    done
}
