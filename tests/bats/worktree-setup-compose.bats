#!/usr/bin/env bats
#
# Integration tests for the docker-compose runtime in stubs/bin/worktree-setup,
# using a fake `docker` executable so no real Docker daemon is needed.

load helpers

setup() {
    setup_docker_compose_worktree
}

@test "brings up its own stack and threads -p through every docker compose call" {
    echo '{}' > "$WORKTREE_DIR/package.json"
    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [ -s "$DOCKER_LOG" ]

    # "docker compose version" (the runtime prerequisite check) has no
    # project scope and legitimately carries no -p — only the up/exec calls
    # matter here. 4 expected: up -d, composer install exec, DB-derivation
    # exec, npm install exec.
    scoped_log="$BATS_TEST_TMPDIR/scoped.log"
    grep -E -- 'up -d| exec ' "$DOCKER_LOG" > "$scoped_log"

    run grep -c . "$scoped_log"
    [ "$output" -eq 4 ]

    run grep -vc -- "-p myapp-feature-auth" "$scoped_log"
    [ "$output" -eq 0 ]

    # up -d must run before the first exec (own-stack-per-worktree, not
    # assuming one is already running)
    first_up_line="$(grep -n -- 'up -d' "$DOCKER_LOG" | head -1 | cut -d: -f1)"
    first_exec_line="$(grep -n -- ' exec ' "$DOCKER_LOG" | head -1 | cut -d: -f1)"
    [ -n "$first_up_line" ]
    [ -n "$first_exec_line" ]
    [ "$first_up_line" -lt "$first_exec_line" ]
}

@test "runs setup through vendor/bin/worktree's symlink" {
    symlink_dir="$BATS_TEST_TMPDIR/vendor-bin"
    mkdir -p "$symlink_dir"
    ln -s "$STUBS_DIR/worktree" "$symlink_dir/worktree"

    run bash "$symlink_dir/worktree" setup
    [ "$status" -eq 0 ]

    run grep -- "up -d" "$DOCKER_LOG"
    [[ "$output" == *"-p myapp-feature-auth"* ]]
}

@test "keeps a compose file path with spaces as a single argument" {
    log_docker_argv
    echo "WORKTREE_COMPOSE_FILE=\"my compose.yml\"" >> "$WORKTREE_DIR/.worktree-isolation.env"
    echo '{}' > "$WORKTREE_DIR/package.json"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    # up -d, composer install, DB derivation, npm install
    run grep -cF -- "[-f] [$(pwd -P)/my compose.yml]" "$DOCKER_ARGV_LOG"
    [ "$output" -eq 4 ]
}

@test "copies env files into a worktree that uses relative gitdir paths, run from a subdirectory" {
    echo "APP_NAME=main" > "$MAIN_REPO/.env"
    relative_dir="$BATS_TEST_TMPDIR/worktrees/relative"
    git -C "$MAIN_REPO" worktree add -q --relative-paths -b relative "$relative_dir"
    cp "$WORKTREE_DIR/.worktree-isolation.env" "$WORKTREE_DIR/.env.testing" "$relative_dir/"
    mkdir -p "$relative_dir/app"
    cd "$relative_dir/app"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [ "$(cat "$relative_dir/.env")" = "APP_NAME=main" ]
}

@test "does nothing in the main checkout" {
    cp "$WORKTREE_DIR/.worktree-isolation.env" "$MAIN_REPO/"
    cd "$MAIN_REPO"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to set up"* ]]
    run grep -- "up -d" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}

@test "skips JavaScript dependencies without a package.json" {
    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    run grep -E -- "(npm|pnpm|yarn|bun) install" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}

@test "installs JavaScript dependencies with the lockfile's package manager" {
    echo '{}' > "$WORKTREE_DIR/package.json"
    touch "$WORKTREE_DIR/pnpm-lock.yaml"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    run grep -c -- "app pnpm install" "$DOCKER_LOG"
    [ "$output" -eq 1 ]
}

@test "only warns when installing JavaScript dependencies fails" {
    echo '{}' > "$WORKTREE_DIR/package.json"
    cat > "$FAKE_BIN/docker" <<SCRIPT
#!/usr/bin/env bash
echo "\$*" >> "$DOCKER_LOG"
[[ "\$*" != *"npm install"* ]]
SCRIPT

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: npm install --no-progress failed"* ]]
    [[ "$output" == *"Worktree setup complete"* ]]
}

@test "skips a worktree whose branch has no .worktree-isolation.env" {
    rm "$WORKTREE_DIR/.worktree-isolation.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"its branch predates worktree-isolation"* ]]
    run grep '^DB_DATABASE=' "$WORKTREE_DIR/.env.testing"
    [ "$output" = DB_DATABASE=testing ]
    [ ! -s "$DOCKER_LOG" ]
}

