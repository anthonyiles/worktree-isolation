# Worktree Isolation

Per-worktree database isolation and bootstrap automation for PHP projects.

Works with **any PHP project** and **any development environment**: native PHP (Herd, Valet), Docker Compose, Laravel Sail, or any standalone Docker image. No framework required — Laravel integration is included but optional.

## The Problem

When using `git worktree` with a PHP project, each worktree needs:
- Composer and npm dependencies installed
- Environment files (`.env`, `.env.testing`) configured
- Isolated test and development databases, so parallel worktrees (and agents running migrations in them) never touch each other's or the main checkout's data

This package automates all of that. After installation, every `git worktree add` automatically bootstraps the new worktree — no manual steps required.

## Requirements

- PHP 8.2+
- Git 2.54+ (for config-based hooks)
- MySQL or MariaDB (for per-worktree database isolation)

## Installation

Every scenario starts the same way:

```bash
composer require anthonyiles/worktree-isolation --dev
```

This installs a single command, `vendor/bin/worktree`, kept in sync automatically by Composer. Nothing is copied into your project except the config file you choose to write (below). Laravel projects can swap `vendor/bin/worktree install` for `php artisan worktree:install` in any scenario below — same flags, `artisan` just delegates to the same installer.

Every operation is a subcommand of `vendor/bin/worktree`, Sail-style — `worktree install`, `worktree setup`, `worktree test`, `worktree clean` — plus anything else (`worktree composer install`, `worktree npm run dev`, `worktree php artisan migrate`, ...) runs straight inside the current worktree's runtime. Alias it once and that's the only command you ever need to remember:

```bash
alias worktree='vendor/bin/worktree'
```

