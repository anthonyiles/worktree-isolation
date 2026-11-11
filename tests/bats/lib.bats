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

@test "derives a development database name" {
    run derive_dev_database_name "myapp" "Feature/Auth"
    [ "$output" = "myapp_wt_feature-auth" ]
}

@test "rederives a development database name from its original base" {
    run derive_dev_database_name "myapp_wt_feature-auth" "renamed"
    [ "$output" = "myapp_wt_renamed" ]
}

@test "rejects an empty base or one too long to fit a worktree suffix" {
    run derive_dev_database_name "" "feature"
    [ "$status" -eq 1 ]
    run derive_dev_database_name "$(printf 'a%.0s' {1..60})" "feature"
    [ "$status" -eq 1 ]
}

@test "truncates an overlong development database name with a hash" {
    run derive_dev_database_name "myapp" "$(printf 'a%.0s' {1..64})"
    [ "$status" -eq 0 ]
    [ "$output" = "myapp_wt_$(printf 'a%.0s' {1..46})-0098ba82" ]
    [ "${#output}" -eq 64 ]
}

@test "derives a test database name ending in _test that fits in 40 characters" {
    run derive_test_database_name "myapp_wt_old" "Feature/Auth"
    [ "$output" = "myapp_wt_feature-auth_test" ]
    run derive_test_database_name "" "feature"
    [ "$status" -eq 1 ]
    run derive_test_database_name "testing" "$(printf 'a%.0s' {1..30})"
    [ "$output" = "testing_wt_$(printf 'a%.0s' {1..15})-cd762363_test" ]
    [ "${#output}" -eq 40 ]
}

