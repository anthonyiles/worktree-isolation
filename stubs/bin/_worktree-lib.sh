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
