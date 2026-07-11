#!/usr/bin/env bash
# Remote installer for claude-profile
# Usage: curl -fsSL https://raw.githubusercontent.com/yarikleto/claude-profile/main/remote-install.sh | bash
set -euo pipefail

# The body runs only from the final line — a truncated download defines an
# incomplete function (syntax error) instead of executing a script prefix.
main() {
  local repo="${CLAUDE_PROFILE_REPO:-https://github.com/yarikleto/claude-profile.git}"
  # Not local — the EXIT trap fires after main returns
  CLONE_DIR="$(mktemp -d)"
  trap 'rm -rf "$CLONE_DIR"' EXIT

  echo "Installing claude-profile..."
  git clone -q --depth 1 "$repo" "$CLONE_DIR/claude-profile"
  bash "$CLONE_DIR/claude-profile/install.sh"
}

main "$@"