@test "fails in the main checkout without .worktree-isolation.env" {
    cd "$MAIN_REPO"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Run vendor/bin/worktree install first"* ]]
}

@test "checks for the main checkout before the runtime" {
    printf 'WORKTREE_RUNTIME=docker-image\nWORKTREE_DOCKER_IMAGE=missing/image\n' > "$MAIN_REPO/.worktree-isolation.env"
    # As if the image hadn't been built: every docker call fails.
    printf '#!/usr/bin/env bash\nexit 1\n' > "$FAKE_BIN/docker"
    cd "$MAIN_REPO"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to set up"* ]]
}

@test "checks for merged worktrees at the end, without failing setup" {
    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    # The fixture has no origin, so the check can only report that.
    [[ "$output" == *"Could not find origin/master"*"Worktree setup complete"* ]]

    echo "WORKTREE_PRUNE_ON_SETUP=false" >> "$WORKTREE_DIR/.worktree-isolation.env"
    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Could not find origin/"* ]]
}

@test "mounts the main clone's git dir into the worktree's stack through an override file" {
    touch "$WORKTREE_DIR/compose.yaml" "$WORKTREE_DIR/compose.override.yaml"
    root="$(pwd -P)"
    common="$(git rev-parse --path-format=absolute --git-common-dir)"
    override="$(git rev-parse --path-format=absolute --git-dir)/worktree-isolation.compose.yml"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep -- "up -d" "$DOCKER_LOG"
    [[ "$output" == *"-f $root/compose.yaml -f $root/compose.override.yaml -f $override up -d"* ]]
    run grep -c -- "-f $override" "$DOCKER_LOG"
    [ "$output" -eq 3 ]
    [ "$(cat "$override")" = "$(printf 'services:\n  "app":\n    volumes:\n      - type: bind\n        source: "%s"\n        target: "%s"' "$common" "$common")" ]
}

@test "passes git settings to commands in the stack" {
    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep -- " exec " "$DOCKER_LOG"
    [[ "$output" == *"-e GIT_CONFIG_COUNT=2 "* ]]
    [[ "$output" == *"-e GIT_CONFIG_VALUE_0=*"* ]]
}

@test "runs the post-setup command once, in the worktree's runtime, after the JavaScript install" {
    echo '{}' > "$WORKTREE_DIR/package.json"
    echo "WORKTREE_POST_SETUP_COMMAND=npm run build" >> "$WORKTREE_DIR/.worktree-isolation.env"

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]

    run grep -c -- "-p myapp-feature-auth exec .* -T app bash -c npm run build" "$DOCKER_LOG"
    [ "$output" -eq 1 ]
    [ "$(grep -n -- "npm install" "$DOCKER_LOG" | cut -d: -f1)" -lt "$(grep -n -- "npm run build" "$DOCKER_LOG" | cut -d: -f1)" ]
}

@test "only warns when the post-setup command fails" {
    echo "WORKTREE_POST_SETUP_COMMAND=npm run build" >> "$WORKTREE_DIR/.worktree-isolation.env"
    cat > "$FAKE_BIN/docker" <<SCRIPT
#!/usr/bin/env bash
echo "\$*" >> "$DOCKER_LOG"
[[ "\$*" != *"npm run build"* ]]
SCRIPT

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: npm run build failed."* ]]
    [[ "$output" == *"Worktree setup complete"* ]]
}

@test "runs no post-setup command by default" {
    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    run grep -- "bash -c" "$DOCKER_LOG"
    [ "$status" -ne 0 ]
}

@test "warns about project git hooks that call sail or docker compose" {
    git config hook.pint.command "vendor/bin/sail php vendor/bin/pint --dirty"
    git config hook.pint.event pre-commit
    git config hook.ok.command "vendor/bin/pint --dirty"
    mkdir -p .husky/_
    git config core.hooksPath .husky/_
    printf '#!/bin/sh\n. "$(dirname "$0")/h"\n' > .husky/_/pre-commit
    printf 'docker compose exec -T app php artisan test\n' > .husky/pre-push
    printf 'if [ -f .git ]; then vendor/bin/worktree php x; else ./vendor/bin/sail php x; fi\n' > .husky/post-merge

    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: these git hooks call sail or docker compose"* ]]
    [[ "$output" == *"  git config hook.pint.command"* ]]
    [[ "$output" == *"  .husky/pre-push"* ]]
    [[ "$output" != *"hook.ok.command"* ]]
    [[ "$output" != *"pre-commit"* ]]
    [[ "$output" != *"post-merge"* ]]
    [[ "$output" != *"worktree-setup"* ]]
}

@test "doesn't warn about hooks without sail" {
    run bash "$STUBS_DIR/worktree-setup"
    [ "$status" -eq 0 ]
    [[ "$output" != *"git hooks call sail"* ]]
}
