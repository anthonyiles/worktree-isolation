#!/usr/bin/env bats
#
# Unit tests for stubs/bin/_worktree-lib.sh.

setup() {
    # shellcheck disable=SC1091
    source "$BATS_TEST_DIRNAME/../../stubs/bin/_worktree-lib.sh"
}

@test "derives a normal project name" {
    run derive_compose_project_name "myapp" "feature-auth"
    [ "$status" -eq 0 ]
    [ "$output" = "myapp-feature-auth" ]
}

@test "lowercases uppercase input" {
    run derive_compose_project_name "myapp" "Feature-Auth"
    [ "$output" = "myapp-feature-auth" ]
}

@test "collapses special characters and spaces into single hyphens" {
    run derive_compose_project_name "myapp" "feature/auth fix!!"
    [ "$output" = "myapp-feature-auth-fix" ]
}

@test "trims leading and trailing hyphens from the suffix" {
    run derive_compose_project_name "myapp" "--feature--"
    [ "$output" = "myapp-feature" ]
}

@test "falls back to 'worktree' when the suffix sanitizes to empty" {
    run derive_compose_project_name "myapp" "___"
    [ "$output" = "myapp-worktree" ]
}

@test "derives a development database name like DevDatabaseResolver" {
    run derive_dev_database_name "myapp" "Feature/Auth"
    [ "$output" = "myapp_wt_feature-auth" ]
}

@test "rederives a development database name from its original base" {
    run derive_dev_database_name "myapp_wt_feature-auth" "renamed"
    [ "$output" = "myapp_wt_renamed" ]
}

@test "rejects an empty base or an overlong development database name" {
    run derive_dev_database_name "" "feature"
    [ "$status" -eq 1 ]
    run derive_dev_database_name "myapp" "$(printf 'a%.0s' {1..64})"
    [ "$status" -eq 1 ]
}

@test "derives a test database name that must mention test and fit in 40 characters" {
    run derive_test_database_name "testing_wt_old" "Feature/Auth"
    [ "$output" = "testing_wt_feature-auth" ]
    run derive_test_database_name "myapp" "feature"
    [ "$status" -eq 1 ]
    run derive_test_database_name "testing" "$(printf 'a%.0s' {1..30})"
    [ "$status" -eq 1 ]
}

@test "does not let the worktree name satisfy the test database check" {
    run derive_test_database_name "laravel" "test-refactor"
    [ "$status" -eq 1 ]
}

@test "writes env values containing sed metacharacters verbatim" {
    file="$BATS_TEST_TMPDIR/.env"
    printf 'DB_CONNECTION=sqlite\nDB_DATABASE=old\n' > "$file"

    set_env_file_value "$file" DB_DATABASE 'database/a&b\1.sqlite'

    [ "$(cat "$file")" = "$(printf 'DB_CONNECTION=sqlite\nDB_DATABASE=database/a&b\\1.sqlite')" ]
}

@test "appends a missing key on its own line when the file has no trailing newline" {
    file="$BATS_TEST_TMPDIR/.env"
    printf 'DB_PASSWORD=secret' > "$file"

    set_env_file_value "$file" DB_DATABASE myapp_wt_feat

    [ "$(cat "$file")" = "$(printf 'DB_PASSWORD=secret\nDB_DATABASE=myapp_wt_feat')" ]
}

@test "only replaces the exact key" {
    file="$BATS_TEST_TMPDIR/.env"
    printf 'DB_DATABASE_URL=keep\nDB_DATABASE=old\n' > "$file"

    set_env_file_value "$file" DB_DATABASE new

    [ "$(cat "$file")" = "$(printf 'DB_DATABASE_URL=keep\nDB_DATABASE=new')" ]
}

@test "append_testing_env_args handles an empty WORKTREE_EXTRA_ENV_VARS under set -u" {
    run bash -c '
        set -euo pipefail
        source "$1"
        DB_PER_WORKTREE_KEY=TEST_DB_PER_WORKTREE TEST_ENV=() APP_ENV=testing
        WORKTREE_EXTRA_ENV_VARS= append_testing_env_args
        echo "${TEST_ENV[*]}"
    ' _ "$BATS_TEST_DIRNAME/../../stubs/bin/_worktree-lib.sh"
    [ "$status" -eq 0 ]
    [ "$output" = "-e APP_ENV=testing" ]
}

@test "append_testing_env_args passes WORKTREE_EXTRA_ENV_VARS through" {
    DB_PER_WORKTREE_KEY=TEST_DB_PER_WORKTREE
    TEST_ENV=()
    FOO=1 BAR=two WORKTREE_EXTRA_ENV_VARS="FOO BAR" append_testing_env_args
    [ "${TEST_ENV[*]}" = "-e FOO=1 -e BAR=two" ]
}
