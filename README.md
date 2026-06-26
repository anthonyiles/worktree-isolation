# Laravel Worktree Isolation

Per-worktree test database isolation and bootstrap automation for Laravel Sail projects.

## The Problem

When using `git worktree` with Laravel Sail, each worktree needs:
- Composer and npm dependencies installed
- Environment files (`.env`, `.env.testing`) configured
- An isolated test database to avoid conflicts with other worktrees running in parallel

This package automates all of that. After installation, every `git worktree add` automatically bootstraps the new worktree — no manual steps required.

## Requirements

- PHP 8.2+
- Laravel 11 or 12
- Laravel Sail
- Git 2.54+ (for config-based hooks)
- Docker

## Installation

```bash
composer require laravel-worktree-isolation/laravel-worktree-isolation --dev
```

Then run the install command:

```bash
php artisan worktree:install --docker-image="sail-8.5/app" --docker-network="myproject_sail"
```

That single command does everything:
- Verifies Git 2.54+ is installed
- Publishes `bin/worktree-setup` and `bin/test` scripts
- Publishes the post-checkout git hook to `.githooks/`
- Makes all scripts executable (`chmod +x`)
- Creates/updates `.githooks.config` with the hook registration
- Configures `git config --local` to use the hooks
- Creates `.worktree-isolation.env` with your Docker settings
- Publishes `config/worktree-isolation.php`

### For other engineers

After pulling the branch, each engineer just runs:

```bash
php artisan worktree:install
```

No separate make targets or manual chmod needed — the command is idempotent and handles everything.

## How It Works

### Automatic Worktree Bootstrap

When you run `git worktree add`, the `post-checkout` hook detects the new worktree (null previous HEAD) and runs `bin/worktree-setup`, which:

1. Copies `.env` from the main repo
2. Copies `.env.testing` (or falls back to `.env.testing.example`)
3. Forces `TEST_DB_PER_WORKTREE=true` in the worktree's `.env.testing`
4. Runs `composer install` via the Sail Docker image
5. Runs `npm install` via the Sail Docker image

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
bin/test --compact                    # compact output
bin/test tests/Feature/MyTest.php     # specific file
```

### Cleaning Up

Drop all per-worktree test databases:

```bash
php artisan worktree:clean
```

This lists all `testing-*` databases and asks for confirmation before dropping them. Use `--force` to skip the prompt.

## Configuration

### `.worktree-isolation.env`

Project-level configuration (committed to repo):

```env
WORKTREE_DOCKER_IMAGE=sail-8.5/app
WORKTREE_DOCKER_NETWORK=myproject_sail
WORKTREE_TESTING_ENV_FILE=.env.testing
WORKTREE_TESTING_ENV_EXAMPLE=.env.testing.example
WORKTREE_DB_PER_WORKTREE_KEY=TEST_DB_PER_WORKTREE

# Additional env vars to forward to the test container
WORKTREE_EXTRA_ENV_VARS=PENNANT_STORE MAILGUN_WEBHOOK_SIGNING_KEY
```

### `config/worktree-isolation.php`

Laravel config for the PHP `TestDatabaseResolver` class. Publish with:

```bash
php artisan vendor:publish --tag=worktree-isolation-config
```

## Determining Your Docker Image and Network

**Docker image:** Check your `docker-compose.yml` — the image name is typically `sail-{php-version}/app`:

```bash
grep 'image:' docker-compose.yml
```

**Docker network:** By default, Sail creates a network named `{project-directory}_sail`:

```bash
docker network ls | grep sail
```

## AI Agent Integration

Add this to your project's cursor rules or AGENTS.md:

```markdown
**Worktrees:** If the working directory is a git worktree (`.git` is a file, not a directory),
you **must** use `bin/test` instead of `vendor/bin/sail artisan test`. The `bin/test` script
handles per-worktree database isolation and Docker networking.
```

## License

MIT
