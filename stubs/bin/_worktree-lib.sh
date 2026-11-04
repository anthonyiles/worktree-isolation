#!/usr/bin/env bash
#
# Shared helpers sourced by stubs/bin/worktree, worktree-install,
# worktree-setup, and test.

# Usage: load_worktree_config [--skip-if-missing]
# Exits when .worktree-isolation.env is missing rather than guessing at
# defaults. In a worktree that means its branch predates worktree-isolation;
# --skip-if-missing exits 0 there, so setup doesn't fail `git worktree add`.
# shellcheck disable=SC2034 # the variables are read by the sourcing scripts
load_worktree_config() {
    # The scripts live in vendor/, so resolve the project root via git.
    PROJECT_ROOT="$(git rev-parse --show-toplevel)"
    WORKTREE_BASENAME="$(basename "$PROJECT_ROOT")"

    if [[ ! -f "$PROJECT_ROOT/.worktree-isolation.env" ]]; then
        if in_main_checkout; then
            echo "Error: .worktree-isolation.env not found. Run vendor/bin/worktree install first." >&2
            exit 1
        fi
        echo "No .worktree-isolation.env in this worktree: its branch predates worktree-isolation." >&2
        [[ "${1:-}" == --skip-if-missing ]] && exit 0
        exit 1
    fi
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
                COMPOSE_PROJECT_NAME="$(derive_compose_project_name "$(compose_project_base)" "$WORKTREE_BASENAME")"
                COMPOSE_ARGS+=(-p "$COMPOSE_PROJECT_NAME")
                add_compose_git_override
            elif [[ -n "${WORKTREE_COMPOSE_FILE:-}" ]]; then
                COMPOSE_ARGS+=(-f "$WORKTREE_COMPOSE_FILE")
            fi
            COMPOSE_EXEC_ARGS=("${COMPOSE_ARGS[@]}" exec "${CONTAINER_USER_ARGS[@]}" "${CONTAINER_GIT_ENV[@]}")
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

# A worktree's stack also mounts the main clone's git dir (see
# container_git_dir), through an override file kept in the worktree's own git
# dir, out of the working tree. Passing -f stops Compose finding its default
# files, so those are passed too. With a relative gitdir pointer, whose
# target depends on the service's own mounts, nothing is added.
add_compose_git_override() {
    local files=() file git_dir override value
    if [[ -n "${WORKTREE_COMPOSE_FILE:-}" ]]; then
        files=("$WORKTREE_COMPOSE_FILE")
    else
        value="${COMPOSE_FILE:-$(env_file_value "$PROJECT_ROOT/.env" COMPOSE_FILE)}"
        if [[ -n "$value" ]]; then
            IFS="${COMPOSE_PATH_SEPARATOR:-:}" read -ra files <<< "$value"
        else
            for file in compose.yaml compose.yml docker-compose.yml docker-compose.yaml; do
                [[ -f "$PROJECT_ROOT/$file" ]] && files=("$file") && break
            done
            for file in compose.override.yml compose.override.yaml docker-compose.override.yml docker-compose.override.yaml; do
                [[ ${#files[@]} -gt 0 && -f "$PROJECT_ROOT/$file" ]] && files+=("$file") && break
            done
        fi
    fi

    for file in ${files[@]+"${files[@]}"}; do
        [[ "$file" == /* ]] || file="$PROJECT_ROOT/$file"
        COMPOSE_ARGS+=(-f "$file")
    done
    git_dir="$(container_git_dir)"
    [[ ${#files[@]} -gt 0 && -n "$git_dir" ]] || return 0

    override="$(git rev-parse --path-format=absolute --git-dir)/worktree-isolation.compose.yml"
    printf 'services:\n  %s:\n    volumes:\n      - type: bind\n        source: %s\n        target: %s\n' \
        "$(yaml_string "$COMPOSE_SERVICE")" \
        "$(yaml_string "$(git rev-parse --path-format=absolute --git-common-dir)")" \
        "$(yaml_string "$git_dir")" > "$override"
    COMPOSE_ARGS+=(-f "$override")
}

# Double-quotes a YAML string, escaping $ from Compose's interpolation too.
yaml_string() {
    local value="${1//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "${value//\$/\$\$}"
}

main_checkout_dir() {
    dirname "$(git rev-parse --path-format=absolute --git-common-dir)"
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
# database, "{name}_test_wt_{worktree}", so no testing env file is needed.
# The name is cut to 16 bytes to leave the worktree room within 40. Falls
# back to "testing" when .env has no MySQL/MariaDB database. Matches
# testDatabaseBase() in worktree-clean.
test_database_base() {
    local LC_ALL=C env name=""
    env="$(main_checkout_dir)/.env"
    if is_mysql_connection "$env"; then
        name="$(env_file_value "$env" DB_DATABASE)"
        name="${name%%_wt_*}"
        name="${name:0:16}"
        while [[ "$name" == *[_-] ]]; do
            name="${name%?}"
        done
    fi
    if [[ -n "$name" ]]; then
        echo "${name}_test"
    else
        echo testing
    fi
}

# Per-worktree test databases apply when the tests use MySQL/MariaDB.
tests_use_mysql() {
    [[ "$(test_db_setting "$PROJECT_ROOT" DB_CONNECTION)" =~ ^(mysql|mariadb)$ ]]
}

# Usage: test_db_setting DIR KEY
# KEY as DIR's tests see it: phpunit.xml (else phpunit.xml.dist), then the
# testing env file, then .env, which Laravel loads when there's no testing
# env file. Fails when none sets it, so callers don't pass a blank that
# would override .env. Matches testSetting() in worktree-clean.
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
    local content rest element pattern='<(env|server)[[:space:]][^>]*>'
    content="$(tr '\r\n\t' '   ' < "$1")"
    while [[ "$content" == *'<!--'* ]]; do
        rest="${content#*<!--}"
        content="${content%%<!--*}"
        [[ "$rest" != *'-->'* ]] || content+="${rest#*-->}"
    done
    while [[ "$content" =~ $pattern ]]; do
        element="${BASH_REMATCH[0]}"
        if [[ "$(xml_attribute "$element" name)" == "$2" ]]; then
            echo "$element"
            return
        fi
        content="${content#*"$element"}"
    done
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

derive_dev_database_name() {
    derive_worktree_database_name "$1" "$2" 64
}

# The "test" check runs on the base: a worktree named e.g. "test-refactor"
# must not make a non-test base pass. Capped at 40 characters: MySQL
# rejected longer test database names.
derive_test_database_name() {
    local base="${1%%_wt_*}"
    [[ "$(printf '%s' "$base" | LC_ALL=C tr '[:upper:]' '[:lower:]')" == *test* ]] || return 1
    derive_worktree_database_name "$base" "$2" 40
}

# Fills WT_PATHS, WT_BRANCHES and WT_STATES from `git worktree list`, one
# entry per linked worktree (the main checkout is left out). A branch is
# empty for a detached HEAD; a state is "locked", "prunable" (its directory
# is gone) or empty.
# shellcheck disable=SC2034 # the arrays are read by the callers
load_worktree_list() {
    local list line i=-1
    list="$(git worktree list --porcelain)"
    WT_PATHS=()
    WT_BRANCHES=()
    WT_STATES=()
    while IFS= read -r line; do
        case "$line" in
            "worktree "*)
                i=$((i + 1))
                WT_PATHS[i]="${line#worktree }"
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
    WT_BRANCHES=("${WT_BRANCHES[@]:1}")
    WT_STATES=("${WT_STATES[@]:1}")
}

# The databases the linked worktrees use, comma-separated, for clean to keep.
# A worktree whose directory is gone still counts until `git worktree prune`
# drops it: inside a container, git can't see the host's worktree
# directories and would report every one as gone.
in_use_databases() {
    local test_base dev_base i name db names=""
    test_base="$(test_database_base)"
    dev_base="$(main_dev_database)"
    load_worktree_list
    for ((i = 0; i < ${#WT_PATHS[@]}; i++)); do
        name="$(basename "${WT_PATHS[i]}")"
        if db="$(derive_test_database_name "$test_base" "$name")"; then
            names+=",$db"
        fi
        if [[ -n "$dev_base" ]] && db="$(derive_dev_database_name "$dev_base" "$name")"; then
            names+=",$db"
        fi
    done
    echo "${names#,}"
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
    local branch="$1" ref="$2" base tmp
    if git merge-base --is-ancestor "$branch" "$ref"; then
        ! is_unused_branch "$branch" "$ref"
        return
    fi
    base="$(git merge-base "$ref" "$branch")" || return 1
    tmp="$(GIT_AUTHOR_NAME=worktree GIT_AUTHOR_EMAIL=worktree@localhost \
        GIT_COMMITTER_NAME=worktree GIT_COMMITTER_EMAIL=worktree@localhost \
        git commit-tree "$branch^{tree}" -p "$base" -m squashed)" || return 1
    [[ "$(git cherry "$ref" "$tmp")" == -* ]]
}

# A branch nobody has committed to is also an ancestor of REF, but isn't
# finished. It still points where it was created (a single reflog entry), at
# a commit on REF's own line rather than one merged in from a branch. The
# grep reads all of rev-list's output, so pipefail sees no SIGPIPE.
is_unused_branch() {
    (( $(git reflog show "refs/heads/$1" -- 2> /dev/null | wc -l) <= 1 )) &&
        git rev-list --first-parent "$2" | grep -xF "$(git rev-parse "$1")" > /dev/null
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

# Git settings for containers. Files can show up under another owner there
# (rootless Docker, Docker Desktop), which git refuses as "dubious
# ownership". The other worktrees aren't mounted, so git gc must not prune
# them as stale.
CONTAINER_GIT_ENV=(
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
    local workdir="${1:-}" pointer common suffix
    in_main_checkout && return 0
    pointer="$(sed -n 's/^gitdir: //p' "$PROJECT_ROOT/.git")"
    common="$(git rev-parse --path-format=absolute --git-common-dir)"
    suffix="$(git rev-parse --path-format=absolute --git-dir)"
    suffix="${suffix#"$common"}"
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

build_docker_image_args() {
    local git_dir
    DOCKER_ARGS=(
        docker run --rm
        "${CONTAINER_USER_ARGS[@]}"
        "${CONTAINER_GIT_ENV[@]}"
        -v "$PROJECT_ROOT:$WORKDIR"
    )
    # Read-write: git add, stash and the like write to the index.
    git_dir="$(container_git_dir "$WORKDIR")"
    if [[ -n "$git_dir" ]]; then
        DOCKER_ARGS+=(-v "$(git rev-parse --path-format=absolute --git-common-dir):$git_dir")
    fi
    DOCKER_ARGS+=(-w "$WORKDIR")

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
