# Worktree Isolation

Per-worktree test database isolation and bootstrap automation for PHP projects.

Works with **any PHP project** and **any development environment**: native PHP (Herd, Valet), Docker Compose, Laravel Sail, or any standalone Docker image. No framework required — Laravel integration is included but optional.

## The Problem

When using `git worktree` with a PHP project, each worktree needs:
- Composer and npm dependencies installed
- Environment files (`.env`, `.env.testing`) configured
- An isolated test database to avoid conflicts with other worktrees running in parallel

This package automates all of that. After installation, every `git worktree add` automatically bootstraps the new worktree — no manual steps required.

## Requirements

- PHP 8.2+
- Git 2.54+ (for config-based hooks)
- MySQL (for per-worktree database isolation)

## Installation

Every scenario starts the same way:

```bash
composer require anthonyiles/worktree-isolation --dev
```

This installs three commands under `vendor/bin/` — `worktree-install`, `worktree-setup`, `test`, `worktree-clean` — kept in sync automatically by Composer. Nothing is copied into your project except the config file you choose to write (below). Laravel projects can swap `vendor/bin/worktree-install` for `php artisan worktree:install` in any scenario below — same flags, `artisan` just delegates to the same installer.

Then pick the section that matches your setup:

- [Native PHP](#native-php) — Herd, Valet, or any local PHP/Node install
- [Docker Compose](#docker-compose) — a service running via `docker compose up -d`
- [Laravel Sail](#laravel-sail) — Sail, or any other standalone Docker image

---

### Native PHP

For Herd, Valet, or any setup where `composer`, `npm`, and your test runner already run directly on the host.

```bash
vendor/bin/worktree-install
# or: php artisan worktree:install  (Laravel projects)
```

This is the default runtime, so no `--runtime` flag is needed. It writes `.worktree-isolation.env`:

```env
# Runtime driver: native | docker-compose | docker-image
WORKTREE_RUNTIME=native

# Test command (default: php artisan test)
# WORKTREE_TEST_COMMAND=php vendor/bin/phpunit

# Common settings
WORKTREE_TESTING_ENV_FILE=.env.testing
WORKTREE_TESTING_ENV_EXAMPLE=.env.testing.example
WORKTREE_DB_PER_WORKTREE_KEY=TEST_DB_PER_WORKTREE
```

Non-Laravel projects should also set `WORKTREE_TEST_COMMAND` — see [Custom Test Command](#custom-test-command).

---

### Docker Compose

For projects where the app runs as a service in `docker-compose.yml`, started with `docker compose up -d`.

```bash
vendor/bin/worktree-install --runtime=docker-compose --compose-service=app
# or: php artisan worktree:install --runtime=docker-compose --compose-service=app
```

`--compose-service` should match the service name in your `docker-compose.yml` that has PHP, Composer, and Node available (default: `app`). This writes:

```env
WORKTREE_RUNTIME=docker-compose

# Test command (default: php artisan test)
# WORKTREE_TEST_COMMAND=php vendor/bin/phpunit

# docker-compose runtime settings
WORKTREE_COMPOSE_SERVICE=app
# WORKTREE_COMPOSE_FILE=docker-compose.yml

# Common settings
WORKTREE_TESTING_ENV_FILE=.env.testing
WORKTREE_TESTING_ENV_EXAMPLE=.env.testing.example
WORKTREE_DB_PER_WORKTREE_KEY=TEST_DB_PER_WORKTREE
```

`composer install`, `npm install`, and your test command all run via `docker compose exec -T`, so the compose stack must already be up when you run `git worktree add` or `vendor/bin/test`.

---

### Laravel Sail

Sail is just Laravel's name for a pre-built Docker image, so it uses the `docker-image` runtime — this also covers any other standalone Docker image (non-Sail) the same way, just with different `--docker-image`/`--docker-network` values.

```bash
vendor/bin/worktree-install --runtime=docker-image --docker-image="sail-8.5/app" --docker-network="myproject_sail"
# or: php artisan worktree:install --runtime=docker-image --docker-image="sail-8.5/app" --docker-network="myproject_sail"
```

- `--docker-image` — the image Sail already built (check with `docker images`, or see `vendor/bin/sail` config; typically `<project>-<php-version>/app`)
- `--docker-network` — the Docker network Sail's containers (including MySQL) run on, so the ephemeral test container can reach them (typically `<project>_sail`)

This writes:

```env
WORKTREE_RUNTIME=docker-image

# Test command (default: php artisan test)
# WORKTREE_TEST_COMMAND=php vendor/bin/phpunit

# docker-image runtime settings
WORKTREE_DOCKER_IMAGE=sail-8.5/app
WORKTREE_DOCKER_NETWORK=myproject_sail
# WORKTREE_DOCKER_WORKDIR=/var/www/html

# Common settings
WORKTREE_TESTING_ENV_FILE=.env.testing
WORKTREE_TESTING_ENV_EXAMPLE=.env.testing.example
WORKTREE_DB_PER_WORKTREE_KEY=TEST_DB_PER_WORKTREE
```

`composer install`, `npm install`, and your test command each run via a throwaway `docker run --rm` against that image, attached to the given network — the image must already be built (`vendor/bin/sail build`, or `docker compose build` for a non-Sail standalone image).

---

### Custom Test Command

By default, tests run via `php artisan test`. For non-Laravel projects (in any of the scenarios above), set a custom test command:

```bash
vendor/bin/worktree-install --test-command="php vendor/bin/phpunit"
```

Or set `WORKTREE_TEST_COMMAND` directly in `.worktree-isolation.env`:

```env
WORKTREE_TEST_COMMAND=php vendor/bin/phpunit
```

### For Other Engineers

After pulling a branch that has `.worktree-isolation.env` committed, each engineer just runs:

```bash
vendor/bin/worktree-install
# or: php artisan worktree:install  (Laravel projects)
```

The command is idempotent — it detects the existing `.worktree-isolation.env` and only (re)configures the git hook.

Hook activation is local to that clone (`git config --local`), so each engineer runs this once per clone — same as any git-hooks tool (Husky, pre-commit, etc.), since git never auto-trusts hooks from a fresh clone. It is **not** tied to any branch: because the hook command is registered as an absolute path resolved at install time, worktrees created from any branch — including ones that never had this package's config committed — get bootstrapped automatically. You don't need to merge anything hook-related into every branch you plan to `git worktree add` from.

## How It Works

### Automatic Worktree Bootstrap

When you run `git worktree add`, the `post-checkout` hook detects the new worktree and runs `worktree-setup` (straight out of `vendor/`), which:

1. Copies `.env` from the main repo
2. Copies `.env.testing` (or falls back to `.env.testing.example`)
3. Forces `TEST_DB_PER_WORKTREE=true` in the worktree's `.env.testing`
4. Runs `composer install` (via the configured runtime)
5. Runs `npm install` (via the configured runtime)

### Per-Worktree Test Databases

When `TEST_DB_PER_WORKTREE=true`, `vendor/bin/test` derives a unique database name from the worktree directory:

```
testing-{worktree-folder-name}
```

For example, a worktree at `../worktrees/my-project/feature-auth` gets database `testing-feature-auth`.

The database is created automatically on first test run. A safety guard ensures the derived name always contains "test" to prevent accidental use of production databases.

### Running Tests

From any worktree:

```bash
vendor/bin/test                              # run all tests
vendor/bin/test --filter=MyTest              # filter tests
vendor/bin/test tests/Feature/MyTest.php     # specific file
```

### Cleaning Up

Drop all per-worktree test databases:

```bash
vendor/bin/worktree-clean
# or: php artisan worktree:clean  (Laravel projects)
```

This lists all databases matching the `{base}-*` pattern and asks for confirmation before dropping them. Use `--force` to skip the prompt.

## Configuration

### Runtime Drivers

| Driver | When to use | Requirements |
|---|---|---|
| `native` (default) | Herd, Valet, any local PHP/Node | PHP, Composer, Node on host |
| `docker-compose` | Docker Compose projects | Running `docker compose up -d` |
| `docker-image` | Sail or standalone Docker image | Pre-built Docker image |

### `.worktree-isolation.env` (full reference)

Project-level configuration (committed to repo). The scenario sections above show the subset of these that matter for each runtime — this is the complete list:

```env
# Runtime driver: native | docker-compose | docker-image
WORKTREE_RUNTIME=native

# Test command (default: php artisan test)
# WORKTREE_TEST_COMMAND=php vendor/bin/phpunit

# --- docker-compose driver ---
# WORKTREE_COMPOSE_SERVICE=app
# WORKTREE_COMPOSE_FILE=docker-compose.yml

# --- docker-image driver ---
# WORKTREE_DOCKER_IMAGE=myapp
# WORKTREE_DOCKER_NETWORK=myapp_default
# WORKTREE_DOCKER_WORKDIR=/var/www/html

# --- Common ---
WORKTREE_TESTING_ENV_FILE=.env.testing
WORKTREE_TESTING_ENV_EXAMPLE=.env.testing.example
WORKTREE_DB_PER_WORKTREE_KEY=TEST_DB_PER_WORKTREE

# Additional env vars to forward to the test container (docker-image only)
# WORKTREE_EXTRA_ENV_VARS=
```

### Laravel Config (optional)

Laravel projects can also publish a config file:

```bash
php artisan vendor:publish --tag=worktree-isolation-config
```

This creates `config/worktree-isolation.php` which mirrors the `.worktree-isolation.env` settings through Laravel's config system.

## Available Commands

All installed via Composer's `bin` mechanism — `vendor/bin/*` always matches the installed package version, nothing to republish on upgrade.

| Command | Purpose |
|---|---|
| `vendor/bin/test` | Run tests with per-worktree database isolation |
| `vendor/bin/worktree-setup` | Bootstrap a worktree (env files, dependencies) — normally run automatically by the git hook |
| `vendor/bin/worktree-install` | Install/configure worktree isolation (no framework needed) |
| `vendor/bin/worktree-clean` | Drop per-worktree test databases (no framework needed) |

## AI Agent Integration

Add this to your project's cursor rules or AGENTS.md:

```markdown
**Worktrees:** If the working directory is a git worktree (`.git` is a file, not a directory),
you **must** use `vendor/bin/test` instead of your usual test command. It handles per-worktree
database isolation and runtime dispatch.
```

## License

MIT
