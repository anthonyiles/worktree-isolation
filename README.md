# Worktree Isolation

Make every `git worktree` of a PHP project ready to use the moment it's created, with its own dependencies, env files and databases.

After a one-off install, `git worktree add` automatically:

- copies `.env` (and `.env.testing`, if you have one) from the main checkout
- gives the worktree its own MySQL/MariaDB test and development databases, so parallel worktrees (and AI agents running migrations in them) never touch each other's data or the main checkout's
- runs `composer install`, and your JavaScript package manager's install when there's a `package.json`

It works with native PHP (Herd, Valet), Docker Compose, Laravel Sail or any Docker image. Laravel isn't required.

## Requirements

- PHP 8.2+ where your app runs (in the container for Docker setups)
- Bash and Git 2.31+ on the host
- MySQL or MariaDB, for per-worktree databases (SQLite needs nothing extra)

## Install

```bash
composer require anthonyiles/worktree-isolation --dev
vendor/bin/worktree install
```

Run `install` on the host, not inside Sail. It writes `.worktree-isolation.env` (commit it) and registers a git hook for this clone. Each teammate runs `vendor/bin/worktree install` once per clone; it keeps the committed config and just registers the hook. Every worktree uses the main checkout's config, whatever its branch.

Pick the runtime that matches how you run PHP:

