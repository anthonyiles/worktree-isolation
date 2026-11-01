#!/usr/bin/env bash
#
# Shared helpers sourced by stubs/bin/worktree, worktree-install,
# worktree-setup, and test.

# shellcheck disable=SC2034 # the variables are read by the sourcing scripts
load_worktree_config() {
    # The scripts live in vendor/, so resolve the project root via git.
    PROJECT_ROOT="$(git rev-parse --show-toplevel)"
    WORKTREE_BASENAME="$(basename "$PROJECT_ROOT")"

    load_env_file "$PROJECT_ROOT/.worktree-isolation.env"

    RUNTIME="${WORKTREE_RUNTIME:-native}"
    TESTING_ENV_FILE="${WORKTREE_TESTING_ENV_FILE:-.env.testing}"
    TESTING_ENV_EXAMPLE="${WORKTREE_TESTING_ENV_EXAMPLE:-.env.testing.example}"

    # docker-image driver settings
    IMAGE="${WORKTREE_DOCKER_IMAGE:-}"
    NETWORK="${WORKTREE_DOCKER_NETWORK:-}"
    WORKDIR="${WORKTREE_DOCKER_WORKDIR:-/var/www/html}"

    # docker-compose driver settings
    COMPOSE_SERVICE="${WORKTREE_COMPOSE_SERVICE:-app}"

    # Containers run as the host user so files they write into the worktree
    # (vendor/, node_modules/, storage/) stay owned by it. That UID may have no
    # passwd entry in the image, hence a HOME that's always writable.
    CONTAINER_USER_ARGS=(-u "$(id -u):$(id -g)" -e HOME=/tmp)
}

in_main_checkout() {
    [[ "$(git rev-parse --path-format=absolute --git-dir)" == "$(git rev-parse --path-format=absolute --git-common-dir)" ]]
}

