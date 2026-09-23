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
    TESTING_ENV_EXAMPLE="${WORKTREE_TESTING_ENV_EXAMPLE:-.env.testing.example}"
    DB_PER_WORKTREE_KEY="${WORKTREE_DB_PER_WORKTREE_KEY:-TEST_DB_PER_WORKTREE}"

    # docker-image driver settings
    IMAGE="${WORKTREE_DOCKER_IMAGE:-}"
    NETWORK="${WORKTREE_DOCKER_NETWORK:-}"
    WORKDIR="${WORKTREE_DOCKER_WORKDIR:-/var/www/html}"

    # docker-compose driver settings
    COMPOSE_SERVICE="${WORKTREE_COMPOSE_SERVICE:-app}"
}

require_worktree() {
    if [[ "$(git rev-parse --path-format=absolute --git-dir)" == "$(git rev-parse --path-format=absolute --git-common-dir)" ]]; then
        echo "Error: this is the main checkout, not a git worktree. Run this from inside a worktree." >&2
        exit 1
    fi
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
            local base="${WORKTREE_COMPOSE_PROJECT_BASE:-}"
            if [[ -z "$base" ]]; then
                # Configs written before install recorded this: fall back to
                # what install derives, the main checkout's directory name.
                base="$(slugify "$(basename "$(main_checkout_dir)")")"
            fi
            COMPOSE_PROJECT_NAME="$(derive_compose_project_name "$base" "$WORKTREE_BASENAME")"
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

main_checkout_dir() {
    dirname "$(git rev-parse --path-format=absolute --git-common-dir)"
}

# The main checkout's own database names. Worktrees derive theirs from these
# and must never end up using them.
main_dev_database() {
    env_file_value "$(main_checkout_dir)/.env" DB_DATABASE
}

main_test_database() {
    local main_dir name
    main_dir="$(main_checkout_dir)"
    name="$(env_file_value "$main_dir/$TESTING_ENV_FILE" DB_DATABASE)"
    [[ -n "$name" ]] || name="$(env_file_value "$main_dir/$TESTING_ENV_EXAMPLE" DB_DATABASE)"
    echo "$name"
}

# Same sanitization as TestDatabaseResolver::worktreeSuffix() and
# worktree-install's sanitizeComposeProjectBase(): lowercase, collapse
# anything outside [a-z0-9] into a single hyphen, trim leading/trailing
# hyphens.
slugify() {
    local slug
    slug="$(echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
    echo "${slug:-worktree}"
}

derive_compose_project_name() {
    echo "$1-$(slugify "$2")"
}

# Must match DevDatabaseResolver::derive() and TestDatabaseResolver::derive().
# Setup writes these names before the stack starts, so they can't wait for
# PHP inside the runtime.
derive_worktree_database_name() {
    local base="${1%%_wt_*}" derived
    [[ -n "$base" ]] || return 1
    derived="${base}_wt_$(slugify "$2")"
    (( ${#derived} <= $3 )) || return 1
    echo "$derived"
}

derive_dev_database_name() {
    derive_worktree_database_name "$1" "$2" 64
}

# The "test" check runs on the base: a worktree named e.g. "test-refactor"
# must not make a non-test base pass.
derive_test_database_name() {
    local base="${1%%_wt_*}"
    [[ "$(echo "$base" | tr '[:upper:]' '[:lower:]')" == *test* ]] || return 1
    derive_worktree_database_name "$base" "$2" 40
}

# Creates a per-worktree database, re-deriving its name with the PHP
# resolver as a cross-check. Runs from the project root with RESOLVER_CLASS
# (defaults to the test resolver), WORKTREE_BASENAME, MAIN_DB_DATABASE and
# DB_* in its environment, and prints "<name> created|existing" as its last line; the
# leading newline keeps that line intact if PHP emitted a notice first.
ENSURE_DB_PHP='
    require "vendor/autoload.php";
    $class = getenv("RESOLVER_CLASS") ?: "WorktreeIsolation\\TestDatabaseResolver";
    $name = $class::derive(getenv("DB_DATABASE") ?: "testing", getenv("WORKTREE_BASENAME") ?: "worktree");
    if ($name === getenv("MAIN_DB_DATABASE")) {
        fwrite(STDERR, "Refusing to use $name: it is the main checkout database.\n");
        exit(1);
    }
    $created = $class::ensureExists(
        $name,
        getenv("DB_HOST") ?: "127.0.0.1",
        (int) (getenv("DB_PORT") ?: 3306),
        getenv("DB_USERNAME") ?: "",
        getenv("DB_PASSWORD") ?: "",
    );
    echo "\n", $name, $created === true ? " created" : " existing";
'

# Validates ENSURE_DB_PHP's output and prints its last line.
parse_ensure_db_output() {
    local last="${1##*$'\n'}"
    [[ "$last" =~ ^[a-z0-9_-]+\ (created|existing)$ ]] || return 1
    echo "$last"
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

# Appends "-e VAR=value" pairs for the testing environment to TEST_ENV.
append_testing_env_args() {
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
            TEST_ENV+=(-e "$var=${!var}")
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
    value="$(grep -E "^${key}=" "$file" 2> /dev/null | tail -n 1)" || return 0
    value="${value#*=}"
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    echo "$value"
}

# The value goes through ENVIRON rather than a sed expression, so it's never
# interpreted.
set_env_file_value() {
    local file="$1" key="$2" value="$3" tmp
    tmp="$(mktemp)"
    KEY="$key" VALUE="$value" awk '
        BEGIN { prefix = ENVIRON["KEY"] "=" }
        index($0, prefix) == 1 { print prefix ENVIRON["VALUE"]; found = 1; next }
        { print }
        END { if (!found) print prefix ENVIRON["VALUE"] }
    ' "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

is_mysql_connection() {
    [[ "$(env_file_value "$1" DB_CONNECTION)" =~ ^(mysql|mariadb)$ ]]
}
