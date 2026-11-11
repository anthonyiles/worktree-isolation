#!/usr/bin/env bash
#
# Shared helpers sourced by the scripts in stubs/bin.
#
# Logic lives here, in bash. PHP is only used to reach the database server,
# inside the runtime, through the short snippets below.

# Absolute paths for the current checkout, worked out once: TOPLEVEL,
# CHECKOUT_GIT_DIR, COMMON_GIT_DIR (the main clone's .git) and MAIN_DIR (the
# main checkout).
# shellcheck disable=SC2034 # the variables are read by the sourcing scripts
load_git_paths() {
    [[ -z "${COMMON_GIT_DIR:-}" ]] || return 0
    local paths
    paths="$(git rev-parse --path-format=absolute --show-toplevel --git-dir --git-common-dir)" || exit 1
    TOPLEVEL="${paths%%$'\n'*}"
    paths="${paths#*$'\n'}"
    CHECKOUT_GIT_DIR="${paths%%$'\n'*}"
    COMMON_GIT_DIR="${paths#*$'\n'}"
    MAIN_DIR="$(dirname "$COMMON_GIT_DIR")"
}

# Usage: load_worktree_config [--skip-if-missing]
# Reads the main checkout's .worktree-isolation.env, whichever checkout this
# is: a new worktree's branch doesn't get to choose the commands setup runs.
# Only WORKTREE_* keys are exported. Exits when the file is missing;
# --skip-if-missing exits 0 instead in a worktree, so the hook doesn't fail
# `git worktree add`.
# shellcheck disable=SC2034 # the variables are read by the sourcing scripts
load_worktree_config() {
    load_git_paths
    PROJECT_ROOT="$TOPLEVEL"

    if [[ ! -f "$MAIN_DIR/.worktree-isolation.env" ]]; then
        echo "Error: .worktree-isolation.env not found in the main checkout ($MAIN_DIR). Run vendor/bin/worktree install there first." >&2
        if [[ "${1:-}" == --skip-if-missing ]] && ! in_main_checkout; then
            exit 0
        fi
        exit 1
    fi
    load_env_file "$MAIN_DIR/.worktree-isolation.env" WORKTREE_

    # Names this worktree's databases and Compose stack.
    WORKTREE_KEY=""
    in_main_checkout || WORKTREE_KEY="$(worktree_key "$(basename "$CHECKOUT_GIT_DIR")")"

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
    load_git_paths
    [[ "$CHECKOUT_GIT_DIR" == "$COMMON_GIT_DIR" ]]
}

# Usage: worktree_key ID
# A worktree's databases and Compose stack are named after its git admin dir
# (.git/worktrees/<ID>), which git keeps unique within the clone, and this
# clone's id, so two clones sharing a database server don't collide.
worktree_key() {
    echo "$1-$(clone_id)"
}

# A random id for this clone, created on first use.
clone_id() {
    local file="$COMMON_GIT_DIR/worktree-isolation/clone-id"
    if [[ ! -s "$file" ]]; then
        mkdir -p "${file%/*}"
        od -An -N2 -tx1 /dev/urandom | tr -d ' \n' > "$file.$$"
        mv "$file.$$" "$file"
    fi
    head -n 1 "$file"
}

# Usage: require_worktree [hint]
require_worktree() {
    if in_main_checkout; then
        echo "Error: this is the main checkout, not a git worktree. Run this from inside a worktree." >&2
        [[ -z "${1:-}" ]] || echo "$1" >&2
        exit 1
    fi
}

# Already inside the runtime: Sail's container, or one this package started
# (see CONTAINER_ENV). There's no docker to reach it with, and no need to.
in_runtime() {
    [[ "${LARAVEL_SAIL:-}" == 1 || "${WORKTREE_IN_RUNTIME:-}" == 1 ]]
}

# The main checkout's stack is the user's own: commands go into it, but it's
# never started for them.
require_compose_service_running() {
    if ! "${COMPOSE_ARGS[@]}" ps --status running --services 2> /dev/null | grep -qxF "$COMPOSE_SERVICE"; then
        echo "Error: the '$COMPOSE_SERVICE' service isn't running in the main checkout's stack. Start it first (e.g. docker compose up -d)." >&2
        exit 1
    fi
}

# Usage: version_at_least VERSION MAJOR MINOR
version_at_least() {
    local major=0 minor=0
    if [[ "$1" =~ ([0-9]+)\.([0-9]+) ]]; then
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
    fi
    (( 10#$major > $2 || (10#$major == $2 && 10#$minor >= $3) ))
}

validate_runtime() {
    case "$RUNTIME" in
        native)
            ;;
        docker-compose)
            local version
            if ! version="$(docker compose version --short 2> /dev/null)"; then
                echo "Error: 'docker compose' not found. Install Docker with the Compose plugin." >&2
                exit 1
            fi
            COMPOSE_ARGS=(docker compose)
            # The main checkout's stack runs under Compose's default project name.
            if ! in_main_checkout; then
                # The worktree's override file uses !reset.
                if ! version_at_least "$version" 2 24; then
                    echo "Error: Docker Compose 2.24+ is required for worktree stacks. You have ${version:-an unknown version}." >&2
                    exit 1
                fi
                COMPOSE_PROJECT_NAME="$(derive_compose_project_name "$(compose_project_base)" "$WORKTREE_KEY")"
                COMPOSE_ARGS+=(-p "$COMPOSE_PROJECT_NAME")
                find_compose_files "$PROJECT_ROOT"
                local file
                for file in ${COMPOSE_FILES[@]+"${COMPOSE_FILES[@]}"}; do
                    COMPOSE_ARGS+=(-f "$file")
                done
                COMPOSE_BASE_ARGS=("${COMPOSE_ARGS[@]}")
                [[ ! -f "$(compose_override_file)" ]] || COMPOSE_ARGS+=(-f "$(compose_override_file)")
            elif [[ -n "${WORKTREE_COMPOSE_FILE:-}" ]]; then
                COMPOSE_ARGS+=(-f "$WORKTREE_COMPOSE_FILE")
            fi
            COMPOSE_EXEC_ARGS=("${COMPOSE_ARGS[@]}" exec "${CONTAINER_USER_ARGS[@]}" "${CONTAINER_ENV[@]}")
            # Sail's compose file builds and serves as these, as vendor/bin/sail sets them.
            export WWWUSER="${WWWUSER:-$(id -u)}" WWWGROUP="${WWWGROUP:-$(id -g)}"
            ;;
        docker-image)
            if [[ -z "$IMAGE" ]]; then
                echo "Error: WORKTREE_DOCKER_IMAGE must be set for the docker-image runtime." >&2
                exit 1
            fi
            if ! command -v docker > /dev/null 2>&1; then
                echo "Error: 'docker' not found. Install Docker, or run this inside the container." >&2
                exit 1
            fi
            if ! docker image inspect "$IMAGE" > /dev/null 2>&1; then
                echo "Error: Docker image '$IMAGE' not found." >&2
                echo "Build it first (e.g. 'docker compose build' or 'vendor/bin/sail build')." >&2
                exit 1
            fi
            local pair pairs=()
            read -ra pairs <<< "${WORKTREE_DOCKER_ENV:-}"
            for pair in ${pairs[@]+"${pairs[@]}"}; do
                if [[ ! "$pair" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                    echo "Error: WORKTREE_DOCKER_ENV entry '$pair' isn't KEY=value." >&2
                    exit 1
                fi
            done
            load_service_env
            ;;
        *)
            echo "Error: Unknown WORKTREE_RUNTIME '$RUNTIME'. Use: native, docker-compose, or docker-image." >&2
            exit 1
            ;;
    esac
}

