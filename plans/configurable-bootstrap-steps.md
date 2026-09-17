# Plan: Configurable bootstrap steps in worktree-setup

## Status

Idea captured for later planning — not started.

## Source

Prompted by comparing this project against [`deskhq/laravel-worktree`](https://packagist.org/packages/deskhq/laravel-worktree)
([GitHub](https://github.com/deskhq/laravel-worktree)), whose `steps` config runs an
arbitrary, user-defined pipeline of bootstrap commands (vendor install, npm build,
migrate, etc.) once per worktree, each idempotent/resumable via sentinel files and
configurable timeouts, executed inside the app container.

We are **not** adopting their sentinel/resume/timeout machinery — that solves interrupted-
bootstrap resumption for a much heavier, containers-always-on setup. The part worth
borrowing is narrower: *let users add steps beyond composer/npm without forking the
stub.*

## Problem

`stubs/bin/worktree-setup` hardcodes exactly two dependency-install steps:

- Step 4: `composer install --no-interaction --no-progress` (per runtime: native /
  docker-compose exec / docker-image run)
- Step 6: `npm install --no-progress` (same three runtime branches)

Any project that needs an additional bootstrap step per worktree — `npm run build`,
`php artisan key:generate`, a one-off migration, warming a cache — has no way to add it
without editing the vendor-published stub directly, which defeats the point of consuming
it via `vendor/bin/worktree-setup` (Composer keeps it in sync automatically; a local edit
would be silently overwritten on `composer update`).

## Reference: how deskhq/laravel-worktree solves it

```php
'steps' => [
    'vendor' => 'composer install --no-interaction',
    'npm' => 'npm ci && npm run build',
    'migrate' => 'php artisan migrate:fresh --seed',
],
```

Each step runs once (sentinel files prevent re-execution), has a configurable
`step_timeout` (default 1800s), can be retried if marked degraded, and runs inside the
app container via Sail. Re-entering an interrupted worktree resumes from the first
incomplete step.

## Proposed approach for this project (v1 scope)

1. Add a `steps` list (name-agnostic, just an ordered list of shell commands) to
   `.worktree-isolation.env` — e.g. a numbered/delimited var like
   `WORKTREE_EXTRA_STEPS` — read by `worktree-setup` the same way `WORKTREE_RUNTIME` and
   the other config keys are already read (`source "$CONF_FILE"`).
2. Run these steps **after** the existing composer/npm steps (i.e. as a new step 7),
   dispatched through the *same* per-runtime branching that composer/npm already use
   (native passthrough / `docker compose exec -T $COMPOSE_SERVICE` / `docker run`) —
   factor that dispatch into a small shared shell function instead of duplicating the
   three-way case statement a third time.
3. Keep v1 intentionally simple to match the current no-idempotency behavior of
   composer/npm install in this script: steps just run in order, every time
   `worktree-setup` runs — no sentinel files, no resume, no per-step timeout. This is
   consistent with how composer/npm install already behave here (they're naturally
   idempotent-ish and just re-run).

## Open question to resolve when picked up

Where the step list should live:

- `.worktree-isolation.env` — simple, plain text, already the single source of truth
  `worktree-setup` reads; consistent with the project's framework-optional design (works
  without Laravel).
- `config/worktree-isolation.php` — richer (arrays, named steps) but only visible to
  Laravel projects, and the script itself deliberately avoids booting the framework.

Leaning `.worktree-isolation.env` for consistency with existing non-Laravel-required
design, but worth confirming before implementing — array-shaped config in a flat `.env`
file needs a delimiter convention (newline-separated? semicolon-separated commands
within one var?) that should be settled up front.

## Files likely touched

- `stubs/bin/worktree-setup` — new step 7, shared runtime-dispatch helper.
- `stubs/bin/worktree-install` — prompt for / write the steps list into
  `.worktree-isolation.env` (or leave commented-out example, matching how
  `WORKTREE_TEST_COMMAND` is already handled).
- `config/worktree-isolation.php` — only if the config-file route is chosen instead.
- `README.md` — document the new config key and give an example.
- `tests/` — coverage for parsing/dispatching the steps list.