| Setup | Install command |
|---|---|
| Herd, Valet, local PHP | `vendor/bin/worktree install` |
| Laravel Sail | `vendor/bin/worktree install` (Sail's image and network are detected) |
| Docker Compose | `vendor/bin/worktree install --runtime=docker-compose --compose-service=app` |
| Any other Docker image | `vendor/bin/worktree install --runtime=docker-image --docker-image=myapp --docker-network=myapp_default` |

Without Laravel, the test command defaults to Pest or PHPUnit; set another with `--test-command`.

## Usage

Create worktrees as usual. Setup runs automatically:

```bash
git worktree add ../worktrees/feature-auth -b feature-auth
cd ../worktrees/feature-auth
```

Then run everything through `vendor/bin/worktree`:

```bash
vendor/bin/worktree test                      # run tests (args go to the test runner)
vendor/bin/worktree test --filter=UserTest
vendor/bin/worktree php artisan migrate       # anything else runs in this worktree's runtime
vendor/bin/worktree composer require foo/bar
vendor/bin/worktree npm run dev
vendor/bin/worktree setup                     # re-run setup, e.g. after fixing DB settings
vendor/bin/worktree prune                     # remove merged and idle worktrees, their stacks and databases
vendor/bin/worktree clean                     # drop databases of removed worktrees
```

Tip: `alias worktree='vendor/bin/worktree'`.

> **Git hooks that call `sail` or `docker compose` work in worktrees unchanged.** Setup points them at the worktree through its `.env`: `COMPOSE_PROJECT_NAME` and `COMPOSE_FILE` for Docker Compose, and `SAIL_DOCKER_BINARY` for Sail on the `docker-image` runtime (laravel/sail 1.55+). With `docker-image`, sail only runs commands in the app container (no `sail up`), and a plain `docker compose exec` still reaches the main checkout's container, so use `vendor/bin/worktree` there. `install` and `setup` warn about hooks that won't reach the worktree.

To use one command in every checkout, e.g. `bash vendor/bin/worktree php vendor/bin/pint $STAGED_FILES` in a git hook, set `WORKTREE_MAIN_CHECKOUT_PASSTHROUGH=true`. In the main checkout it then runs in your usual runtime: on the host, in your running Compose service, or in a fresh container of the image. Inside a container (Sail, or one `vendor/bin/worktree` started) it runs the command directly.

## What setup does

1. Copies `.env`, `.env.testing` (or `.env.testing.example`) and any `WORKTREE_COPY_FILES` from the main checkout, if the worktree doesn't have them.
2. Points them at the worktree's own databases (see below), before anything else runs.
3. Docker Compose only: starts the worktree's own stack with `docker compose -p <project>-<worktree> up -d`, and writes that project and its compose files into `.env` for `sail` and `docker compose`.
4. Runs `composer install`.
5. Creates the test and development databases. A new development database is migrated and seeded; an existing one is only migrated.
6. If there's a `package.json`, runs `npm install` (or `pnpm`, `yarn` or `bun`, by lockfile). A failure here only warns.
7. Runs `WORKTREE_POST_SETUP_COMMAND`, if set (e.g. `npm run build`, so tests that render `@vite` find a manifest). A failure here only warns.
8. Runs `vendor/bin/worktree prune` in the background, without fetching or asking, at most once an hour. Its log is `.git/worktree-isolation/prune.log`.

`prune` finds worktrees whose branch is merged into origin's default branch, or `WORKTREE_PRUNE_BRANCH` (squash merges included), or that have had no git activity for `WORKTREE_PRUNE_AFTER` days (default 7), and removes them with their Compose stacks and databases. Branches are kept, so `git worktree add <path> <branch>` brings one back. Worktrees with uncommitted changes are never removed.

Setup runs the branch's Composer and npm scripts. For a branch you don't trust, skip it: `WORKTREE_SKIP_SETUP=1 git worktree add ...`.

## Databases

Each worktree's databases are named after the worktree (as `git worktree list` names it) and a short id for the clone, so same-named worktrees in different directories or clones never share one:

| | Main checkout | Worktree `feature-auth` |
|---|---|---|
| Test | (yours) | `myapp_wt_feature-auth-3f2a_test` |
| Development (`.env`) | `myapp` | `myapp_wt_feature-auth-3f2a` |

- Both are named after the main checkout's `.env` `DB_DATABASE`, so no `.env.testing` is needed. The test database uses the connection and credentials your tests use: `phpunit.xml`, then `.env.testing`, then `.env`.
- Only MySQL/MariaDB connections are changed. SQLite and others are left alone. A worktree is never pointed at one of the main checkout's databases.
- Long names are shortened with a hash (test names to 40 characters, development names to 64).
- `vendor/bin/worktree test` passes the test database in the environment, and creates it if it's missing. A worktree's `.env.testing`, if any, gets the name too, so `php artisan test` and `phpunit` use it, unless `phpunit.xml` sets `DB_DATABASE`.
- `phpunit.xml` must set `DB_DATABASE` (if at all) with `<env>` and no `force="true"`: a forced value or `<server>` overrides the worktree's.
- `vendor/bin/worktree clean` drops the databases of removed worktrees (after asking; `--force` skips the prompt). `--all` drops every worktree's. Only databases setup or test created are dropped, never the main checkout's.

## Configuration

`.worktree-isolation.env`, written by `install`. Only the runtime line is required; everything else is optional:

```env
# native | docker-compose | docker-image
WORKTREE_RUNTIME=native

# WORKTREE_TEST_COMMAND=php artisan test

# docker-compose
# WORKTREE_COMPOSE_SERVICE=app
# WORKTREE_COMPOSE_FILE=                    # empty: .env's COMPOSE_FILE, else compose.yaml or docker-compose.yml
# WORKTREE_COMPOSE_PROJECT_BASE=my-project   # stack name prefix; defaults to the directory name
# WORKTREE_DB_WAIT_SECONDS=30                # how long setup waits for a new stack's database

# docker-image
# WORKTREE_DOCKER_IMAGE=sail-8.4/app
# WORKTREE_DOCKER_NETWORK=myproject_sail
# WORKTREE_DOCKER_WORKDIR=/var/www/html
# WORKTREE_DOCKER_SERVICE=laravel.test           # whose environment containers get; defaults to the service using the image, empty for none
# WORKTREE_DOCKER_ENV=                          # more KEY=value pairs passed to every container, e.g. "PHPSTAN_MAX_PROCESSES=4"

# Per-worktree development databases (false or unset: worktrees share the main checkout's)
WORKTREE_DEV_DB_PER_WORKTREE=true
# WORKTREE_DEV_DB_MIGRATE_COMMAND=php artisan migrate --no-interaction   # empty to skip
# WORKTREE_DEV_DB_SEED_COMMAND=php artisan db:seed --no-interaction      # empty to skip

# WORKTREE_POST_SETUP_COMMAND=   # run at the end of setup, e.g. npm run build

# WORKTREE_TESTING_ENV_FILE=.env.testing
# WORKTREE_TESTING_ENV_EXAMPLE=.env.testing.example

# WORKTREE_COPY_FILES=   # more untracked files copied into each worktree, e.g. "auth.json"

# WORKTREE_PRUNE_AFTER=7         # days without git activity before prune removes a worktree; 0: never
# WORKTREE_PRUNE_BRANCH=        # merged into; empty: origin's default branch, else main or master
# WORKTREE_PRUNE_ON_SETUP=true   # false: setup doesn't run prune

# WORKTREE_MAIN_CHECKOUT_PASSTHROUGH=false   # true: vendor/bin/worktree <command> also works in the main checkout
```

Commands are run as you'd type them in a shell, so quoting works.

**Docker notes.** Containers run as your host user, so files they create in the worktree stay yours. The main clone's `.git` directory is mounted too, so git and tools that use it (e.g. `pint --dirty`) work. With Docker Compose (2.24+), each worktree runs its own stack with no published ports, so stacks never clash over host ports; commands reach them through `vendor/bin/worktree`. With the `docker-image` runtime, build the image first (`sail build` or `docker compose build`).

## AI agents

Agents need to know to use `vendor/bin/worktree` in worktrees. Add the instructions to your agent files with:

```bash
vendor/bin/worktree install --agents                       # AGENTS.md / CLAUDE.md, whichever exist (else AGENTS.md)
vendor/bin/worktree install --agents=CLAUDE.md,AGENTS.md   # or name the files
```

This adds a short block between `<!-- worktree-isolation:start -->` and `<!-- worktree-isolation:end -->` markers, and updates it in place when re-run. A `CLAUDE.md` that imports `@AGENTS.md` is left alone. The full agent guide is [docs/ai-agents.md](docs/ai-agents.md).

## License

MIT
