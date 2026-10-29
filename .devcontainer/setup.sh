#!/usr/bin/env bash
# postCreate: install bats and shellcheck (tests/bats, the stubs/ shell scripts)
# and tmux, then install Composer dependencies. Safe to rerun.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# The Claude config volume is created root-owned.
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  sudo chown -R "$(id -u):$(id -g)" "$CLAUDE_CONFIG_DIR"
  # Repo settings can't turn these on, only user settings can: Remote Control
  # at startup and auto permission mode. Merged in, keeping anything already set.
  node -e '
    const fs = require("fs"), f = process.argv[1];
    let s = {};
    try { s = JSON.parse(fs.readFileSync(f, "utf8")); } catch {}
    s.remoteControlAtStartup ??= true;
    s.permissions = { defaultMode: "auto", ...s.permissions };
    fs.writeFileSync(f, JSON.stringify(s, null, 2) + "\n");
  ' "$CLAUDE_CONFIG_DIR/settings.json"
fi

echo "==> GitHub over HTTPS"
# The remote is SSH (the checkout is shared with the host) and there's no key in
# here. In this container's global config only: rewrite GitHub SSH URLs to HTTPS
# and let gh supply GH_TOKEN as the credential. The host's git config is untouched.
if gh auth status >/dev/null 2>&1; then
  gh auth setup-git
  for from in "git@github.com:" "ssh://git@github.com/"; do
    git config --global --get-all url."https://github.com/".insteadOf | grep -qxF "$from" \
      || git config --global --add url."https://github.com/".insteadOf "$from"
  done
  # Commit identity from the token's account, unless one is set (VS Code copies the host's).
  if [ -z "$(git config --global user.email)" ]; then
    gh api user --jq '.name // .login, "\(.id)+\(.login)@users.noreply.github.com"' | {
      read -r name; read -r email
      git config --global user.name "$name"
      git config --global user.email "$email"
    }
  fi
else
  echo "    gh is not logged in (no GH_TOKEN?); git push/pull to GitHub won't work"
fi

echo "==> Packages"
# The image's Yarn apt source has an unavailable signing key, which fails apt-get update.
sudo rm -f /etc/apt/sources.list.d/yarn.list
sudo apt-get update -q
sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends \
  bats shellcheck tmux

echo "==> Composer"
cd "$ROOT"
composer install --no-interaction --no-progress

echo "==> Done. Tests: composer test && composer test:bash"