require_worktree() {
    if in_main_checkout; then
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
            COMPOSE_ARGS=(docker compose)
            # The main checkout's stack runs under Compose's default project name.
            if ! in_main_checkout; then
                local base="${WORKTREE_COMPOSE_PROJECT_BASE:-}"
                if [[ -z "$base" ]]; then
                    # Configs written before install recorded this: fall back to
                    # what install derives, the main checkout's directory name.
                    base="$(slugify "$(basename "$(main_checkout_dir)")")"
                fi
                COMPOSE_PROJECT_NAME="$(derive_compose_project_name "$base" "$WORKTREE_BASENAME")"
                COMPOSE_ARGS+=(-p "$COMPOSE_PROJECT_NAME")
            fi
            if [[ -n "${WORKTREE_COMPOSE_FILE:-}" ]]; then
                COMPOSE_ARGS+=(-f "$WORKTREE_COMPOSE_FILE")
            fi
            COMPOSE_EXEC_ARGS=("${COMPOSE_ARGS[@]}" exec "${CONTAINER_USER_ARGS[@]}")
            # Sail's compose file builds and serves as these, as vendor/bin/sail sets them.
            export WWWUSER="${WWWUSER:-$(id -u)}" WWWGROUP="${WWWGROUP:-$(id -g)}"
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

# Same sanitization as WorktreeDatabaseResolver::worktreeSuffix(), and what
# worktree-install applies to the compose project base: lowercase, collapse
# anything outside [a-z0-9] into a single hyphen, trim leading/trailing
# hyphens. LC_ALL=C works on bytes like PHP: in a UTF-8 locale, tr and sed
# would keep letters like "ë".
slugify() {
    local slug
    slug="$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
    echo "${slug:-worktree}"
}

derive_compose_project_name() {
    echo "$1-$(slugify "$2")"
}

sha1_hex() {
    if command -v sha1sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha1sum | cut -d' ' -f1
    else
        printf '%s' "$1" | shasum -a 1 | cut -d' ' -f1
    fi
}

# Must match WorktreeDatabaseResolver::derive(), which clean --stale uses.
# Setup and test derive names here, before the stack starts, and PHP only
# creates them. An overlong suffix is truncated and tagged with a hash of the
# full suffix, as in WorktreeDatabaseResolver::fit(). Lengths count bytes,
# like PHP's strlen().
derive_worktree_database_name() {
    local LC_ALL=C
    local base="${1%%_wt_*}" suffix hash room
    [[ -n "$base" ]] || return 1
    suffix="$(slugify "$2")"
    if (( ${#base} + 4 + ${#suffix} > $3 )); then
        hash="$(sha1_hex "$suffix")"
        hash="${hash:0:8}"
        room=$(( $3 - ${#base} - 4 - ${#hash} - 1 ))
        (( room >= 1 )) || return 1
        suffix="${suffix:0:room}"
        suffix="${suffix%-}-${hash}"
    fi
    echo "${base}_wt_${suffix}"
}

derive_dev_database_name() {
    derive_worktree_database_name "$1" "$2" 64
}

# The "test" check runs on the base: a worktree named e.g. "test-refactor"
# must not make a non-test base pass.
derive_test_database_name() {
    local base="${1%%_wt_*}"
    [[ "$(printf '%s' "$base" | LC_ALL=C tr '[:upper:]' '[:lower:]')" == *test* ]] || return 1
    derive_worktree_database_name "$base" "$2" 40
}

# Creates the per-worktree database named by DB_DATABASE, which bash already
# derived. Refuses anything that isn't a per-worktree name or is the main
# checkout's. Runs from the project root with DB_* and MAIN_DB_DATABASE in
# its environment, and prints "<name> created|existing" as its last line; the
# leading newline keeps that line intact if PHP emitted a notice first.
# The autoloader is the worktree's, which may hold an older release of this
# package, so only use what every release has.
# shellcheck disable=SC2016 # PHP code, expanded by PHP
ENSURE_DB_PHP='
    require "vendor/autoload.php";
    $name = (string) getenv("DB_DATABASE");
    if (! str_contains($name, "_wt_")) {
        fwrite(STDERR, "Refusing to create \"$name\": not a per-worktree database name.\n");
        exit(1);
    }
    if ($name === getenv("MAIN_DB_DATABASE")) {
        fwrite(STDERR, "Refusing to use $name: it is the main checkout database.\n");
        exit(1);
    }
    $created = WorktreeIsolation\TestDatabaseResolver::ensureExists(
        $name,
        getenv("DB_HOST") ?: "127.0.0.1",
        (int) (getenv("DB_PORT") ?: 3306),
        getenv("DB_USERNAME") ?: "",
        getenv("DB_PASSWORD") ?: "",
    );
    echo "\n", $name, $created ? " created" : " existing";
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
        "${CONTAINER_USER_ARGS[@]}"
        -v "$PROJECT_ROOT:$WORKDIR"
        -w "$WORKDIR"
    )

    if [[ -n "$NETWORK" ]]; then
        DOCKER_ARGS+=(--network "$NETWORK")
    fi
}

# Prints the key of every assignment in a dotenv file, once each.
env_file_keys() {
    local line seen=" "
    [[ -f "$1" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $ENV_LINE_PATTERN && "$seen" != *" ${BASH_REMATCH[2]} "* ]]; then
            seen+="${BASH_REMATCH[2]} "
            echo "${BASH_REMATCH[2]}"
        fi
    done < "$1"
}

# Usage: run_in_runtime [-e VAR=value]... command [args...]
# The values are exported and docker gets only their names (it reads the
# values from its environment), so secrets like DB_PASSWORD never show up in
# a process listing. The subshell keeps the exports from leaking.
run_in_runtime() (
    local cmd=()
    case "$RUNTIME" in
        docker-compose)
            cmd=("${COMPOSE_EXEC_ARGS[@]}" -T)
            ;;
        docker-image)
            build_docker_image_args
            cmd=("${DOCKER_ARGS[@]}")
            ;;
    esac

    while [[ "${1:-}" == -e ]]; do
        export "${2?}"
        [[ "$RUNTIME" == native ]] || cmd+=(-e "${2%%=*}")
        shift 2
    done

    case "$RUNTIME" in
        native)
            cd "$PROJECT_ROOT" && "$@"
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
)

# Dotenv values are parsed, never sourced: .env files aren't guaranteed to be
# valid shell (e.g. APP_NAME=My App), and sourcing would expand $ and
# backticks. A quoted value is taken verbatim up to its closing quote; an
# unquoted one loses a trailing " # comment" and surrounding whitespace.
# Matches parseEnvFile() in worktree-clean.
parse_env_value() {
    local value="$1"
    value="${value%$'\r'}"
    value="${value#"${value%%[![:space:]]*}"}"
    case "$value" in
        \"*)
            value="${value#\"}"
            value="${value%%\"*}"
            ;;
        \'*)
            value="${value#\'}"
            value="${value%%\'*}"
            ;;
        *)
            value="${value%%[[:space:]]#*}"
            value="${value%"${value##*[![:space:]]}"}"
            ;;
    esac
    printf '%s\n' "$value"
}

ENV_LINE_PATTERN='^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$'

# Reads KEY's value from a dotenv file (the last assignment wins).
env_file_value() {
    local file="$1" key="$2" line value=""
    [[ -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $ENV_LINE_PATTERN && "${BASH_REMATCH[2]}" == "$key" ]]; then
            value="$(parse_env_value "${BASH_REMATCH[3]}")"
        fi
    done < "$file"
    echo "$value"
}

# Exports every assignment in a dotenv file.
load_env_file() {
    local line
    [[ -f "$1" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $ENV_LINE_PATTERN ]]; then
            export "${BASH_REMATCH[2]}=$(parse_env_value "${BASH_REMATCH[3]}")"
        fi
    done < "$1"
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
