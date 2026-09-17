# Plan: Derived Docker Compose project/port isolation per worktree

## Status

Implemented (2026-09-16). The three open questions below were resolved:
`WORKTREE_COMPOSE_PROJECT_BASE` auto-derives from the main repo's dirname at install
time; bats coverage (`tests/bats/`) was added alongside the bash changes rather than
deferred; teardown of per-worktree stacks stayed out of scope as a follow-up.

## Source

Prompted by comparing this project against [`deskhq/laravel-worktree`](https://packagist.org/packages/deskhq/laravel-worktree)
([GitHub](https://github.com/deskhq/laravel-worktree)), which manages the full worktree
lifecycle (create/list/start/stop/remove, PR checkout) via a machine-global registry
(`~/.laravel-worktree/registry.json`) that allocates each worktree a slot of host ports
and a unique `COMPOSE_PROJECT_NAME`, guarded by mkdir-based locks.

We are **not** adopting their registry/lock/slot-allocator machinery — that solves a
bigger problem (orchestrating worktree creation itself) than this project takes on. The
part worth borrowing is narrower: *derive an isolated Compose identity from the worktree,
the same way we already derive an isolated database name.*

## Problem

`config/worktree-isolation.php` + `stubs/bin/worktree-setup` support three runtimes —
`native`, `docker-compose`, `docker-image` — but only `docker-compose`/`docker-image`
touch Docker at all, and neither isolates the Docker Compose **project name** or **host
ports** per worktree. If a project's `docker-compose.yml` has fixed `COMPOSE_PROJECT_NAME`
(or none, which Compose defaults to the directory name — often the same across worktrees
of the same repo) and fixed host port bindings, two worktrees running the same compose
file concurrently will collide on container names, networks, volumes, and ports.

Today the `docker-compose` runtime assumes a single already-running stack that
`worktree-setup` execs into (`docker compose exec -T $COMPOSE_SERVICE composer install`)
— it doesn't start or manage the stack itself, so this gap is currently the user's
problem to solve by hand.

## Gap identified during review: this isn't just a naming collision

The problem statement above undersells the issue. Docker bind mounts
(`volumes: - .:/var/www/html` in `docker-compose.yml`) are resolved once, at `docker
compose up` time, to whatever host directory the stack was started from — a running
container can't be repointed at a different directory via `docker compose exec`. Since
`worktree-setup` and `test` today only ever `exec` into a stack someone else already
brought up (`stubs/bin/worktree-setup` steps 4/6, `stubs/bin/test` step 4), two
worktrees sharing one running stack don't just collide on names — worktree B's
`composer install`/tests would silently run against worktree A's mounted files
(whichever directory the stack happens to be bound to), not worktree B's own checkout.
That's worse than a naming collision: it doesn't even error.

This means `COMPOSE_PROJECT_NAME` derivation alone (the original proposal below)
doesn't deliver real isolation unless `worktree-setup` also starts its **own** stack
per worktree (`docker compose up -d`) instead of assuming one is already running. The
project-name derivation and the "bring up your own stack" change are both required —
one without the other still leaves either a volume collision (no own stack) or a
container/network/port collision (own stack, same project name). See the
Implementation Plan below.

## Reference: how deskhq/laravel-worktree solves it

- Slot-based port allocation: `port = port_base + (slot * port_stride) + port_index`,
  bind-probing all ports in a block before claiming a slot.
- Every worktree gets `COMPOSE_PROJECT_NAME=wt-<repo-slug>-<slug>`; Docker's
  `com.docker.compose.project` label then scopes containers/networks/volumes
  automatically.
- Machine-global JSON registry tracks slot → repo → ports across every clone on the
  machine, protected by a short-lived registry lock (claim only) and a longer per-worktree
  lock (whole operation), both `mkdir`-based with stale-lock detection via PID/hostname/
  start-time in `owner.json`.

## Proposed approach for this project (v1 scope)

Reuse the existing derivation pattern from `src/TestDatabaseResolver.php` (which derives
a database name from `strtolower(preg_replace('/[^a-z0-9]+/', '-', $worktreeBasename))`)
rather than building a global registry:

1. Derive `COMPOSE_PROJECT_NAME` as `<repo-slug>-<worktree-basename>` (or similar) using
   the same sanitization logic already proven in `TestDatabaseResolver::derive()`. No
   machine-global state, no locks — the worktree basename is already locally unique per
   clone, same assumption the DB resolver relies on.
2. Write it into `.env` (or `.worktree-isolation.env`) during `worktree-setup`, alongside
   the existing `.env` copy step (step 3 in the script) — `docker compose` reads
   `COMPOSE_PROJECT_NAME` from the environment automatically, so no change to the user's
   `docker-compose.yml` is required.
3. Document in the README that users whose compose files use fixed host port bindings
   still need to parameterize those themselves (e.g. `${APP_PORT:-8080}:80`) — this
   project would only be responsible for the project-name half of isolation in v1.

## Open question to resolve when picked up

Whether to also offer a derived host-port offset (interpolated into `.env` as e.g.
`DERIVED_PORT_OFFSET`) for projects whose compose files want to parameterize ports, or
keep v1 scoped to `COMPOSE_PROJECT_NAME` only and let users handle ports themselves. Port
offsets pull in the bind-probing complexity that makes the deskhq registry heavyweight —
worth deciding whether that complexity is justified before committing to it.

## Implementation Plan (against `main`@6d1d9c4)

### Decisions

1. **`worktree-setup` brings up its own stack.** Add a new step before the existing
   "Install Composer dependencies" step (step 4) in `stubs/bin/worktree-setup`, for the
   `docker-compose` runtime only:
   ```bash
   docker compose -p "$COMPOSE_PROJECT_NAME" $COMPOSE_FILE_OPT up -d
   ```
   This replaces the current assumption that a stack is already running. `native` and
   `docker-image` are unaffected — `docker-image` already creates/destroys ephemeral
   containers per invocation via `docker run --rm`.

2. **Derive `COMPOSE_PROJECT_NAME` in bash, not PHP.** `TestDatabaseResolver::derive()`
   can lean on PHP because DB-name derivation happens *after* `composer install`
   (`vendor/autoload.php` exists by then, per step 5 of `worktree-setup`). The compose
   project name is needed *before* `composer install` can even run (the container has
   to exist first) — on a first-ever worktree setup there's no autoloader to require
   yet. Port the same sanitization (`lowercase`, `[^a-z0-9]+` → `-`, trim `-`) as a bash
   snippet:
   ```bash
   derive_compose_project_name() {
       local base="$1" wt="$2"
       local suffix
       suffix="$(echo "$wt" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
       echo "${base}-${suffix:-worktree}"
   }
   ```
   `base` = a new `WORKTREE_COMPOSE_PROJECT_BASE` config key (see Open Questions for its
   default).

3. **Pass the project name via `-p`, not `.env`.** Every `docker compose` invocation
   (`up`, `exec`, and any future `down`) takes an explicit `-p "$COMPOSE_PROJECT_NAME"`
   flag, the same way `$COMPOSE_FILE_OPT` is already threaded through as a flag rather
   than an env var. This reverses the original proposal above (writing
   `COMPOSE_PROJECT_NAME` into `.env`) — a flag can't be silently overridden by
   something else writing to `.env` later in the script, and doesn't risk clobbering a
   project name the user already set for unrelated reasons.

4. **Shared bash logic goes in a new sourced lib.** The same
   `derive_compose_project_name` function is now needed in `stubs/bin/worktree-setup`
   and `stubs/bin/test` (and `stubs/bin/worktree-clean`, if teardown lands — see Open
   Questions). Add `stubs/bin/_worktree-lib.sh`, sourced near the top of each script
   (right after loading `.worktree-isolation.env`), holding
   `derive_compose_project_name` initially. This also gives the
   `configurable-bootstrap-steps` plan's "factor dispatch into a shared helper" a place
   to land later instead of a fourth copy-pasted case statement.

### Steps

1. `config/worktree-isolation.php` + `stubs/bin/worktree-install`'s `createEnvConfig()`:
   add `WORKTREE_COMPOSE_PROJECT_BASE`, written only for the `docker-compose` runtime,
   documented alongside the existing `WORKTREE_COMPOSE_SERVICE` / `WORKTREE_COMPOSE_FILE`
   keys.
2. `stubs/bin/_worktree-lib.sh` (new): `derive_compose_project_name()`.
3. `stubs/bin/worktree-setup`: source the lib; compute
   `COMPOSE_PROJECT_NAME="$(derive_compose_project_name "$COMPOSE_PROJECT_BASE" "$WORKTREE_BASENAME")"`
   (worktree basename is already resolved by step 5, needs hoisting earlier); insert the
   `docker compose -p "$COMPOSE_PROJECT_NAME" ... up -d` call as a new step before the
   existing composer-install step; add `-p "$COMPOSE_PROJECT_NAME"` to the two existing
   `docker compose exec` calls (composer install, npm install) and the DB-derivation
   `docker compose exec` call.
4. `stubs/bin/test`: same lib source + derivation; add `-p "$COMPOSE_PROJECT_NAME"` to
   both existing `docker compose exec` call sites (with and without per-worktree DB).
   `test` does **not** run `up` itself — it assumes `worktree-setup` already brought the
   stack up; if the stack isn't running, `docker compose exec` fails with Docker's
   normal "service is not running" error, matching today's behavior for a stack that
   was never started.
5. `README.md`: rewrite the "Docker Compose" section — `worktree-setup` now owns
   bringing the stack up, so `docker compose up -d` before `git worktree add` is no
   longer a prerequisite the user has to do by hand; document
   `WORKTREE_COMPOSE_PROJECT_BASE`; add the port-collision caveat.
6. `tests/` — no PHPUnit coverage applies (no PHP code added by this change); see Open
   Questions re: bash test coverage.

### Explicit non-goals for this pass

- Host port derivation/offsetting — still out of scope; document that fixed host port
  bindings remain the user's problem (per the original "Open question" above).
- Automatic teardown of per-worktree stacks on `git worktree remove` — see Open
  Questions below; Git has no built-in hook event for worktree removal today (only
  `post-checkout` is used elsewhere in this package), so this isn't a small addition.

### Open questions to resolve before implementing

- **`WORKTREE_COMPOSE_PROJECT_BASE` default** — derive automatically from the main
  repo's directory basename (consistent with `DB_DATABASE` defaulting to `testing`, no
  user input required), or require the user to set it explicitly at install time (safer
  — avoids accidentally deriving a name that collides with an unrelated project on the
  same Docker host)?
- **Teardown mechanism** — `worktree-clean` today only drops databases, queried by
  `LIKE '{base}-%'` in MySQL (`stubs/bin/worktree-clean`). There's no equivalent "list
  compose projects by name prefix and offer to tear them down" today; `docker compose ls
  --filter name=<prefix>` could work, but touching `worktree-clean` to add this is a
  second, separable change. Recommend shipping stack-creation first (this plan) and
  scoping teardown as a follow-up once the creation side is validated in practice.
- **Bash test coverage** — none of the four stub scripts have automated coverage today
  (existing gap, independent of this feature). Worth deciding whether to introduce a
  bash test tool (e.g. bats) as part of this change, or continue relying on manual
  verification.

## Files likely touched

- `stubs/bin/_worktree-lib.sh` — new, shared `derive_compose_project_name()`.
- `stubs/bin/worktree-setup` — source the lib, bring up the stack, pass `-p` on every
  `docker compose` call.
- `stubs/bin/test` — source the lib, pass `-p` on every `docker compose` call.
- `stubs/bin/worktree-install` — write `WORKTREE_COMPOSE_PROJECT_BASE` into
  `.worktree-isolation.env` for the `docker-compose` runtime.
- `config/worktree-isolation.php` — new `compose_project_base` key.
- `README.md` — document the new behavior and its scope limits (no port isolation, no
  automatic teardown in this pass).
- `src/TestDatabaseResolver.php` — not touched by this plan (derivation stays in bash;
  see Decision 2 above for why the existing PHP resolver pattern doesn't apply here).