@test "drops a trailing hyphen left by truncation" {
    run derive_test_database_name "testing" "$(printf 'a%.0s' {1..14})-bbbbbbbbbbbb"
    [[ "$output" =~ ^testing_wt_a{14}-[0-9a-f]{8}_test$ ]]
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

@test "env_file_keys lists each assigned key once" {
    file="$BATS_TEST_TMPDIR/.env.testing"
    printf '%s\n' '# COMMENTED=1' 'APP_ENV=testing' 'export DB_HOST=mysql' 'not an assignment' 'APP_ENV=again' > "$file"

    [ "$(env_file_keys "$file" | tr '\n' ' ')" = "APP_ENV DB_HOST " ]
    [ -z "$(env_file_keys "$BATS_TEST_TMPDIR/missing")" ]
}

@test "env_file_value parses quotes, export, comments and CRLF without evaluating" {
    file="$BATS_TEST_TMPDIR/.env"
    printf '%s\n' \
        'APP_NAME=My App # trailing comment' \
        'export DB_HOST = mysql' \
        'DB_PASSWORD="p@ss #not a comment"' \
        "DB_USERNAME='\$(touch $BATS_TEST_TMPDIR/pwned)'" \
        'DB_PORT=3307' > "$file"
    printf 'DB_DATABASE=crlf\r\n' >> "$file"

    [ "$(env_file_value "$file" APP_NAME)" = "My App" ]
    [ "$(env_file_value "$file" DB_HOST)" = "mysql" ]
    [ "$(env_file_value "$file" DB_PASSWORD)" = "p@ss #not a comment" ]
    [ "$(env_file_value "$file" DB_USERNAME)" = "\$(touch $BATS_TEST_TMPDIR/pwned)" ]
    [ "$(env_file_value "$file" DB_DATABASE)" = "crlf" ]
    [ "$(env_file_value "$file" MISSING)" = "" ]
    [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
}

@test "load_env_file exports values without running them" {
    file="$BATS_TEST_TMPDIR/.env.testing"
    printf '%s\n' \
        'APP_NAME=My App' \
        "DB_PASSWORD=\`touch $BATS_TEST_TMPDIR/pwned\`" \
        '# DB_HOST=commented' > "$file"

    load_env_file "$file"

    [ "$APP_NAME" = "My App" ]
    [ "$DB_PASSWORD" = "\`touch $BATS_TEST_TMPDIR/pwned\`" ]
    [ -z "${DB_HOST:-}" ]
    [ ! -e "$BATS_TEST_TMPDIR/pwned" ]
    [ "$(bash -c 'echo "$APP_NAME"')" = "My App" ]
}

@test "derives database names from bytes, in a UTF-8 locale too" {
    [ "$(LC_ALL=en_US.UTF-8 derive_dev_database_name myapp "Fëature-Äbc")" = "myapp_wt_f-ature-bc" ]
    [ "$(LC_ALL=en_US.UTF-8 derive_dev_database_name myapp "日本")" = "myapp_wt_worktree" ]
    [ "$(LC_ALL=en_US.UTF-8 derive_test_database_name testing "$(printf 'ë%.0s' {1..20})x")" = "testing_wt_x_test" ]
}

@test "normalizes . and .. in a path" {
    run normalize_path "/var/www/html/../../main/./.git"
    [ "$output" = "/var/main/.git" ]
    run normalize_path "/../a"
    [ "$output" = "/a" ]
    run normalize_path "/"
    [ "$output" = "/" ]
}

@test "finds no git dir to mount in the main checkout" {
    repo="$BATS_TEST_TMPDIR/repo"
    git init -q "$repo"
    cd "$repo"
    PROJECT_ROOT="$repo"

    run container_git_dir /var/www/html
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "quotes a YAML string, escaping Compose interpolation" {
    run yaml_string 'a "b" \c $d'
    [ "$output" = '"a \"b\" \\c $$d"' ]
}

@test "reads phpunit.xml's values, skipping commented-out elements" {
    dir="$BATS_TEST_TMPDIR/project"
    mkdir -p "$dir"
    cat > "$dir/phpunit.xml.dist" <<'XML'
<phpunit>
    <php>
        <!-- <env name="DB_DATABASE" value=":memory:"/> -->
        <env name="APP_ENV" value="testing"/>
        <env
            value='app_testing' name='DB_DATABASE'/>
        <server name="DB_CONNECTION" value="mysql"/>
    </php>
</phpunit>
XML

    run phpunit_value "$dir" DB_DATABASE
    [ "$output" = app_testing ]
    run phpunit_value "$dir" DB_CONNECTION
    [ "$output" = mysql ]
    run phpunit_value "$dir" DB_HOST
    [ "$status" -eq 1 ]
}

@test "prefers phpunit.xml over phpunit.xml.dist" {
    dir="$BATS_TEST_TMPDIR/project"
    mkdir -p "$dir"
    echo '<env name="DB_DATABASE" value="dist"/>' > "$dir/phpunit.xml.dist"
    echo '<env name="DB_DATABASE" value="local"/>' > "$dir/phpunit.xml"

    run phpunit_value "$dir" DB_DATABASE
    [ "$output" = local ]
}

@test "warns when phpunit.xml forces DB_DATABASE, by force or with <server>" {
    PROJECT_ROOT="$BATS_TEST_TMPDIR"
    echo '<env name="DB_DATABASE" value="x"/>' > "$PROJECT_ROOT/phpunit.xml"
    run warn_if_phpunit_forces_database
    [ -z "$output" ]

    echo '<env name="DB_DATABASE" value="x" force="true"/>' > "$PROJECT_ROOT/phpunit.xml"
    run warn_if_phpunit_forces_database
    [[ "$output" == *"so tests ignore this"* ]]

    echo '<server name="DB_DATABASE" value="x"/>' > "$PROJECT_ROOT/phpunit.xml"
    run warn_if_phpunit_forces_database
    [[ "$output" == *"so tests ignore this"* ]]
}

@test "reads a test setting from phpunit.xml, then the testing env file, then .env" {
    dir="$BATS_TEST_TMPDIR"
    TESTING_ENV_FILE=.env.testing
    printf 'DB_HOST=mysql\nDB_PORT=3306\nDB_PASSWORD=secret\n' > "$dir/.env"
    printf 'DB_PORT=3307\nDB_PASSWORD=\n' > "$dir/.env.testing"
    echo '<env name="DB_PORT" value="3308"/>' > "$dir/phpunit.xml"

    run test_db_setting "$dir" DB_HOST
    [ "$output" = mysql ]
    run test_db_setting "$dir" DB_PORT
    [ "$output" = 3308 ]
    run test_db_setting "$dir" DB_PASSWORD
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run test_db_setting "$dir" DB_USERNAME
    [ "$status" -eq 1 ]
}

@test "names test databases after the main checkout's development database" {
    repo="$BATS_TEST_TMPDIR/repo"
    git init -q "$repo"
    cd "$repo"

    run test_database_base
    [ "$output" = testing ]
    printf 'DB_CONNECTION=sqlite\nDB_DATABASE=database/database.sqlite\n' > .env
    run test_database_base
    [ "$output" = testing ]
    printf 'DB_CONNECTION=mysql\nDB_DATABASE=myapp_wt_old\n' > .env
    run test_database_base
    [ "$output" = myapp ]
    printf 'DB_CONNECTION=mysql\nDB_DATABASE=my_long_app_name_with_more\n' > .env
    run test_database_base
    [ "$output" = my_long_app_name ]
    printf 'DB_CONNECTION=mysql\nDB_DATABASE=my_long_app_nam_e\n' > .env
    run test_database_base
    [ "$output" = my_long_app_nam ]
}

@test "the database snippets run under PHP and refuse names that aren't per-worktree" {
    command -v php > /dev/null || skip "needs PHP"

    # The name is checked before connecting.
    DB_DATABASE=myapp run php -r "$ENSURE_DB_PHP"
    [ "$status" -eq 1 ]
    [[ "$output" == *'Refusing to create "myapp"'* ]]
    MAIN_DB_DATABASE=myapp_wt_x DB_DATABASE=myapp_wt_x run php -r "$ENSURE_DB_PHP"
    [[ "$output" == *'Refusing to create "myapp_wt_x"'* ]]

    # Port 1 refuses connections (or there's no pdo_mysql).
    DB_HOST=127.0.0.1 DB_PORT=1 DB_DATABASE=myapp_wt_x run php -r "$ENSURE_DB_PHP"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not connect to the database server"* ]]
    DB_HOST=127.0.0.1 DB_PORT=1 DROP_DATABASES=myapp_wt_x run php -r "$DROP_DB_PHP"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not connect to the database server"* ]]
}

@test "names a worktree after its git admin dir and the clone, so same-named directories differ" {
    repo="$BATS_TEST_TMPDIR/repo"
    git init -q "$repo"
    git -C "$repo" -c user.email=t@example.com -c user.name=T commit -q --allow-empty -m init
    git -C "$repo" worktree add -q -b a "$BATS_TEST_TMPDIR/one/feature"
    git -C "$repo" worktree add -q -b b "$BATS_TEST_TMPDIR/two/feature"
    mkdir -p "$repo/.git/worktree-isolation"
    echo c0de > "$repo/.git/worktree-isolation/clone-id"
    echo "WORKTREE_RUNTIME=native" > "$repo/.worktree-isolation.env"

    cd "$BATS_TEST_TMPDIR/one/feature"
    run bash -c "source '$BATS_TEST_DIRNAME/../../stubs/bin/_worktree-lib.sh'; load_worktree_config; echo \$WORKTREE_KEY"
    [ "$output" = "feature-c0de" ]
    cd "$BATS_TEST_TMPDIR/two/feature"
    run bash -c "source '$BATS_TEST_DIRNAME/../../stubs/bin/_worktree-lib.sh'; load_worktree_config; echo \$WORKTREE_KEY"
    [ "$output" = "feature1-c0de" ]

    cd "$repo"
    load_worktree_list
    [ "${WT_IDS[*]}" = "feature feature1" ]
}

@test "creates a clone id once" {
    repo="$BATS_TEST_TMPDIR/repo"
    git init -q "$repo"
    cd "$repo"
    load_git_paths

    first="$(clone_id)"
    [[ "$first" =~ ^[0-9a-f]{4}$ ]]
    [ "$(clone_id)" = "$first" ]
}
