#!/usr/bin/env bats
#
# stubs/bin/worktree-prune: a main checkout with a bare origin, and
# worktrees whose branches are merged into origin/main in different ways.

setup() {
    REAL_STUBS_DIR="$(cd "$BATS_TEST_DIRNAME/../../stubs/bin" && pwd)"
    export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
    export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com

    ORIGIN="$BATS_TEST_TMPDIR/origin.git"
    MAIN_REPO="$BATS_TEST_TMPDIR/main"
    WORKTREES="$BATS_TEST_TMPDIR/worktrees"
    git init -q --bare -b main "$ORIGIN"
    git init -q -b main "$MAIN_REPO"
    cd "$MAIN_REPO"
    git remote add origin "$ORIGIN"
    echo "vendor/" > .gitignore
    echo "WORKTREE_RUNTIME=native" > .worktree-isolation.env
    echo base > app.txt
    git add . && git commit -q -m init
    git push -q -u origin main
    git remote set-head origin main

    # Clean runs from the checkout the scripts belong to, as in a real install.
    STUBS_DIR="$MAIN_REPO/vendor/anthonyiles/worktree-isolation/stubs/bin"
    mkdir -p "$STUBS_DIR"
    cp "$REAL_STUBS_DIR"/* "$STUBS_DIR/"
    cp -R "$REAL_STUBS_DIR/../../src" "$STUBS_DIR/../../src"
}

# Usage: add_worktree NAME — on a new branch NAME with one commit.
add_worktree() {
    git worktree add -q -b "$1" "$WORKTREES/$1"
    echo "$1" > "$WORKTREES/$1/$1.txt"
    git -C "$WORKTREES/$1" add . && git -C "$WORKTREES/$1" commit -q -m "$1"
}

merge_and_push() {
    git merge -q --no-ff -m "merge $1" "$1"
    git push -q origin main
}

prune() {
    bash "$STUBS_DIR/worktree-prune" --no-fetch "$@"
}

@test "removes merged worktrees and keeps their branches" {
    add_worktree merged
    merge_and_push merged
    add_worktree squashed
    git merge -q --squash squashed && git commit -q -m "squashed"
    echo more >> squashed.txt && git commit -q -am "main moves on"
    git push -q origin main

    # Someone else's branch, checked out to review: never committed to here.
    git branch review main && git -C . worktree add -q "$WORKTREES/tmp" review
    echo review > "$WORKTREES/tmp/review.txt"
    git -C "$WORKTREES/tmp" add . && git -C "$WORKTREES/tmp" commit -q -m review
    git push -q origin review
    git worktree remove "$WORKTREES/tmp" && git branch -q -D review
    git worktree add -q "$WORKTREES/review" review
    git merge -q --no-ff -m "merge review" origin/review
    git push -q origin main

    run prune --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"$WORKTREES/merged (merged is merged into origin/main)"* ]]
    [ ! -d "$WORKTREES/merged" ]
    [ ! -d "$WORKTREES/squashed" ]
    [ ! -d "$WORKTREES/review" ]
    git rev-parse --verify -q merged
    git rev-parse --verify -q squashed
    [ "$(git worktree list | wc -l)" -eq 1 ]
}

@test "keeps unmerged, fresh, dirty, locked and detached worktrees" {
    add_worktree open
    git worktree add -q -b fresh "$WORKTREES/fresh"
    add_worktree dirty
    add_worktree locked
    merge_and_push dirty
    merge_and_push locked
    touch "$WORKTREES/dirty/notes.txt"
    git worktree lock "$WORKTREES/locked"
    git worktree add -q --detach "$WORKTREES/detached" main

    run prune --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"Keeping $WORKTREES/dirty (dirty is merged, but the worktree has uncommitted or untracked changes)"* ]]
    [[ "$output" == *"No merged worktrees to remove."* ]]
    for name in open fresh dirty locked detached; do
        [ -d "$WORKTREES/$name" ]
    done
}

@test "never removes the current worktree" {
    add_worktree merged
    merge_and_push merged
    cd "$WORKTREES/merged"

    run prune --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"No merged worktrees to remove."* ]]
}

@test "cleans up after a worktree whose directory was deleted" {
    add_worktree gone
    rm -rf "$WORKTREES/gone"

    run prune --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"$WORKTREES/gone (directory is gone)"* ]]
    [ "$(git worktree list | wc -l)" -eq 1 ]
}

@test "--dry-run and WORKTREE_PRUNE=report only list them" {
    add_worktree merged
    merge_and_push merged

    run prune --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Remove them with: vendor/bin/worktree prune --force"* ]]
    [ -d "$WORKTREES/merged" ]

    echo "WORKTREE_PRUNE=report" >> .worktree-isolation.env
    run prune
    [ "$status" -eq 0 ]
    [[ "$output" == *"Remove them with"* ]]
    [ -d "$WORKTREES/merged" ]
}

@test "WORKTREE_PRUNE=remove removes them without asking" {
    add_worktree merged
    merge_and_push merged
    echo "WORKTREE_PRUNE=remove" >> .worktree-isolation.env

    run prune
    [ "$status" -eq 0 ]
    [ ! -d "$WORKTREES/merged" ]
}

@test "asks only with a terminal" {
    add_worktree merged
    merge_and_push merged

    if command -v setsid > /dev/null; then
        run setsid -w bash "$STUBS_DIR/worktree-prune" --no-fetch < /dev/null
    else
        run prune < /dev/null
    fi
    [ "$status" -eq 0 ]
    [[ "$output" == *"Remove them with"* ]]
    [ -d "$WORKTREES/merged" ]

    script --version > /dev/null 2>&1 || skip "needs util-linux script"
    run bash -c "printf 'n\n' | script -qec 'bash $STUBS_DIR/worktree-prune --no-fetch' /dev/null"
    [[ "$output" == *"Remove these worktrees, their Compose stacks and databases? [y/N]"*"Aborted."* ]]
    [ -d "$WORKTREES/merged" ]

    run bash -c "printf 'y\n' | script -qec 'bash $STUBS_DIR/worktree-prune --no-fetch' /dev/null"
    [[ "$output" == *"Removed $WORKTREES/merged"* ]]
    [ ! -d "$WORKTREES/merged" ]
}

@test "drops the removed worktrees' databases through clean" {
    add_worktree merged
    merge_and_push merged
    add_worktree open
    FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
    mkdir -p "$FAKE_BIN"
    printf '#!/usr/bin/env bash\necho "php $*" >> "%s"\n' "$BATS_TEST_TMPDIR/php.log" > "$FAKE_BIN/php"
    chmod +x "$FAKE_BIN/php"
    printf 'DB_CONNECTION=mysql\nDB_DATABASE=testing\n' > .env.testing

    PATH="$FAKE_BIN:$PATH" run prune --force
    [ "$status" -eq 0 ]
    [[ "$(cat "$BATS_TEST_TMPDIR/php.log")" == *"worktree-clean --force --keep=testing_wt_open" ]]
}

@test "takes the Compose stack down first, and keeps the worktree if that fails" {
    add_worktree merged
    merge_and_push merged
    printf 'WORKTREE_RUNTIME=docker-compose\nWORKTREE_COMPOSE_PROJECT_BASE=myapp\n' > .worktree-isolation.env
    FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
    mkdir -p "$FAKE_BIN"
    cat > "$FAKE_BIN/docker" <<SCRIPT
#!/usr/bin/env bash
echo "docker \$*" >> "$BATS_TEST_TMPDIR/docker.log"
[[ "\$*" != *" down "* || -z "\${FAIL_DOWN:-}" ]]
SCRIPT
    chmod +x "$FAKE_BIN/docker"

    FAIL_DOWN=1 PATH="$FAKE_BIN:$PATH" run prune --force
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not remove the Compose stack myapp-merged, so $WORKTREES/merged is kept."* ]]
    [ -d "$WORKTREES/merged" ]

    PATH="$FAKE_BIN:$PATH" run prune --force
    [ "$status" -eq 0 ]
    [ ! -d "$WORKTREES/merged" ]
    grep -q -- "docker compose -p myapp-merged down -v --remove-orphans" "$BATS_TEST_TMPDIR/docker.log"
    grep -q -- "worktree-clean --force --keep=" "$BATS_TEST_TMPDIR/docker.log"
}

@test "fails without origin's default branch" {
    git remote remove origin

    run prune
    [ "$status" -eq 1 ]
    [[ "$output" == *"git remote set-head origin --auto"* ]]
}

@test "rejects an unknown WORKTREE_PRUNE" {
    echo "WORKTREE_PRUNE=always" >> .worktree-isolation.env

    run prune
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown WORKTREE_PRUNE 'always'"* ]]
}