# Usage: find_compose_files DIR
# Fills COMPOSE_FILES with the absolute paths of the compose files Compose
# would use in DIR: WORKTREE_COMPOSE_FILE, else COMPOSE_FILE (from the
# environment or DIR/.env), else the first default file and its override.
# Leaves out this worktree's override file, which setup adds to its .env's
# COMPOSE_FILE (see point_compose_at_worktree_stack).
find_compose_files() {
    local dir="$1" file value files=() override=""
    [[ -z "${CHECKOUT_GIT_DIR:-}" ]] || override="$(compose_override_file)"
    COMPOSE_FILES=()
    value="${COMPOSE_FILE:-$(env_file_value "$dir/.env" COMPOSE_FILE)}"
    if [[ -n "${WORKTREE_COMPOSE_FILE:-}" ]]; then
        COMPOSE_FILES=("$WORKTREE_COMPOSE_FILE")
    elif [[ -n "$value" ]]; then
        IFS="${COMPOSE_PATH_SEPARATOR:-:}" read -ra COMPOSE_FILES <<< "$value"
    else
        for file in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
            [[ -f "$dir/$file" ]] && COMPOSE_FILES=("$file") && break
        done
        for file in compose.override.yaml compose.override.yml docker-compose.override.yaml docker-compose.override.yml; do
            [[ ${#COMPOSE_FILES[@]} -gt 0 && -f "$dir/$file" ]] && COMPOSE_FILES+=("$file") && break
        done
    fi
    for file in ${COMPOSE_FILES[@]+"${COMPOSE_FILES[@]}"}; do
        [[ "$file" == /* ]] || file="$dir/$file"
        [[ "$file" == "$override" ]] || files+=("$file")
    done
    COMPOSE_FILES=(${files[@]+"${files[@]}"})
}

# Kept in the worktree's own git dir, out of the working tree.
compose_override_file() {
    echo "$CHECKOUT_GIT_DIR/worktree-isolation.compose.yml"
}

# Setup writes a worktree stack's override file before starting it. It drops
# every service's published ports, so stacks don't clash over host ports
# (commands reach them through exec, not ports), and mounts the main clone's
# git dir where the worktree's .git pointer resolves (see container_git_dir).
# With a relative pointer, whose target depends on the service's own mounts,
# no git dir is mounted.
write_compose_override() {
    local override services service git_dir
    override="$(compose_override_file)"
    rm -f "$override"
    COMPOSE_ARGS=("${COMPOSE_BASE_ARGS[@]}")
    [[ ${#COMPOSE_FILES[@]} -gt 0 ]] || return 0
    services="$("${COMPOSE_ARGS[@]}" config --services)" || return 1
    git_dir="$(container_git_dir)"

    {
        echo 'services:'
        while IFS= read -r service; do
            [[ -n "$service" ]] || continue
            printf '  %s:\n    ports: !reset []\n' "$(yaml_string "$service")"
            if [[ "$service" == "$COMPOSE_SERVICE" && -n "$git_dir" ]]; then
                printf '    volumes:\n      - type: bind\n        source: %s\n        target: %s\n' \
                    "$(yaml_string "$COMMON_GIT_DIR")" "$(yaml_string "$git_dir")"
            fi
        done <<< "$services"
    } > "$override"
    COMPOSE_ARGS+=(-f "$override")
    COMPOSE_EXEC_ARGS=("${COMPOSE_ARGS[@]}" exec "${CONTAINER_USER_ARGS[@]}" "${CONTAINER_ENV[@]}")
}

# Usage: point_compose_at_worktree_stack ENV_FILE
# Writes the worktree stack's project name and compose files into its .env,
# which Compose reads from the directory it runs in. A plain `docker compose
# exec` or `sail`, e.g. in a project's git hook, then reaches this worktree's
# stack rather than the main checkout's, or none. Sail passes SAIL_FILES as
# -f, which beats COMPOSE_FILE, so a SAIL_FILES gets the same files.
point_compose_at_worktree_stack() {
    local env_file="$1" files=() value
    set_env_file_value "$env_file" COMPOSE_PROJECT_NAME "$COMPOSE_PROJECT_NAME"
    [[ ${#COMPOSE_FILES[@]} -gt 0 ]] || return 0
    files=("${COMPOSE_FILES[@]}")
    [[ ! -f "$(compose_override_file)" ]] || files+=("$(compose_override_file)")

    value="$(IFS="${COMPOSE_PATH_SEPARATOR:-:}" && echo "${files[*]}")"
    [[ "$value" != *[[:space:]]* ]] || value="\"$value\""
    set_env_file_value "$env_file" COMPOSE_FILE "$value"

    if [[ -n "$(env_file_value "$env_file" SAIL_FILES)" ]]; then
        value="$(IFS=: && echo "${files[*]}")"
        [[ "$value" != *[[:space:]]* ]] || value="\"$value\""
        set_env_file_value "$env_file" SAIL_FILES "$value"
    fi
}

# Double-quotes a YAML string, escaping $ from Compose's interpolation too.
yaml_string() {
    local value="${1//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "${value//\$/\$\$}"
}

main_checkout_dir() {
    load_git_paths
    echo "$MAIN_DIR"
}

# The main checkout's own database names. Worktrees derive theirs from these
# and must never end up using them.
main_dev_database() {
    env_file_value "$(main_checkout_dir)/.env" DB_DATABASE
}

# The main checkout's test database, as its tests see it. Worktrees must
# never use it.
main_test_database() {
    test_db_setting "$(main_checkout_dir)" DB_DATABASE || true
}

# Worktrees' test databases are named after the main checkout's development
# database, "{name}_wt_{worktree}_test", so no testing env file is needed,
# and sort next to the worktree's development database.
# The name is cut to 16 bytes to leave the worktree room within 40. Falls
# back to "testing" when .env has no database on a server.
test_database_base() {
    local LC_ALL=C env name=""
    env="$(main_checkout_dir)/.env"
    if [[ "$(env_file_value "$env" DB_CONNECTION)" =~ $SERVER_CONNECTIONS ]]; then
        name="$(env_file_value "$env" DB_DATABASE)"
        name="${name%%_wt_*}"
        name="${name:0:16}"
        while [[ "$name" == *[_-] ]]; do
            name="${name%?}"
        done
    fi
    echo "${name:-testing}"
}

# Connections whose per-worktree databases are created on a database server.
# SQLite's are files in the worktree (see sqlite_worktree_path).
SERVER_CONNECTIONS='^(mysql|mariadb|pgsql)$'

# The connection the tests use.
tests_connection() {
    test_db_setting "$PROJECT_ROOT" DB_CONNECTION || true
}

# Usage: test_db_setting DIR KEY
# KEY as DIR's tests see it: phpunit.xml (else phpunit.xml.dist), then the
# testing env file, then .env, which Laravel loads when there's no testing
# env file. Fails when none sets it, so callers don't pass a blank that
# would override .env.
test_db_setting() {
    local file
    phpunit_value "$1" "$2" && return
    for file in "$1/$TESTING_ENV_FILE" "$1/.env"; do
        if [[ $'\n'"$(env_file_keys "$file")"$'\n' == *$'\n'"$2"$'\n'* ]]; then
            env_file_value "$file" "$2"
            return
        fi
    done
    return 1
}

# The connection settings passed to the database snippets.
DB_SETTING_KEYS=(DB_CONNECTION DB_HOST DB_PORT DB_SOCKET DB_USERNAME DB_PASSWORD DB_CHARSET DB_COLLATION DB_SSLMODE MYSQL_ATTR_SSL_CA)

# Usage: sqlite_worktree_path VALUE
# A SQLite DB_DATABASE as the worktree should have it, so it doesn't share
# the main checkout's file, and the file that is on the host, tab-separated.
# Laravel's default (no value) and relative paths are already the
# worktree's own. An absolute path into the main checkout moves to the same
# place in the worktree; natively, one outside the project moves into the
# worktree's database/. In a Docker runtime the project is always mounted at
# WORKDIR, so a path under it is the worktree's own, and one outside it
# can't be kept apart: that fails. Prints nothing for an in-memory database.
sqlite_worktree_path() {
    local value="$1"
    case "$value" in
        :memory: | *mode=memory*)
            return 0
            ;;
        "")
            printf '\t%s\n' "$PROJECT_ROOT/database/database.sqlite"
            ;;
        /*)
            if [[ "$RUNTIME" != native ]]; then
                [[ "$value" == "$WORKDIR"/* ]] || return 1
                printf '%s\t%s\n' "$value" "$PROJECT_ROOT/${value#"$WORKDIR"/}"
            elif [[ "$value" == "$PROJECT_ROOT"/* ]]; then
                printf '%s\t%s\n' "$value" "$value"
            elif [[ "$value" == "$MAIN_DIR"/* ]]; then
                printf '%s\t%s\n' "$PROJECT_ROOT/${value#"$MAIN_DIR"/}" "$PROJECT_ROOT/${value#"$MAIN_DIR"/}"
            else
                printf '%s\t%s\n' "$PROJECT_ROOT/database/${value##*/}" "$PROJECT_ROOT/database/${value##*/}"
            fi
            ;;
        *)
            printf '%s\t%s\n' "$value" "$PROJECT_ROOT/$value"
            ;;
    esac
}

# Usage: ensure_sqlite_file PATH
# Prints "created" or "existing".
ensure_sqlite_file() {
    if [[ -e "$1" ]]; then
        echo existing
    else
        mkdir -p "$(dirname "$1")" && : > "$1" && echo created
    fi
}

# Usage: db_env_args test|development DIR
# Fills DB_ENV with "-e KEY=value" for the connection settings a kind of
# database uses in DIR's checkout: the tests' (see test_db_setting), or
# .env's. Settings no file has are left out.
db_env_args() {
    local key value keys
    DB_ENV=()
    keys=$'\n'"$(env_file_keys "$2/.env")"$'\n'
    for key in "${DB_SETTING_KEYS[@]}"; do
        if [[ "$1" == test ]]; then
            value="$(test_db_setting "$2" "$key")" || continue
        else
            [[ "$keys" == *$'\n'"$key"$'\n'* ]] || continue
            value="$(env_file_value "$2/.env" "$key")"
        fi
        DB_ENV+=(-e "$key=$value")
    done
}

# Warns when phpunit.xml's DB_DATABASE beats the per-worktree one, which
# vendor/bin/worktree test passes in the environment: an <env> with
# force="true", or a <server>, which PHPUnit always writes to $_SERVER,
# where Laravel looks first.
warn_if_phpunit_forces_database() {
    local file element
    file="$(phpunit_file "$PROJECT_ROOT")" || return 0
    element="$(phpunit_variable "$file" DB_DATABASE)"
    if [[ "$element" == '<server'* || "$(xml_attribute "$element" force)" =~ ^(true|1)$ ]]; then
        echo "Warning: phpunit.xml sets DB_DATABASE with <server> or force=\"true\", so tests ignore this" >&2
        echo "  worktree's test database. Use <env name=\"DB_DATABASE\" ...> without force." >&2
    fi
}

phpunit_file() {
    local file
    for file in "$1/phpunit.xml" "$1/phpunit.xml.dist"; do
        if [[ -f "$file" ]]; then
            echo "$file"
            return
        fi
    done
    return 1
}

# Usage: phpunit_value DIR NAME
# The value phpunit.xml's <env> or <server> element gives NAME; fails when
# there's none.
phpunit_value() {
    local file element
    file="$(phpunit_file "$1")" || return 1
    element="$(phpunit_variable "$file" "$2")"
    [[ -n "$element" ]] || return 1
    xml_attribute "$element" value
}

# Prints the first <env> or <server> element setting NAME in a phpunit.xml,
# on one line, ignoring commented-out ones.
phpunit_variable() {
    local element elements
    if [[ -n "${PHPUNIT_CACHE_FILE:-}" && "$PHPUNIT_CACHE_FILE" == "$1" ]]; then
        elements="$PHPUNIT_CACHE"
    else
        elements="$(phpunit_elements "$1")"
    fi
    while IFS= read -r element; do
        if [[ "$element" =~ [[:space:]]name[[:space:]]*=[[:space:]]*[\"\']"$2"[\"\'] ]]; then
            echo "$element"
            return
        fi
    done <<< "$elements"
}

# Prints a phpunit.xml's <env> and <server> elements, one per line, leaving
# out commented-out ones.
phpunit_elements() {
    local content rest pattern='<(env|server)[[:space:]][^>]*>'
    content="$(tr '\r\n\t' '   ' < "$1")"
    while [[ "$content" == *'<!--'* ]]; do
        rest="${content#*<!--}"
        content="${content%%<!--*}"
        [[ "$rest" != *'-->'* ]] || content+="${rest#*-->}"
    done
    while [[ "$content" =~ $pattern ]]; do
        echo "${BASH_REMATCH[0]}"
        content="${content#*"${BASH_REMATCH[0]}"}"
    done
}

# Usage: cache_phpunit DIR
# Reads DIR's phpunit.xml once for the phpunit_* calls that follow, in this
# shell and its subshells.
cache_phpunit() {
    PHPUNIT_CACHE_FILE="$(phpunit_file "$1")" || PHPUNIT_CACHE_FILE=""
    PHPUNIT_CACHE=""
    [[ -z "$PHPUNIT_CACHE_FILE" ]] || PHPUNIT_CACHE="$(phpunit_elements "$PHPUNIT_CACHE_FILE")"
}

xml_attribute() {
    local double="[[:space:]]$2[[:space:]]*=[[:space:]]*\"([^\"]*)\"" single="[[:space:]]$2[[:space:]]*=[[:space:]]*'([^']*)'"
    if [[ "$1" =~ $double || "$1" =~ $single ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# Used for database names and, by worktree-install, the compose project
# base: lowercase, collapse anything outside [a-z0-9] into a single hyphen,
# trim leading/trailing hyphens. LC_ALL=C works on bytes: in a UTF-8 locale,
# tr and sed would keep letters like "ë".
slugify() {
    local slug
    slug="$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
    echo "${slug:-worktree}"
}

derive_compose_project_name() {
    echo "$1-$(slugify "$2")"
}

compose_project_base() {
    if [[ -n "${WORKTREE_COMPOSE_PROJECT_BASE:-}" ]]; then
        echo "$WORKTREE_COMPOSE_PROJECT_BASE"
    else
        # Configs written before install recorded this: fall back to what
        # install derives, the main checkout's directory name.
        slugify "$(basename "$(main_checkout_dir)")"
    fi
}

sha1_hex() {
    if command -v sha1sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha1sum | cut -d' ' -f1
    else
        printf '%s' "$1" | shasum -a 1 | cut -d' ' -f1
    fi
}

# Setup and test derive names here, before the stack starts, and PHP only
# creates them. An overlong suffix is truncated and tagged with a hash of the
# full suffix. Lengths count bytes.
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

# 63 bytes: PostgreSQL's limit (MySQL's is 64).
derive_dev_database_name() {
    derive_worktree_database_name "$1" "$2" 63
}

# Capped at 40 characters, "_test" included: MySQL rejected longer test
# database names.
derive_test_database_name() {
    local name
    name="$(derive_worktree_database_name "$1" "$2" 35)" || return 1
    echo "${name}_test"
}

# Fills WT_PATHS, WT_IDS, WT_BRANCHES and WT_STATES from `git worktree list`,
# one entry per linked worktree (the main checkout is left out). An id is the
# worktree's git admin dir name (see worktree_key). A branch is empty for a
# detached HEAD; a state is "locked", "prunable" (its directory is gone) or
# empty.
# shellcheck disable=SC2034 # the arrays are read by the callers
load_worktree_list() {
    local list line i=-1
    list="$(git worktree list --porcelain)"
    WT_PATHS=()
    WT_IDS=()
    WT_BRANCHES=()
    WT_STATES=()
    while IFS= read -r line; do
        case "$line" in
            "worktree "*)
                i=$((i + 1))
                WT_PATHS[i]="${line#worktree }"
                WT_IDS[i]="$(worktree_id "${WT_PATHS[i]}")"
                WT_BRANCHES[i]=""
                WT_STATES[i]=""
                ;;
            "branch refs/heads/"*)
                WT_BRANCHES[i]="${line#branch refs/heads/}"
                ;;
            locked | "locked "*)
                WT_STATES[i]=locked
                ;;
            prunable | "prunable "*)
                [[ "${WT_STATES[i]}" == locked ]] || WT_STATES[i]=prunable
                ;;
        esac
    done <<< "$list"
    WT_PATHS=("${WT_PATHS[@]:1}")
    WT_IDS=("${WT_IDS[@]:1}")
    WT_BRANCHES=("${WT_BRANCHES[@]:1}")
    WT_STATES=("${WT_STATES[@]:1}")
}

# Usage: worktree_id PATH
# The admin dir (.git/worktrees/<id>) whose gitdir file points at PATH/.git.
# Works when PATH is gone, too.
worktree_id() {
    local admin target
    load_git_paths
    for admin in "$COMMON_GIT_DIR"/worktrees/*; do
        [[ -f "$admin/gitdir" ]] || continue
        target="$(head -n 1 "$admin/gitdir")"
        [[ "$target" == /* ]] || target="$(normalize_path "$admin/$target")"
        if [[ "$target" == "$1/.git" ]]; then
            basename "$admin"
            return
        fi
    done
    basename "$1"
}

# Usage: idle_for DAYS ID
# Whether a worktree has seen no git activity (checkout, commit, staging) for
# DAYS days.
idle_for() {
    local admin="$COMMON_GIT_DIR/worktrees/$2" file
    for file in "$admin/HEAD" "$admin/index" "$admin/logs/HEAD"; do
        [[ ! -e "$file" ]] || [[ -z "$(find "$file" -prune -mmin "-$(($1 * 1440))")" ]] || return 1
    done
}

# The ref worktree branches are merged into: origin/$WORKTREE_PRUNE_BRANCH,
# else origin's default branch, else origin/main or origin/master.
prune_base_ref() {
    local ref
    if [[ -n "${WORKTREE_PRUNE_BRANCH:-}" ]]; then
        echo "origin/$WORKTREE_PRUNE_BRANCH"
    elif ref="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD)"; then
        echo "$ref"
    elif git rev-parse --verify --quiet refs/remotes/origin/main > /dev/null; then
        echo origin/main
    else
        echo origin/master
    fi
}

# Whether BRANCH's work is in REF: merged or fast-forwarded into it, or
# squash- or rebase-merged, which leaves a commit in REF with the same
# change as the whole branch.
is_merged() {
    local branch="$1" ref="$2" base since id
    if git merge-base --is-ancestor "$branch" "$ref"; then
        ! is_unused_branch "$branch" "$ref"
        return
    fi
    base="$(git merge-base "$ref" "$branch")" || return 1
    id="$(git diff "$base" "$branch" | git patch-id --stable | cut -d' ' -f1)"
    [[ -n "$id" ]] || return 1
    # A squash merge lands after the branch's last commit, so only REF's
    # newer commits are compared (with a day's margin for clock skew). grep
    # reads all of its input, so pipefail sees no SIGPIPE.
    since=$(( $(git log -1 --format=%ct "$branch") - 86400 ))
    git log -p --no-merges --since="@$since" "$base..$ref" | git patch-id --stable | cut -d' ' -f1 |
        grep -xF "$id" > /dev/null
}

# A branch nobody has committed to is also an ancestor of REF, but isn't
# finished. It still points where it was created (a single reflog entry), at
# a commit on REF's own line rather than one merged in from a branch. The
# walk stops at the branch's parents, so it doesn't cover REF's whole history.
is_unused_branch() {
    local tip
    (( $(git reflog show "refs/heads/$1" -- 2> /dev/null | wc -l) <= 1 )) || return 1
    tip="$(git rev-parse "$1")"
    # shellcheck disable=SC2046 # one argument per parent
    git rev-list --first-parent "$2" --not $(git rev-parse "$1^@") | grep -xF "$tip" > /dev/null
}

# Setup and test record each worktree's databases, so clean drops exactly
# those: one file per worktree, named after its id (see worktree_key), with
# "test|development<TAB>name" lines.
database_ledger_dir() {
    echo "$COMMON_GIT_DIR/worktree-isolation/databases"
}

# Usage: record_database test|development NAME
record_database() {
    local file
    file="$(database_ledger_dir)/$(basename "$CHECKOUT_GIT_DIR")"
    mkdir -p "${file%/*}"
    grep -qxF "$1"$'\t'"$2" "$file" 2> /dev/null || printf '%s\t%s\n' "$1" "$2" >> "$file"
}

# PHP only reaches the database server, inside the runtime, with everything
# it needs in the environment, as Laravel names it: DB_CONNECTION (pgsql, or
# else MySQL/MariaDB), DB_* and MYSQL_ATTR_SSL_CA. PostgreSQL is reached
# through its "postgres" maintenance database. There's no autoloader: the
# worktree's vendor/ may hold another release of this package, or nothing
# yet. No single quotes in here: the snippets are single-quoted bash strings.
# shellcheck disable=SC2016 # PHP code, expanded by PHP
DB_CONNECT_PHP='
    $pgsql = getenv("DB_CONNECTION") === "pgsql";
    try {
        $options = [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION];
        if ($pgsql) {
            $dsn = "pgsql:host=" . (getenv("DB_HOST") ?: "127.0.0.1") . ";port=" . (getenv("DB_PORT") ?: 5432) . ";dbname=postgres";
            if (getenv("DB_SSLMODE")) {
                $dsn .= ";sslmode=" . getenv("DB_SSLMODE");
            }
        } else {
            $dsn = getenv("DB_SOCKET")
                ? "mysql:unix_socket=" . getenv("DB_SOCKET")
                : "mysql:host=" . (getenv("DB_HOST") ?: "127.0.0.1") . ";port=" . (getenv("DB_PORT") ?: 3306);
            if (getenv("MYSQL_ATTR_SSL_CA")) {
                $options[defined("Pdo\\Mysql::ATTR_SSL_CA") ? constant("Pdo\\Mysql::ATTR_SSL_CA") : PDO::MYSQL_ATTR_SSL_CA] = getenv("MYSQL_ATTR_SSL_CA");
            }
        }
        $pdo = new PDO($dsn, getenv("DB_USERNAME") ?: "", getenv("DB_PASSWORD") ?: "", $options);
    } catch (Throwable $e) {
        fwrite(STDERR, "Could not connect to the database server: " . $e->getMessage() . "\n");
        exit(1);
    }
    $quote = fn ($name) => $pgsql ? "\"$name\"" : "`$name`";
'

# shellcheck disable=SC2016 # PHP code, expanded by PHP
DB_NAME_PHP='
    $isWorktreeDatabase = fn ($name) => preg_match("/^[a-z0-9_-]+$/", $name) === 1 && str_contains($name, "_wt_");
'

# Creates the per-worktree database named by DB_DATABASE, which bash already
# derived; on MySQL/MariaDB in DB_CHARSET/DB_COLLATION when set. Refuses
# anything that isn't a per-worktree name or is the main checkout's
# (MAIN_DB_DATABASE). Prints "<name> created|existing" as its last line; the
# leading newline keeps that line intact if PHP emitted a notice first.
# shellcheck disable=SC2016 # PHP code, expanded by PHP
ENSURE_DB_PHP="$DB_NAME_PHP"'
    $name = (string) getenv("DB_DATABASE");
    if (! $isWorktreeDatabase($name) || $name === getenv("MAIN_DB_DATABASE")) {
        fwrite(STDERR, "Refusing to create \"$name\": not a per-worktree database name, or it is the main checkout database.\n");
        exit(1);
    }
'"$DB_CONNECT_PHP"'
    $exists = $pdo->prepare($pgsql
        ? "SELECT 1 FROM pg_database WHERE datname = ?"
        : "SELECT 1 FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = ?");
    $exists->execute([$name]);
    if ($exists->fetchColumn()) {
        echo "\n$name existing";
        exit;
    }
    if ($pgsql) {
        try {
            $pdo->exec("CREATE DATABASE " . $quote($name));
        } catch (PDOException $e) {
            // 42P04: created by someone else in the meantime.
            if ($e->getCode() !== "42P04") {
                throw $e;
            }
            echo "\n$name existing";
            exit;
        }
    } else {
        $sql = "CREATE DATABASE IF NOT EXISTS " . $quote($name);
        foreach (["CHARACTER SET" => "DB_CHARSET", "COLLATE" => "DB_COLLATION"] as $clause => $key) {
            if (preg_match("/^[A-Za-z0-9_]+$/", (string) getenv($key)) === 1) {
                $sql .= " $clause " . getenv($key);
            }
        }
        $pdo->exec($sql);
    }
    echo "\n$name created";
'

# Drops the space-separated DROP_DATABASES, if they're per-worktree names.
# PostgreSQL 13+ drops them even while something is still connected.
# Prints "dropped <name>" or "failed <name>: <reason>" per database.
# shellcheck disable=SC2016 # PHP code, expanded by PHP
DROP_DB_PHP="$DB_NAME_PHP$DB_CONNECT_PHP"'
    $force = $pgsql && (int) $pdo->getAttribute(PDO::ATTR_SERVER_VERSION) >= 13 ? " WITH (FORCE)" : "";
    foreach (preg_split("/\s+/", trim((string) getenv("DROP_DATABASES")), -1, PREG_SPLIT_NO_EMPTY) as $name) {
        if (! $isWorktreeDatabase($name)) {
            echo "failed $name: not a per-worktree database name\n";
            continue;
        }
        try {
            $pdo->exec("DROP DATABASE IF EXISTS " . $quote($name) . $force);
            echo "dropped $name\n";
        } catch (PDOException $e) {
            echo "failed $name: ", $e->getMessage(), "\n";
        }
    }
'

# Validates ENSURE_DB_PHP's output and prints its last line.
parse_ensure_db_output() {
    local last="${1##*$'\n'}"
    [[ "$last" =~ ^[a-z0-9_-]+\ (created|existing)$ ]] || return 1
    echo "$last"
}

# Environment for every container this package runs commands in. Files can
# show up under another owner there (rootless Docker, Docker Desktop), which
# git refuses as "dubious ownership". The other worktrees aren't mounted, so
# git gc must not prune them as stale. WORKTREE_IN_RUNTIME tells these
# scripts, run inside, that they're already in the runtime.
CONTAINER_ENV=(
    -e WORKTREE_IN_RUNTIME=1
    -e GIT_CONFIG_COUNT=2
    -e GIT_CONFIG_KEY_0=safe.directory -e "GIT_CONFIG_VALUE_0=*"
    -e GIT_CONFIG_KEY_1=gc.worktreePruneExpire -e GIT_CONFIG_VALUE_1=never
)

# Usage: container_git_dir [WORKDIR]
# A worktree's .git file points at <main>/.git/worktrees/<name>, so a
# container needs the main clone's git dir mounted where that pointer
# resolves. Prints that path: the pointer itself when it's absolute, or
# resolved against WORKDIR, where the worktree is mounted, when it's relative
# (git worktree add --relative-paths). Prints nothing in the main checkout,
# or for a relative pointer without WORKDIR.
container_git_dir() {
    local workdir="${1:-}" pointer suffix
    in_main_checkout && return 0
    pointer="$(sed -n 's/^gitdir: //p' "$TOPLEVEL/.git")"
    suffix="${CHECKOUT_GIT_DIR#"$COMMON_GIT_DIR"}"
    if [[ "$pointer" != /* ]]; then
        [[ -n "$workdir" ]] || return 0
        pointer="$(normalize_path "$workdir/$pointer")"
    fi
    [[ "$suffix" == /* && "$pointer" == *?"$suffix" ]] || return 0
    echo "${pointer%"$suffix"}"
}

# Resolves . and .. in an absolute path without touching the filesystem.
normalize_path() {
    local part parts=() out=()
    IFS=/ read -ra parts <<< "$1"
    for part in ${parts[@]+"${parts[@]}"}; do
        case "$part" in
            ''|.) ;;
            ..) [[ ${#out[@]} -eq 0 ]] || unset 'out[${#out[@]}-1]' ;;
            *) out+=("$part") ;;
        esac
    done
    local IFS=/
    echo "/${out[*]+"${out[*]}"}"
}

# The compose service that normally runs the image sets environment a plain
# docker run lacks (Sail's laravel.test: LARAVEL_SAIL, XDEBUG_MODE, and
# whatever the project adds). Compose resolves it against this checkout's own
# .env, so it follows the compose file and never lands in the committed
# config. WORKTREE_DOCKER_SERVICE names the service; empty, it's the one using
# the image. Fills SERVICE_ENV with KEY=value pairs.
# The result is cached in the checkout's git dir until the compose files or
# .env change, since `docker compose config` is slow to run on every command.
load_service_env() {
    SERVICE_ENV=()
    local service="${WORKTREE_DOCKER_SERVICE:-}" args=(docker compose) cache key config lines line value file
    find_compose_files "$PROJECT_ROOT"
    if [[ ${#COMPOSE_FILES[@]} -eq 0 ]]; then
        [[ -z "$service" ]] || echo "Warning: no compose file, so containers don't get the $service service's environment." >&2
        return 0
    fi

    cache="$CHECKOUT_GIT_DIR/worktree-isolation.service-env"
    key="$IMAGE|$service|${COMPOSE_FILES[*]}"
    if [[ -f "$cache" && "$(head -n 1 "$cache")" == "$key" ]] &&
        [[ -z "$(find "${COMPOSE_FILES[@]}" "$PROJECT_ROOT/.env" -newer "$cache" 2> /dev/null)" ]]; then
        while IFS= read -r -d '' line; do
            [[ -z "$line" ]] || SERVICE_ENV+=("$line")
        done < <(tail -n +2 "$cache")
        return 0
    fi

    for file in "${COMPOSE_FILES[@]}"; do
        args+=(-f "$file")
    done
    if ! config="$(cd "$PROJECT_ROOT" && "${args[@]}" config 2> /dev/null)"; then
        echo "Warning: 'docker compose config' failed, so containers don't get the compose service's environment." >&2
        return 0
    fi
    lines="$(compose_service_env "$config" "$service" "$IMAGE")"
    if [[ -n "$service" && -z "$lines" ]]; then
        echo "Warning: no '$service' service in the compose file, so containers don't get its environment." >&2
        return 0
    fi

    while IFS=$'\t' read -r line value; do
        # HOME and PATH belong to the image and to the container's user
        # (HOME=/tmp, see CONTAINER_USER_ARGS); exporting them here would
        # also change this script's own.
        [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*$ && "$line" != HOME && "$line" != PATH ]] || continue
        value="$(yaml_scalar "$value")" || continue
        SERVICE_ENV+=("$line=$value")
    done < <(printf '%s\n' "$lines" | tail -n +2)

    # Values may hold newlines, so the pairs are NUL-separated.
    {
        printf '%s\n' "$key"
        [[ ${#SERVICE_ENV[@]} -eq 0 ]] || printf '%s\0' "${SERVICE_ENV[@]}"
    } > "$cache.$$" && mv "$cache.$$" "$cache"
}

# Reads `docker compose config` output, whose layout Compose normalizes:
# services at two spaces, their keys at four, environment entries at six.
# Prints "service <name>" and then "KEY<tab>raw value" lines for the named
# service, or else the one using the image (preferring the one that builds
# it, as Sail's laravel.test does), or nothing.
compose_service_env() {
    printf '%s\n' "$1" | awk -v want="$2" -v image="$3" '
        function unquote(s) {
            if (s ~ /^".*"$/ || s ~ /^\047.*\047$/) s = substr(s, 2, length(s) - 2)
            return s
        }
        /^[^ ]/ { in_services = ($0 == "services:"); next }
        !in_services { next }
        /^  [^ ]/ {
            service = unquote(substr($0, 3, length($0) - 3))
            order[++count] = service
            section = ""
            next
        }
        /^    [^ ]/ {
            line = substr($0, 5)
            section = line
            sub(/:.*/, "", section)
            if (section == "image") images[service] = unquote(substr(line, 8))
            if (section == "build") builds[service] = 1
            next
        }
        section == "environment" && /^      [^ ]/ {
            line = substr($0, 7)
            key = line
            sub(/:.*/, "", key)
            value = substr(line, length(key) + 2)
            sub(/^ /, "", value)
            env[service] = env[service] key "\t" value "\n"
        }
        END {
            for (i = 1; i <= count; i++) {
                s = order[i]
                if (s == want) found = 1
                if (image != "" && images[s] == image && (pick == "" || (builds[s] && !builds[pick]))) pick = s
            }
            if (want == "") want = pick
            else if (!found) exit
            if (want != "") printf "service %s\n%s", want, env[want]
        }
    '
}

# Decodes a YAML scalar as `docker compose config` prints it. Fails for null
# and for block scalars, which it doesn't print for environment values in
# practice.
yaml_scalar() {
    local value="$1" decoded="" i char
    case "$value" in
        null|'~'|'|'*|'>'*)
            return 1
            ;;
        \'*\')
            value="${value:1:${#value}-2}"
            printf '%s' "${value//\'\'/\'}"
            ;;
        \"*\")
            value="${value:1:${#value}-2}"
            for ((i = 0; i < ${#value}; i++)); do
                char="${value:i:1}"
                if [[ "$char" == \\ ]]; then
                    i=$((i + 1))
                    case "${value:i:1}" in
                        n) char=$'\n' ;;
                        t) char=$'\t' ;;
                        *) char="${value:i:1}" ;;
                    esac
                fi
                decoded+="$char"
            done
            printf '%s' "$decoded"
            ;;
        *)
            printf '%s' "$value"
            ;;
    esac
}

# WORKTREE_DOCKER_ENV's values (and the compose service's) are exported and
# passed by name, as run_in_runtime does, so they stay out of a process
# listing. WORKTREE_DOCKER_ENV comes second, so it wins.
build_docker_image_args() {
    local git_dir pair pairs=()
    DOCKER_ARGS=(
        docker run --rm
        "${CONTAINER_USER_ARGS[@]}"
        "${CONTAINER_ENV[@]}"
    )
    read -ra pairs <<< "${WORKTREE_DOCKER_ENV:-}"
    for pair in ${SERVICE_ENV[@]+"${SERVICE_ENV[@]}"} ${pairs[@]+"${pairs[@]}"}; do
        export "${pair?}"
        DOCKER_ARGS+=(-e "${pair%%=*}")
    done
    DOCKER_ARGS+=(-v "$PROJECT_ROOT:$WORKDIR")
    # Read-write: git add, stash and the like write to the index.
    git_dir="$(container_git_dir "$WORKDIR")"
    if [[ -n "$git_dir" ]]; then
        DOCKER_ARGS+=(-v "$COMMON_GIT_DIR:$git_dir")
    fi
    DOCKER_ARGS+=(-w "$WORKDIR")

    if [[ -n "$NETWORK" ]]; then
        DOCKER_ARGS+=(--network "$NETWORK")
    fi
}

# Usage: exec_in_docker_image [-e KEY[=value]]... [-T] [--root] -- command [args...]
# Replaces this process with command run in a throwaway container of the
# image, the way passthrough runs it. -e values are exported and passed by
# name, as run_in_runtime does. -T never allocates a TTY; otherwise one is
# allocated when stdin and stdout are terminals. --root runs as root rather
# than the host user.
exec_in_docker_image() {
    local pairs=() pair tty=true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -e) pairs+=("$2"); shift 2 ;;
            -T) tty=false; shift ;;
            --root) CONTAINER_USER_ARGS=(-u root); shift ;;
            --) shift; break ;;
            *) break ;;
        esac
    done

    build_docker_image_args
    for pair in ${pairs[@]+"${pairs[@]}"}; do
        [[ "$pair" != *=* ]] || export "${pair?}"
        DOCKER_ARGS+=(-e "${pair%%=*}")
    done
    DOCKER_ARGS+=(-i)
    [[ "$tty" == true && -t 0 && -t 1 ]] && DOCKER_ARGS+=(-t)

    # Overriding --entrypoint with the command's first token is the same
    # pattern run_in_runtime uses (--entrypoint composer, --entrypoint npm).
    exec "${DOCKER_ARGS[@]}" --entrypoint "$1" "$IMAGE" "${@:2}"
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
# Sets PARSED_VALUE rather than printing it, to save a subshell per line.
parse_env_value() {
    local raw="${1%$'\r'}" value
    value="${raw#"${raw%%[![:space:]]*}"}"
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
            # From the raw value, so "KEY=   # comment" is empty.
            value="${raw%%[[:space:]]#*}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            ;;
    esac
    PARSED_VALUE="$value"
}

