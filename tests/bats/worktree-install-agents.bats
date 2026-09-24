#!/usr/bin/env bats
#
# Integration tests for `worktree install --agents`: which instruction files
# get the block, and that re-running replaces it in place.

setup() {
    STUBS_DIR="$(cd "$BATS_TEST_DIRNAME/../../stubs" && pwd)"

    PROJECT_DIR="$BATS_TEST_TMPDIR/app"
    mkdir -p "$PROJECT_DIR"
    git -C "$PROJECT_DIR" init -q

    # Same git --version shim as worktree-install-compose.bats.
    REAL_GIT="$(command -v git)"
    FAKE_BIN="$BATS_TEST_TMPDIR/fakebin"
    mkdir -p "$FAKE_BIN"
    cat > "$FAKE_BIN/git" <<SCRIPT
#!/usr/bin/env bash
if [[ "\$1" == "--version" ]]; then
    echo "git version 2.54.0"
else
    exec "$REAL_GIT" "\$@"
fi
SCRIPT
    chmod +x "$FAKE_BIN/git"
    export PATH="$FAKE_BIN:$PATH"
}

run_install() {
    php "$STUBS_DIR/bin/worktree-install" \
        --project-dir="$PROJECT_DIR" --stubs-dir="$STUBS_DIR" "$@"
}

block_count() {
    grep -c '<!-- worktree-isolation:start -->' "$1"
}

@test "writes nothing for agents without --agents" {
    run run_install
    [ "$status" -eq 0 ]
    [ ! -e "$PROJECT_DIR/AGENTS.md" ]
    [ ! -e "$PROJECT_DIR/CLAUDE.md" ]
}

@test "creates AGENTS.md when no instruction file exists" {
    run run_install --agents
    [ "$status" -eq 0 ]
    [[ "$output" == *"Tip: Claude Code reads CLAUDE.md"* ]]
    [ "$(block_count "$PROJECT_DIR/AGENTS.md")" -eq 1 ]
    grep -q 'vendor/bin/worktree test' "$PROJECT_DIR/AGENTS.md"
    [ ! -e "$PROJECT_DIR/CLAUDE.md" ]
}

@test "appends to an existing CLAUDE.md without touching its content" {
    printf '# My project\n\nUse tabs.\n' > "$PROJECT_DIR/CLAUDE.md"

    run run_install --agents
    [ "$status" -eq 0 ]
    [ "$(head -3 "$PROJECT_DIR/CLAUDE.md")" = "$(printf '# My project\n\nUse tabs.')" ]
    [ "$(block_count "$PROJECT_DIR/CLAUDE.md")" -eq 1 ]
    [ ! -e "$PROJECT_DIR/AGENTS.md" ]
}

@test "skips a CLAUDE.md that imports AGENTS.md" {
    echo '@AGENTS.md' > "$PROJECT_DIR/CLAUDE.md"
    echo '# Agents' > "$PROJECT_DIR/AGENTS.md"

    run run_install --agents
    [ "$status" -eq 0 ]
    [ "$(block_count "$PROJECT_DIR/AGENTS.md")" -eq 1 ]
    [ "$(cat "$PROJECT_DIR/CLAUDE.md")" = "@AGENTS.md" ]
}

@test "writes to explicitly listed files, creating directories" {
    run run_install --agents=CLAUDE.md,.github/copilot-instructions.md
    [ "$status" -eq 0 ]
    [ "$(block_count "$PROJECT_DIR/CLAUDE.md")" -eq 1 ]
    [ "$(block_count "$PROJECT_DIR/.github/copilot-instructions.md")" -eq 1 ]
    [ ! -e "$PROJECT_DIR/AGENTS.md" ]
}

@test "replaces a stale block in place on re-run" {
    cat > "$PROJECT_DIR/AGENTS.md" <<'MD'
# Before
<!-- worktree-isolation:start -->
old instructions
<!-- worktree-isolation:end -->
# After
MD

    run run_install --agents
    [ "$status" -eq 0 ]
    [[ "$output" == *"Updated: AGENTS.md"* ]]
    [ "$(block_count "$PROJECT_DIR/AGENTS.md")" -eq 1 ]
    [ "$(grep -c 'old instructions' "$PROJECT_DIR/AGENTS.md")" -eq 0 ]
    [ "$(head -1 "$PROJECT_DIR/AGENTS.md")" = "# Before" ]
    [ "$(tail -1 "$PROJECT_DIR/AGENTS.md")" = "# After" ]

    run run_install --agents
    [[ "$output" == *"Unchanged: AGENTS.md"* ]]
}
