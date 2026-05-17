#!/usr/bin/env bash
# bb_workspace devcontainer onCreateCommand.
#
# Installs asdf plugins from .tool-versions, then bootstraps Hex/Rebar so that
# every cloned bb_* repo can run `mix` immediately.

set -euo pipefail

ASDF_DIR="${ASDF_DIR:-$HOME/.asdf}"
PATH="$ASDF_DIR/bin:${ASDF_DATA_DIR:-$ASDF_DIR}/shims:$PATH"

if [[ ! -e .tool-versions ]]; then
  echo "No .tool-versions file in workspace root; skipping asdf bootstrap."
else
  REQUIRED_PLUGINS=$(awk '{print $1}' .tool-versions)
  INSTALLED_PLUGINS=$(asdf plugin list 2>/dev/null || echo "")

  echo "==> Installing/updating asdf plugins"
  for plugin in $REQUIRED_PLUGINS; do
    if echo "$INSTALLED_PLUGINS" | grep -qx "$plugin"; then
      asdf plugin update "$plugin" || true
    else
      asdf plugin add "$plugin"
    fi
  done

  echo "==> Installing tools from .tool-versions"
  asdf install

  echo "==> Configuring Hex and Rebar"
  mix local.hex --force
  mix local.rebar --force
fi

# Make asdf shims and the workspace bin/ dir available in plain bash/zsh
# sessions (devcontainer remoteEnv.PATH handles VS Code terminals; this covers
# raw `docker exec`/`ssh` sessions too).
WORKSPACE_BIN="/workspaces/bb_workspace/bin"
ASDF_LINE="export PATH=\"$WORKSPACE_BIN:$ASDF_DIR/shims:$ASDF_DIR/bin:\$PATH\""
# .profile is sourced by login shells (ssh, docker exec -l) unconditionally.
# .bashrc/.zshrc are sourced by interactive shells (VS Code terminals).
# .bashrc returns early when non-interactive, so .profile is needed for the
# non-interactive case to work.
for rc in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ -f "$rc" ]] || continue
  grep -qxF "$ASDF_LINE" "$rc" || printf '\n# bb_workspace devcontainer\n%s\n' "$ASDF_LINE" >> "$rc"
done

echo "==> Done. Run 'bb-sync' to clone the beam-bots ecosystem."