ENV_LINE_PATTERN='^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$'

# Reads KEY's value from a dotenv file (the last assignment wins).
env_file_value() {
    local file="$1" key="$2" line value=""
    [[ -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $ENV_LINE_PATTERN && "${BASH_REMATCH[2]}" == "$key" ]]; then
            parse_env_value "${BASH_REMATCH[3]}"
            value="$PARSED_VALUE"
        fi
    done < "$file"
    printf '%s\n' "$value"
}

# Usage: load_env_file FILE [PREFIX]
# Exports every assignment in a dotenv file, or only the keys starting with
# PREFIX.
load_env_file() {
    local line
    [[ -f "$1" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ $ENV_LINE_PATTERN && "${BASH_REMATCH[2]}" == "${2:-}"* ]]; then
            parse_env_value "${BASH_REMATCH[3]}"
            export "${BASH_REMATCH[2]}=$PARSED_VALUE"
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


# Usage: sail_docker_binary_usable DIR SAIL_DOCKER
# Whether the checkout's Sail runs docker through SAIL_DOCKER_BINARY (1.55+),
# so setup can point it at SAIL_DOCKER (stubs/bin/sail-docker). Sail expands
# the setting unquoted, so the path can't contain whitespace.
sail_docker_binary_usable() {
    [[ -n "$2" && "$2" != *[[:space:]]* ]] && grep -qs SAIL_DOCKER_BINARY "$1/vendor/laravel/sail/bin/sail"
}

# Usage: warn_about_hooks_calling_sail DIR RUNTIME SAIL_DOCKER
# The project's own git hooks run in worktrees too, where `sail` and `docker
# compose exec` reach the main checkout's container, or none, so e.g. a
# pre-commit pint --dirty formats the main checkout's files. Setup points
# both at a docker-compose worktree's own stack, and Sail 1.55+ at
# SAIL_DOCKER in a docker-image worktree, so only the rest is flagged.
# Checks hook.*.command and the hooks directory (core.hooksPath, and husky's
# scripts above .husky/_). Hooks that mention vendor/bin/worktree are assumed
# to handle worktrees.
warn_about_hooks_calling_sail() {
    local sail='(^|[[:space:];&|(/])sail[[:space:]]' compose='docker[ -]compose[^;&|]*[[:space:]](exec|run)[[:space:]]'
    local pattern="$sail|$compose" old_sail=false
    case "$2" in
        docker-compose)
            return 0
            ;;
        docker-image)
            if sail_docker_binary_usable "$1" "$3"; then
                pattern="$compose"
            elif [[ -f "$1/vendor/laravel/sail/bin/sail" ]]; then
                old_sail=true
            fi
            ;;
    esac
    local found=() line hooks_dir hook_dirs=() dir file
    while IFS= read -r line; do
        if [[ "$line" != hook.worktree-setup.command* && "$line" =~ $pattern && "$line" != *vendor/bin/worktree* ]]; then
            found+=("git config ${line%% *}")
        fi
    done < <(git -C "$1" config --get-regexp '^hook\..*\.command$' 2> /dev/null)

    if hooks_dir="$(git -C "$1" rev-parse --path-format=absolute --git-path hooks 2> /dev/null)"; then
        hook_dirs=("$hooks_dir")
        [[ "$hooks_dir" != */_ ]] || hook_dirs+=("${hooks_dir%/_}")
    fi
    for dir in ${hook_dirs[@]+"${hook_dirs[@]}"}; do
        for file in "$dir"/*; do
            [[ -f "$file" && "$file" != *.sample ]] || continue
            if grep -qE "$pattern" "$file" && ! grep -q vendor/bin/worktree "$file"; then
                found+=("${file#"$1"/}")
            fi
        done
    done

    if [[ ${#found[@]} -gt 0 ]]; then
        echo "Warning: these git hooks call sail or docker compose, which in a worktree reach the main checkout's container, or none:" >&2
        printf '  %s\n' "${found[@]}" >&2
        [[ "$old_sail" == false ]] || echo "  With laravel/sail 1.55+, sail runs in worktrees unchanged." >&2
        echo "  Run those commands through vendor/bin/worktree instead. To use it in the main checkout too, set WORKTREE_MAIN_CHECKOUT_PASSTHROUGH=true." >&2
    fi
}
