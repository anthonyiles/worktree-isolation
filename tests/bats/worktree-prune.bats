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
    # A fixed clone id, so the derived names are predictable.
    mkdir -p .git/worktree-isolation
    echo c0de > .git/worktree-isolation/clone-id
}

# Usage: age_worktree NAME — no git activity in it since 2020.
age_worktree() {
    local admin="$MAIN_REPO/.git/worktrees/$1" file
    for file in "$admin/HEAD" "$admin/index" "$admin/logs/HEAD"; do
        [[ ! -e "$file" ]] || touch -t 202001010000 "$file"
    done
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
    [[ "$output" == *"Keeping $WORKTREES/dirty (dirty is merged into origin/main, but the worktree has uncommitted or untracked changes)"* ]]
    [[ "$output" == *"No worktrees to remove."* ]]
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
    [[ "$output" == *"No worktrees to remove."* ]]
}

@test "cleans up after a worktree whose directory was deleted" {
    add_worktree gone
    rm -rf "$WORKTREES/gone"

    run prune --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"$WORKTREES/gone (directory is gone)"* ]]
    [ "$(git worktree list | wc -l)" -eq 1 ]
}

@test "--dry-run only lists them" {
    add_worktree merged
    merge_and_push merged

    run prune --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Remove them with: vendor/bin/worktree prune --force"* ]]
    [ -d "$WORKTREES/merged" ]
}

@test "--auto removes them without asking, at most once an hour" {
    add_worktree merged
    merge_and_push merged

    run prune --auto
    [ "$status" -eq 0 ]
    [ ! -d "$WORKTREES/merged" ]

    add_worktree merged-too
    merge_and_push merged-too
    run prune --auto
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ -d "$WORKTREES/merged-too" ]

    touch -t 202001010000 .git/worktree-isolation/last-prune
    run prune --auto
    [ "$status" -eq 0 ]
    [ ! -d "$WORKTREES/merged-too" ]
}

@test "removes worktrees idle for WORKTREE_PRUNE_AFTER days, keeping their branches" {
    add_worktree idle
    add_worktree busy
    add_worktree idle-dirty
    touch "$WORKTREES/idle-dirty/notes.txt"
    age_worktree idle
    age_worktree idle-dirty

    run prune --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"$WORKTREES/idle (no git activity for 7 days; idle is kept)"* ]]
    [[ "$output" == *"Keeping $WORKTREES/idle-dirty (no git activity for 7 days; idle-dirty is kept, but the worktree has uncommitted or untracked changes)"* ]]
    [ ! -d "$WORKTREES/idle" ]
    [ -d "$WORKTREES/busy" ]
    [ -d "$WORKTREES/idle-dirty" ]
    git rev-parse --verify -q idle
}

@test "WORKTREE_PRUNE_AFTER=0 never removes idle worktrees" {
    add_worktree idle
    age_worktree idle
    echo "WORKTREE_PRUNE_AFTER=0" >> .worktree-isolation.env

    run prune --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"No worktrees to remove."* ]]
    [ -d "$WORKTREES/idle" ]
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

