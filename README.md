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

```bash
composer require anthonyiles/worktree-isolation --dev
```

Then run the install script with your preferred runtime:

### Any PHP Project

```bash
php vendor/anthonyiles/worktree-isolation/stubs/bin/worktree-install
```

After the first install, re-runs are simpler since scripts are published to `bin/`:

```bash
php bin/worktree-install
```

### Laravel Projects

Laravel projects get artisan integration automatically:

```bash
php artisan worktree:install
```

### Runtime Options

All install paths accept the same runtime options:

**Native PHP** (default — Herd, Valet, local PHP):

```bash
php bin/worktree-install
# or: php artisan worktree:install
```

**Docker Compose:**

```bash
php bin/worktree-install --runtime=docker-compose --compose-service=app
# or: php artisan worktree:install --runtime=docker-compose --compose-service=app
```

**Docker Image** (Sail or standalone):

```bash
php bin/worktree-install --runtime=docker-image --docker-image="myapp" --docker-network="myapp_default"
# or: php artisan worktree:install --runtime=docker-image --docker-image="sail-8.5/app" --docker-network="myproject_sail"
```

### Custom Test Command

By default, tests run via `php artisan test`. For non-Laravel projects, set a custom test command:

```bash
php bin/worktree-install --test-command="php vendor/bin/phpunit"
```

Or set `WORKTREE_TEST_COMMAND` in `.worktree-isolation.env`:

```env
WORKTREE_TEST_COMMAND=php vendor/bin/phpunit
```

---

The install command does everything:
- Verifies Git 2.54+ is installed
- Publishes `bin/worktree-setup`, `bin/test`, `bin/worktree-install`, and `bin/worktree-clean` scripts
- Publishes the post-checkout git hook to `.githooks/`
- Makes all scripts executable
- Registers the hook locally via `git config --local hook.worktree-setup.command`/`event`, pointing at the absolute path of `.githooks/post-checkout-worktree-setup.sh` in this clone
- Creates `.worktree-isolation.env` with your runtime settings

### For other engineers

After pulling the branch, each engineer just runs:

```bash
php bin/worktree-install
# or: php artisan worktree:install  (Laravel projects)
```

The command is idempotent and handles everything.

Hook activation is local to that clone (`git config --local`), so each engineer runs this once per clone — same as any git-hooks tool (Husky, pre-commit, etc.), since git never auto-trusts hooks from a fresh clone. It is **not** tied to any branch: because the hook command is registered as an absolute path resolved at install time, worktrees created from any branch — including ones that never had `.githooks/` committed — get bootstrapped automatically. You don't need to merge the hook into every branch you plan to `git worktree add` from.

## How It Works

### Automatic Worktree Bootstrap

When you run `git worktree add`, the `post-checkout` hook detects the new worktree and runs `bin/worktree-setup`, which:

1. Copies `.env` from the main repo
2. Copies `.env.testing` (or falls back to `.env.testing.example`)
3. Forces `TEST_DB_PER_WORKTREE=true` in the worktree's `.env.testing`
4. Runs `composer install` (via the configured runtime)
5. Runs `npm install` (via the configured runtime)

### Per-Worktree Test Databases

When `TEST_DB_PER_WORKTREE=true`, `bin/test` derives a unique database name from the worktree directory:

```
testing-{worktree-folder-name}
```

For example, a worktree at `../worktrees/my-project/feature-auth` gets database `testing-feature-auth`.

The database is created automatically on first test run. A safety guard ensures the derived name always contains "test" to prevent accidental use of production databases.

### Running Tests

From any worktree:

```bash
bin/test                              # run all tests
bin/test --filter=MyTest              # filter tests
bin/test tests/Feature/MyTest.php     # specific file
```

### Cleaning Up

Drop all per-worktree test databases:

```bash
php bin/worktree-clean
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

### `.worktree-isolation.env`

Project-level configuration (committed to repo):

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

## Published Scripts

| Script | Purpose |
|---|---|
| `bin/test` | Run tests with per-worktree database isolation |
| `bin/worktree-setup` | Bootstrap a worktree (env files, dependencies) |
| `bin/worktree-install` | Install/configure worktree isolation (no framework needed) |
| `bin/worktree-clean` | Drop per-worktree test databases (no framework needed) |

## AI Agent Integration

Add this to your project's cursor rules or AGENTS.md:

```markdown
**Worktrees:** If the working directory is a git worktree (`.git` is a file, not a directory),
you **must** use `bin/test` instead of your usual test command. The `bin/test` script handles
per-worktree database isolation and runtime dispatch.
```

## License

MIT
