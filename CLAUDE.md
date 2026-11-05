# worktree-isolation

- Keep logic in bash (`stubs/bin/`). Use PHP only where it's unavoidable, which today means talking to the database
  server through PDO. Even then, keep it to a short inline snippet run inside the runtime (like `ENSURE_DB_PHP`),
  with names and credentials already worked out by bash and passed in the environment. Never require PHP on the host.
- The scripts must run on macOS's Bash 3.2 and pass `shellcheck -x`.
- Tests: `bats tests/bats`.
