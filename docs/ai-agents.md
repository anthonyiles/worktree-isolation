# Working in Git Worktrees (for AI Agents)

This project uses `anthonyiles/worktree-isolation`. Each git worktree gets its own
Composer and npm dependencies, its own `.env` / `.env.testing`, and its own test and
development databases. That isolation only holds if commands run through
`vendor/bin/worktree`.

## Am I in a worktree?

```bash
test -f .git && echo worktree || echo main checkout
```

In a worktree `.git` is a file pointing at the main repository. In the main checkout
it is a directory, and commands run as usual there. `vendor/bin/worktree` refuses to
pass commands through from the main checkout.

## The rule

Inside a worktree, prefix every project command with `vendor/bin/worktree`:

| Instead of | Run |
| --- | --- |
| `php artisan test`, `sail test`, `vendor/bin/phpunit` | `vendor/bin/worktree test` |
| `php artisan test --filter=UserTest` | `vendor/bin/worktree test --filter=UserTest` |
| `composer install`, `sail composer require foo/bar` | `vendor/bin/worktree composer install`, `vendor/bin/worktree composer require foo/bar` |
| `npm run build`, `sail npm run dev` | `vendor/bin/worktree npm run build`, `vendor/bin/worktree npm run dev` |
| `php artisan migrate`, `sail artisan tinker` | `vendor/bin/worktree php artisan migrate`, `vendor/bin/worktree php artisan tinker` |
| `docker compose exec app ...` | `vendor/bin/worktree ...` |

Git commands, file edits and read-only tools (`grep`, `ls`) need no prefix.

## Why

With Docker Compose or Sail, `sail` and `docker compose exec` target whichever
container is already running, which is often bind-mounted to the main checkout or a
different worktree. The command then reads that checkout's code and `.env.testing`
and migrates or wipes its database. `vendor/bin/worktree` resolves the runtime
(native, Docker Compose, Sail/standalone image) for the current worktree every time.

## Creating a worktree

```bash
git worktree add ../worktrees/<project>/<branch> -b <branch>
```

A post-checkout hook bootstraps the new worktree automatically: dependencies, env
files and per-worktree databases. Don't copy `.env` files or run `composer install`
yourself.

## When something looks wrong

- **`vendor/` is missing in the worktree**: the bootstrap didn't run or failed. From
  the worktree, run the main checkout's copy:
  `"$(git rev-parse --path-format=absolute --git-common-dir)/../vendor/bin/worktree" setup`
- **Tests hit the wrong database, or env files are missing**: run
  `vendor/bin/worktree setup` again. It is safe to repeat.
- **`Error: this is the main checkout`**: you are not in a worktree, so run the
  command without the prefix.

Don't edit `.worktree-isolation.env` or the database names in `.env` /
`.env.testing` to work around a failure. Report the error instead.