@test "drops only the removed worktrees' recorded databases" {
    add_worktree merged
    merge_and_push merged
    add_worktree open
    mkdir -p .git/worktree-isolation/databases
    printf 'test\ttesting_wt_merged-c0de\ndevelopment\tmyapp_wt_merged-c0de\n' > .git/worktree-isolation/databases/merged
    printf 'test\ttesting_wt_open-c0de\n' > .git/worktree-isolation/databases/open
    printf 'DB_CONNECTION=mysql\nDB_DATABASE=myapp\nDB_HOST=db\n' > .env
    FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
    mkdir -p "$FAKE_BIN"
    cat > "$FAKE_BIN/php" <<SCRIPT
#!/usr/bin/env bash
echo "\$DB_HOST \$DROP_DATABASES" >> "$BATS_TEST_TMPDIR/php.log"
for name in \$DROP_DATABASES; do echo "dropped \$name"; done
SCRIPT
    chmod +x "$FAKE_BIN/php"

    PATH="$FAKE_BIN:$PATH" run prune --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dropped: testing_wt_merged-c0de"*"Dropped: myapp_wt_merged-c0de"* ]]
    [ "$(cat "$BATS_TEST_TMPDIR/php.log")" = "db testing_wt_merged-c0de
db myapp_wt_merged-c0de" ]
    [ ! -e .git/worktree-isolation/databases/merged ]
    [ -e .git/worktree-isolation/databases/open ]
}

@test "takes the Compose stack down first, and keeps the worktree if that fails" {
    add_worktree merged
    merge_and_push merged
    printf 'WORKTREE_RUNTIME=docker-compose\nWORKTREE_COMPOSE_PROJECT_BASE=myapp\n' > .worktree-isolation.env
    FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
    mkdir -p "$FAKE_BIN"
    cat > "$FAKE_BIN/docker" <<SCRIPT
#!/usr/bin/env bash
[[ " \$* " != *" compose version "* ]] || echo 2.29.0
[[ " \$* " != *" config --services"* ]] || echo app
echo "docker \$*" >> "$BATS_TEST_TMPDIR/docker.log"
[[ "\$*" != *" ps "* ]] || echo app
[[ "\$*" != *" down "* || -z "\${FAIL_DOWN:-}" ]]
SCRIPT
    chmod +x "$FAKE_BIN/docker"

    FAIL_DOWN=1 PATH="$FAKE_BIN:$PATH" run prune --force
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not remove the Compose stack myapp-merged-c0de, so $WORKTREES/merged is kept."* ]]
    [ -d "$WORKTREES/merged" ]

    PATH="$FAKE_BIN:$PATH" run prune --force
    [ "$status" -eq 0 ]
    [ ! -d "$WORKTREES/merged" ]
    grep -q -- "docker compose -p myapp-merged-c0de down -v --remove-orphans" "$BATS_TEST_TMPDIR/docker.log"
}

@test "checks against WORKTREE_PRUNE_BRANCH when set" {
    git push -q origin main:develop
    add_worktree into-develop
    add_worktree into-main
    merge_and_push into-main
    git checkout -q -b develop origin/develop
    git merge -q --no-ff -m "merge into-develop" into-develop
    git push -q origin develop
    echo "WORKTREE_PRUNE_BRANCH=develop" >> .worktree-isolation.env

    run prune --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"into-develop is merged into origin/develop"* ]]
    [ ! -d "$WORKTREES/into-develop" ]
    [ -d "$WORKTREES/into-main" ]
}

@test "falls back to origin/master without origin/HEAD" {
    git push -q origin main:master
    git remote set-head origin --delete
    git update-ref -d refs/remotes/origin/main
    add_worktree merged
    git merge -q --no-ff -m "merge merged" merged
    git push -q origin main:master

    run prune --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"merged is merged into origin/master"* ]]
}

@test "fails when the branch to check against doesn't exist" {
    echo "WORKTREE_PRUNE_BRANCH=nope" >> .worktree-isolation.env

    run prune
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not find origin/nope. Set WORKTREE_PRUNE_BRANCH"* ]]

    git remote remove origin
    sed -i.bak '/WORKTREE_PRUNE_BRANCH/d' .worktree-isolation.env
    run prune
    [ "$status" -eq 1 ]
    [[ "$output" == *"git remote set-head origin --auto"* ]]
}

@test "rejects a WORKTREE_PRUNE_AFTER that isn't a number of days" {
    echo "WORKTREE_PRUNE_AFTER=1w" >> .worktree-isolation.env

    run prune
    [ "$status" -eq 1 ]
    [[ "$output" == *"WORKTREE_PRUNE_AFTER must be a number of days, not '1w'"* ]]
}
