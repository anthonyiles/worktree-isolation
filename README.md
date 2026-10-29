# Worktree Isolation

Make every `git worktree` of a PHP project ready to use the moment it's created, with its own dependencies, env files and databases.

After a one-off install, `git worktree add` automatically:

- copies `.env` and `.env.testing` from the main checkout
- gives the worktree its own MySQL/MariaDB test and development databases, so parallel worktrees (and AI agents running migrations in them) never touch each other's data or the main checkout's
- runs `composer install`, and your JavaScript package manager's install when there's a `package.json`

It works with native PHP (Herd, Valet), Docker Compose, Laravel Sail or any Docker image. Laravel isn't required.

## Requirements

- PHP 8.2+
- Git 2.54+
- MySQL or MariaDB, for per-worktree databases (SQLite needs nothing extra)

## Install

```bash
composer require anthonyiles/worktree-isolation --dev
vendor/bin/worktree install
```

Run `install` on the host, not inside Sail. It writes `.worktree-isolation.env` (commit it) and registers a git hook for this clone. Each teammate runs `vendor/bin/worktree install` once per clone; it keeps the committed config and just registers the hook, which then works for worktrees of any branch.

Pick the runtime that matches how you run PHP:

| Setup | Install command |
|---|---|
| Herd, Valet, local PHP | `vendor/bin/worktree install` |
| Laravel Sail | `vendor/bin/worktree install` (Sail's image and network are detected) |
| Docker Compose | `vendor/bin/worktree install --runtime=docker-compose --compose-service=app` |
| Any other Docker image | `vendor/bin/worktree install --runtime=docker-image --docker-image=myapp --docker-network=myapp_default` |

Not using Laravel? Add `--test-command="php vendor/bin/phpunit"` (or your runner). Laravel projects can use `php artisan worktree:install` with the same options.

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
vendor/bin/worktree clean --stale             # drop databases of removed worktrees
```

Tip: `alias worktree='vendor/bin/worktree'`.

> **With Sail or Docker Compose, don't call `sail` or `docker compose` directly inside a worktree.** They exec into whichever container is already running, which is usually mounted on the main checkout, so commands run against the wrong code and database. `vendor/bin/worktree` always targets the current worktree.

## What setup does

1. Copies `.env` and `.env.testing` (or `.env.testing.example`) from the main checkout, if the worktree doesn't have them.
2. Points both at the worktree's own databases (see below), before anything else runs.
3. Docker Compose only: starts the worktree's own stack with `docker compose -p <project>-<worktree> up -d`.
4. Runs `composer install`.
5. Creates the test and development databases. A new development database is migrated and seeded; an existing one is only migrated.
6. If there's a `package.json`, runs `npm install` (or `pnpm`, `yarn` or `bun`, by lockfile). A failure here only warns.

## Databases

Each worktree's databases are named after its directory:

| | Main checkout | Worktree `feature-auth` |
|---|---|---|
| Test (`.env.testing`) | `testing` | `testing_wt_feature-auth` |
| Development (`.env`) | `myapp` | `myapp_wt_feature-auth` |

- Only MySQL/MariaDB connections are changed. SQLite and others are left alone.
- The main checkout's test database name must contain `test`, and a worktree is never pointed at one of the main checkout's databases.
- Long names are shortened with a hash (test names to 40 characters, development names to 64).
- The names are written into the worktree's env files, so `php artisan test`, `phpunit` and the like use them too. `vendor/bin/worktree test` also creates the test database if it's missing.
- `vendor/bin/worktree clean` drops all per-worktree databases (after asking; `--force` skips the prompt). `--stale` only drops those whose worktree has been removed. The main checkout's databases are never dropped.

## Configuration

`.worktree-isolation.env`, written by `install`. Only the runtime line is required; everything else is optional:

```env
# native | docker-compose | docker-image
WORKTREE_RUNTIME=native

# WORKTREE_TEST_COMMAND=php artisan test

# docker-compose
# WORKTREE_COMPOSE_SERVICE=app
# WORKTREE_COMPOSE_FILE=docker-compose.yml
# WORKTREE_COMPOSE_PROJECT_BASE=my-project   # stack name prefix; defaults to the directory name
# WORKTREE_DB_WAIT_SECONDS=30                # how long setup waits for a new stack's database

# docker-image
# WORKTREE_DOCKER_IMAGE=sail-8.4/app
# WORKTREE_DOCKER_NETWORK=myproject_sail
# WORKTREE_DOCKER_WORKDIR=/var/www/html
# WORKTREE_EXTRA_ENV_VARS="FOO BAR"          # extra .env.testing vars to pass to the test container

# Per-worktree development databases (off when this line is missing)
WORKTREE_DEV_DB_PER_WORKTREE=true
# WORKTREE_DEV_DB_MIGRATE_COMMAND=php artisan migrate --no-interaction   # empty to skip
# WORKTREE_DEV_DB_SEED_COMMAND=php artisan db:seed --no-interaction      # empty to skip

# WORKTREE_TESTING_ENV_FILE=.env.testing
# WORKTREE_TESTING_ENV_EXAMPLE=.env.testing.example
```

Commands are run as you'd type them in a shell, so quoting works.

**Docker notes.** Containers run as your host user, so files they create in the worktree stay yours. With Docker Compose, each worktree runs its own stack, so fixed host ports (e.g. `8080:80`) clash between worktrees: make them configurable (e.g. `${APP_PORT:-8080}:80`) if you run several at once. With the `docker-image` runtime, build the image first (`sail build` or `docker compose build`).

## AI agents

Agents need to know to use `vendor/bin/worktree` in worktrees. Add the instructions to your agent files with:

```bash
vendor/bin/worktree install --agents                       # AGENTS.md / CLAUDE.md, whichever exist (else AGENTS.md)
vendor/bin/worktree install --agents=CLAUDE.md,AGENTS.md   # or name the files
```

This adds a short block between `<!-- worktree-isolation:start -->` and `<!-- worktree-isolation:end -->` markers, and updates it in place when re-run. A `CLAUDE.md` that imports `@AGENTS.md` is left alone. The full agent guide is [docs/ai-agents.md](docs/ai-agents.md).

## Upgrading

- Use `vendor/bin/worktree install|setup|test|clean` instead of the old `vendor/bin/worktree-install`, `worktree-setup`, `test` and `worktree-clean`.
- Configs written by older versions may lack `WORKTREE_DEV_DB_PER_WORKTREE=true`; add it to get per-worktree development databases.
- `WORKTREE_DB_PER_WORKTREE_KEY` is no longer read; the flag is always `TEST_DB_PER_WORKTREE`.
- The scripts never read `config/worktree-isolation.php`. If you published it, you can delete it.

## License

MIT