[Running Arbitrary Commands](#running-arbitrary-commands) covers the passthrough form in full.

Whichever runtime you pick below, `vendor/bin/worktree install` always writes these same lines to `.worktree-isolation.env`:

```env
# Test command (default: php artisan test)
# WORKTREE_TEST_COMMAND=php vendor/bin/phpunit

# Common settings
WORKTREE_TESTING_ENV_FILE=.env.testing
WORKTREE_TESTING_ENV_EXAMPLE=.env.testing.example
WORKTREE_DB_PER_WORKTREE_KEY=TEST_DB_PER_WORKTREE

# Per-worktree development database (see "Per-Worktree Development Databases")
WORKTREE_DEV_DB_PER_WORKTREE=true
# WORKTREE_DEV_DB_MIGRATE_COMMAND=php artisan migrate --no-interaction
# WORKTREE_DEV_DB_SEED_COMMAND=php artisan db:seed --no-interaction
```

Non-Laravel projects should also set `WORKTREE_TEST_COMMAND` — see [Custom Test Command](#custom-test-command).

Now pick the section that matches your setup. Each gives the exact install command plus the runtime-specific lines it adds on top of the common settings above:

- [Native PHP](#native-php) — Herd, Valet, or any local PHP/Node install
- [Docker Compose](#docker-compose) — an app service defined in `docker-compose.yml`
- [Laravel Sail](#laravel-sail) — Sail, or any other standalone Docker image

---

### Native PHP

For Herd, Valet, or any setup where `composer`, `npm`, and your test runner already run directly on the host.

**1. Install**

```bash
vendor/bin/worktree install
# or: php artisan worktree:install  (Laravel projects)
```

This is the default runtime, so no `--runtime` flag is needed.

**2. Configure**

Nothing to pass in — this writes only:

```env
# Runtime driver: native | docker-compose | docker-image
WORKTREE_RUNTIME=native
```

plus the [common settings](#installation) above. There's nothing else to configure: Composer, npm, and your test runner already work on the host.

---

### Docker Compose

For projects where the app runs as a service in `docker-compose.yml`.

**1. Install**

```bash
vendor/bin/worktree install --runtime=docker-compose --compose-service=app
# or: php artisan worktree:install --runtime=docker-compose --compose-service=app
```

`--compose-service` should match the service name in your `docker-compose.yml` that has PHP, Composer, and Node available (default: `app`).

**2. Configure**

This writes:

```env
WORKTREE_RUNTIME=docker-compose
WORKTREE_COMPOSE_SERVICE=app
# WORKTREE_COMPOSE_FILE=docker-compose.yml
WORKTREE_COMPOSE_PROJECT_BASE=my-project
```

plus the [common settings](#installation) above. `WORKTREE_COMPOSE_PROJECT_BASE` defaults to your project directory's name (sanitized: lowercased, non-alphanumeric characters collapsed to `-`); override it with `--compose-project-base=NAME` at install time if that would collide with an unrelated project on the same Docker host.

**3. What this gets you**

`vendor/bin/worktree setup` brings up its **own** Compose stack for each worktree — `docker compose up -d` — under an isolated `-p <project>` derived from `WORKTREE_COMPOSE_PROJECT_BASE` and the worktree's directory name (e.g. `my-project-feature-auth`), the same way the per-worktree test database name is derived. `composer install`, `npm install`, and `vendor/bin/worktree test` all pass that same `-p` flag through to `docker compose exec`, so each worktree's stack — containers, networks, volumes — stays completely separate from every other worktree's. `docker compose up -d` before `git worktree add` is no longer something you need to do by hand.

**Not covered by this:** fixed host port bindings in your `docker-compose.yml` (e.g. `8080:80`) will still collide across worktrees — parameterize those yourself (e.g. `${APP_PORT:-8080}:80`) if you plan to run multiple worktrees' stacks at once. `vendor/bin/worktree test` assumes `vendor/bin/worktree setup` already brought the stack up for that worktree; if it hasn't, `docker compose exec` fails with Docker's normal error.

Need to run something else in that same container — `composer require`, `npm run build`, an artisan command? Use `vendor/bin/worktree` (see [Running Arbitrary Commands](#running-arbitrary-commands)) instead of calling `docker compose exec` yourself — it threads the same `-p` flag through automatically:

```bash
vendor/bin/worktree composer require guzzlehttp/guzzle
vendor/bin/worktree npm run build
```

---

### Laravel Sail

Sail is just Laravel's name for a pre-built Docker image, so it uses the `docker-image` runtime — this also covers any other standalone Docker image (non-Sail) the same way, just with different `--docker-image`/`--docker-network` values.

**1. Install**

```bash
vendor/bin/worktree install --runtime=docker-image --docker-image="sail-8.5/app" --docker-network="myproject_sail"
# or: php artisan worktree:install --runtime=docker-image --docker-image="sail-8.5/app" --docker-network="myproject_sail"
```

- `--docker-image` — the image Sail already built (check with `docker images`, or see `vendor/bin/sail` config; typically `<project>-<php-version>/app`)
- `--docker-network` — the Docker network Sail's containers (including MySQL) run on, so the ephemeral test container can reach them (typically `<project>_sail`)

**2. Configure**

This writes:

```env
WORKTREE_RUNTIME=docker-image
WORKTREE_DOCKER_IMAGE=sail-8.5/app
WORKTREE_DOCKER_NETWORK=myproject_sail
# WORKTREE_DOCKER_WORKDIR=/var/www/html
```

plus the [common settings](#installation) above. `composer install`, `npm install`, and your test command each run via a throwaway `docker run --rm` against that image, attached to the given network — the image must already be built (`vendor/bin/sail build`, or `docker compose build` for a non-Sail standalone image).

**3. Important**

**Don't call `vendor/bin/sail` (or `docker compose`) directly from inside a worktree.** Sail's own CLI checks whether its containers are already running and, if so, `exec`s straight into them instead of starting fresh — and that container's bind mount is fixed to wherever it was originally started (normally your main checkout, since that's the stack `WORKTREE_DOCKER_NETWORK` points at). Run `sail composer install` or `sail artisan test` from a worktree and you'll silently install dependencies or run tests against the **main checkout's files**, not the worktree's — the exact bug this package exists to prevent, just reached via Sail's CLI instead of raw Docker Compose. `vendor/bin/worktree setup` and `vendor/bin/worktree test` sidestep this entirely: they never call `sail`, they run `docker run --rm -v <this-worktree>:...` directly against the built image, so the bind mount is always correct. Always use `vendor/bin/worktree test` / `vendor/bin/worktree setup` instead of Sail's CLI once you're working across worktrees.

That covers install and test, but what about everything else Sail normally handles — `sail composer require`, `sail npm run dev`, `sail artisan migrate`? Use `vendor/bin/worktree` (see [Running Arbitrary Commands](#running-arbitrary-commands)) instead — same throwaway `docker run --rm -v <this-worktree>:...` approach, so it's always bind-mounted to the correct worktree:

```bash
vendor/bin/worktree composer require guzzlehttp/guzzle
vendor/bin/worktree npm run dev
vendor/bin/worktree php artisan migrate
```

---

### Custom Test Command

By default, tests run via `php artisan test`. For non-Laravel projects (in any of the scenarios above), set a custom test command:

```bash
vendor/bin/worktree install --test-command="php vendor/bin/phpunit"
```

Or set `WORKTREE_TEST_COMMAND` directly in `.worktree-isolation.env`:

```env
WORKTREE_TEST_COMMAND=php vendor/bin/phpunit
```

### For Other Engineers

After pulling a branch that has `.worktree-isolation.env` committed, each engineer just runs:

```bash
vendor/bin/worktree install
# or: php artisan worktree:install  (Laravel projects)
```

The command is idempotent — it detects the existing `.worktree-isolation.env` and only (re)configures the git hook.

Hook activation is local to that clone (`git config --local`), so each engineer runs this once per clone — same as any git-hooks tool (Husky, pre-commit, etc.), since git never auto-trusts hooks from a fresh clone. It is **not** tied to any branch: because the hook command is registered as an absolute path resolved at install time, worktrees created from any branch — including ones that never had this package's config committed — get bootstrapped automatically. You don't need to merge anything hook-related into every branch you plan to `git worktree add` from.

## How It Works

### Automatic Worktree Bootstrap

When you run `git worktree add`, the `post-checkout` hook detects the new worktree and automatically runs the same setup `vendor/bin/worktree setup` performs (invoked directly from inside `vendor/`), which:

1. Copies `.env` from the main repo
2. Copies `.env.testing` (or falls back to `.env.testing.example`)
3. Forces `TEST_DB_PER_WORKTREE=true` in the worktree's `.env.testing`
4. For the `docker-compose` runtime: brings up this worktree's own Compose stack (`docker compose -p <isolated-project-name> up -d`)
5. Runs `composer install` (via the configured runtime)
6. Derives the per-worktree test database name, creates it, and writes it as `DB_DATABASE` in the worktree's `.env.testing`
7. If `WORKTREE_DEV_DB_PER_WORKTREE=true`: derives the per-worktree development database name, creates it, writes it as `DB_DATABASE` in the worktree's `.env`, then migrates it (and seeds it, if it was just created)
8. Runs `npm install` (via the configured runtime)

### Per-Worktree Test Databases

The database name is derived from the worktree directory:

```
testing-{worktree-folder-name}
```

For example, a worktree at `../worktrees/my-project/feature-auth` gets database `testing-feature-auth`. A safety guard ensures the derived name always contains "test" to prevent accidental use of production databases.

Because this name is written directly into `.env.testing` at bootstrap time (step 6 above), it applies no matter how you run tests — `vendor/bin/worktree test`, `sail test`, `php artisan test`, `vendor/bin/phpunit`, or anything else that reads `.env.testing` the normal way. `vendor/bin/worktree test` also re-derives and re-creates the database dynamically on every run, so it stays correct even if step 6 failed at setup time (e.g. the database wasn't reachable yet) or the worktree directory gets renamed later.

### Per-Worktree Development Databases

Each worktree also gets its own development database, so `php artisan migrate` (or an agent running it) in a feature branch never touches the main checkout's data:

```
{DB_DATABASE}_wt_{worktree-folder-name}
```

For example, with `DB_DATABASE=myapp` in the main repo's `.env`, a worktree at `../worktrees/my-project/feature-auth` gets `myapp_wt_feature-auth`, written into that worktree's `.env`. The main repo's `.env` is never modified.

Setup then runs `WORKTREE_DEV_DB_MIGRATE_COMMAND` (default `php artisan migrate --no-interaction`) every time, and `WORKTREE_DEV_DB_SEED_COMMAND` (default `php artisan db:seed --no-interaction`) only when the database was just created, since seeders usually aren't safe to re-run. Set either to an empty value to skip it, or point them at your own scripts for non-Laravel projects:

```env
WORKTREE_DEV_DB_SEED_COMMAND=php artisan db:seed --class=DemoSeeder --no-interaction
```

Only MySQL/MariaDB connections are handled; setup skips the step for anything else. SQLite needs nothing extra when the database file lives inside the project, since each worktree has its own copy. `vendor/bin/worktree install` writes `WORKTREE_DEV_DB_PER_WORKTREE=true`; a `.worktree-isolation.env` without that line (including one written by an earlier version) keeps sharing one development database across worktrees, as does setting it to `false`.

### Running Tests

From any worktree:

```bash
vendor/bin/worktree test                              # run all tests
vendor/bin/worktree test --filter=MyTest              # filter tests
vendor/bin/worktree test tests/Feature/MyTest.php     # specific file
```

### Running Arbitrary Commands

`vendor/bin/worktree setup` only runs its fixed bootstrap steps, and `vendor/bin/worktree test` only runs your configured test command. For everything else — `composer require`, `npm run build`, `npm run dev`, `php artisan migrate`, or any other command — pass it straight to `vendor/bin/worktree`:

```bash
vendor/bin/worktree composer require guzzlehttp/guzzle
vendor/bin/worktree npm run build
vendor/bin/worktree php artisan migrate
```

It dispatches through the same runtime resolution as `vendor/bin/worktree test` and `vendor/bin/worktree setup`:

- `native` — runs the command directly on the host, from the worktree's root.
- `docker-compose` — runs it via `docker compose -p <isolated-project> exec` in this worktree's own service container.
- `docker-image` — runs it via a throwaway `docker run --rm -v <this-worktree>:...` against the built image, same as `vendor/bin/worktree test`.

Unlike `vendor/bin/worktree test`, passthrough commands don't load `.env.testing`. `worktree php artisan migrate` runs against the worktree's `.env`, which means its own [development database](#per-worktree-development-databases).

`install`, `setup`, `test`, and `clean` are its own built-in subcommands (covered above) — everything else is passthrough. Alias it for a Sail-like feel:

```bash
alias worktree='vendor/bin/worktree'

worktree setup
worktree test --filter=MyTest
worktree composer install
worktree npm run dev
worktree clean
```

### Cleaning Up

Drop all per-worktree test and development databases:

```bash
vendor/bin/worktree clean
# or: php artisan worktree:clean  (Laravel projects)
```

This lists all databases matching `{base}-*` (test, from `.env.testing`) and `{base}_wt_*` (development, from `.env`) and asks for confirmation before dropping them. Use `--force` to skip the prompt.

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
# WORKTREE_COMPOSE_PROJECT_BASE=my-project

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

# --- Per-worktree development database (off when unset) ---
WORKTREE_DEV_DB_PER_WORKTREE=true
# WORKTREE_DEV_DB_MIGRATE_COMMAND=php artisan migrate --no-interaction
# WORKTREE_DEV_DB_SEED_COMMAND=php artisan db:seed --no-interaction
```

### Laravel Config (optional)

Laravel projects can also publish a config file:

```bash
php artisan vendor:publish --tag=worktree-isolation-config
```

This creates `config/worktree-isolation.php` which mirrors the `.worktree-isolation.env` settings through Laravel's config system.

## Available Commands

`vendor/bin/worktree` is the only command Composer installs — always matches the installed package version, nothing to republish on upgrade.

| Subcommand | Purpose |
|---|---|
| `vendor/bin/worktree install` | Install/configure worktree isolation (no framework needed) |
| `vendor/bin/worktree setup` | Bootstrap a worktree (env files, dependencies) — normally run automatically by the git hook |
| `vendor/bin/worktree test` | Run tests with per-worktree database isolation |
| `vendor/bin/worktree clean` | Drop per-worktree test and development databases (no framework needed) |
| `vendor/bin/worktree <anything else>` | Run that command inside the current worktree's runtime (`composer`, `npm`, `artisan`, ...) |

## Upgrading from 1.x

- The separate Composer bins are gone. Replace `vendor/bin/worktree-install`, `vendor/bin/worktree-setup`, `vendor/bin/test` and `vendor/bin/worktree-clean` with `vendor/bin/worktree install`, `setup`, `test` and `clean` in scripts, CI and aliases. The git hook needs no changes.
- Per-worktree development databases stay off until you add `WORKTREE_DEV_DB_PER_WORKTREE=true` to `.worktree-isolation.env`.
- A docker-compose config without `WORKTREE_COMPOSE_PROJECT_BASE` falls back to the main checkout's directory name, the same default the installer writes.

## AI Agent Integration

For the `native` runtime, the per-worktree database is baked into `.env.testing` at bootstrap time (see [Per-Worktree Test Databases](#per-worktree-test-databases)), so an agent running `php artisan test` directly still hits the correct, isolated database.

For `docker-compose` and `docker-image` (Sail) runtimes, that guarantee only holds if the agent goes through this package's commands. An agent that runs `sail artisan test`, `sail composer install`, or raw `docker compose exec` directly from a worktree can end up executing inside a container bind-mounted to a *different* checkout (see the warning in [Laravel Sail](#laravel-sail) above) — at that point it's reading the wrong worktree's `.env.testing` entirely, isolated database name or not. `vendor/bin/worktree` is the only command that guarantees the correct worktree, in every runtime, for any command — not just install and test. Add this to your project's cursor rules or AGENTS.md:

```markdown
**Worktrees:** If the working directory is a git worktree (`.git` is a file, not a directory),
always run commands through `vendor/bin/worktree` — `vendor/bin/worktree test`,
`vendor/bin/worktree setup`, `vendor/bin/worktree composer ...`, `vendor/bin/worktree npm ...`,
`vendor/bin/worktree php artisan ...` — never call `sail`, `docker compose`, `composer`, `npm`,
or `php artisan` directly. Those can silently execute inside another worktree's (or the main
checkout's) container. `vendor/bin/worktree` handles runtime dispatch (native, Docker Compose,
Sail) on top of the per-worktree database isolation already active in .env and .env.testing.
```

## License

MIT
