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
