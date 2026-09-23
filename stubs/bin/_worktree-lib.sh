#!/usr/bin/env bash
#
# Shared helpers sourced by stubs/bin/worktree, worktree-setup, and test.

# shellcheck disable=SC2034 # the variables are read by the sourcing scripts
load_worktree_config() {
    # The scripts live in vendor/, so resolve the project root via git.
    PROJECT_ROOT="$(git rev-parse --show-toplevel)"
    WORKTREE_BASENAME="$(basename "$PROJECT_ROOT")"

    local conf_file="$PROJECT_ROOT/.worktree-isolation.env"
    if [[ -f "$conf_file" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$conf_file"
        set +a
    fi

    RUNTIME="${WORKTREE_RUNTIME:-native}"
    TESTING_ENV_FILE="${WORKTREE_TESTING_ENV_FILE:-.env.testing}"
    DB_PER_WORKTREE_KEY="${WORKTREE_DB_PER_WORKTREE_KEY:-TEST_DB_PER_WORKTREE}"
    RESOLVER_CLASS="${WORKTREE_RESOLVER_CLASS:-WorktreeIsolation\\TestDatabaseResolver}"

    # docker-image driver settings
    IMAGE="${WORKTREE_DOCKER_IMAGE:-}"
    NETWORK="${WORKTREE_DOCKER_NETWORK:-}"
    WORKDIR="${WORKTREE_DOCKER_WORKDIR:-/var/www/html}"

    # docker-compose driver settings
    COMPOSE_SERVICE="${WORKTREE_COMPOSE_SERVICE:-app}"
}

validate_runtime() {
    case "$RUNTIME" in
        native)
            ;;
        docker-compose)
            if ! docker compose version > /dev/null 2>&1; then
                echo "Error: 'docker compose' not found. Install Docker with the Compose plugin." >&2
                exit 1
            fi
            if [[ -z "${WORKTREE_COMPOSE_PROJECT_BASE:-}" ]]; then
                echo "Error: WORKTREE_COMPOSE_PROJECT_BASE must be set for the docker-compose runtime." >&2
                echo "Re-run 'vendor/bin/worktree install --runtime=docker-compose --force' to regenerate .worktree-isolation.env." >&2
                exit 1
            fi
            COMPOSE_PROJECT_NAME="$(derive_compose_project_name "$WORKTREE_COMPOSE_PROJECT_BASE" "$WORKTREE_BASENAME")"
            COMPOSE_ARGS=(docker compose -p "$COMPOSE_PROJECT_NAME")
            if [[ -n "${WORKTREE_COMPOSE_FILE:-}" ]]; then
                COMPOSE_ARGS+=(-f "$WORKTREE_COMPOSE_FILE")
            fi
            ;;
        docker-image)
            if [[ -z "$IMAGE" ]]; then
                echo "Error: WORKTREE_DOCKER_IMAGE must be set for the docker-image runtime." >&2
                exit 1
            fi
            if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
                echo "Error: Docker image '$IMAGE' not found." >&2
                echo "Build it first (e.g. 'docker compose build' or 'vendor/bin/sail build')." >&2
                exit 1
            fi
            ;;
        *)
            echo "Error: Unknown WORKTREE_RUNTIME '$RUNTIME'. Use: native, docker-compose, or docker-image." >&2
            exit 1
            ;;
    esac
}

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

build_docker_image_args() {
    DOCKER_ARGS=(
        docker run --rm
        -v "$PROJECT_ROOT:$WORKDIR"
        -w "$WORKDIR"
    )

    if [[ -n "$NETWORK" ]]; then
        DOCKER_ARGS+=(--network "$NETWORK")
    fi
}

forward_testing_env_vars() {
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

# Usage: run_in_runtime [-e VAR=value]... command [args...]
run_in_runtime() {
    local cmd
    case "$RUNTIME" in
        native)
            cmd=(env)
            ;;
        docker-compose)
            cmd=("${COMPOSE_ARGS[@]}" exec -T)
            ;;
        docker-image)
            build_docker_image_args
            cmd=("${DOCKER_ARGS[@]}")
            ;;
    esac

    while [[ "${1:-}" == -e ]]; do
        if [[ "$RUNTIME" == native ]]; then
            cmd+=("$2")
        else
            cmd+=(-e "$2")
        fi
        shift 2
    done

    case "$RUNTIME" in
        native)
            (cd "$PROJECT_ROOT" && "${cmd[@]}" "$@")
            ;;
        docker-compose)
            "${cmd[@]}" "$COMPOSE_SERVICE" "$@"
            ;;
        docker-image)
            local entrypoint="$1"
            shift
            "${cmd[@]}" --entrypoint "$entrypoint" "$IMAGE" "$@"
            ;;
    esac
}

# Reads KEY's value from a dotenv file without sourcing it (.env files aren't
# guaranteed to be valid shell).
env_file_value() {
    local file="$1" key="$2" value
    value="$(grep -E "^${key}=" "$file" | tail -n 1)" || return 0
    value="${value#*=}"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    echo "$value"
}

set_env_file_value() {
    local file="$1" key="$2" value="$3"
    if grep -q "^${key}=" "$file"; then
        sed -i.bak "s/^${key}=.*/${key}=${value}/" "$file"
        rm -f "$file.bak"
    else
        echo "${key}=${value}" >> "$file"
    fi
}
