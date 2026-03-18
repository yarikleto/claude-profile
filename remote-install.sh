#!/usr/bin/env bash
# Remote installer for claude-profile
# Usage: curl -fsSL https://raw.githubusercontent.com/yarikleto/claude-profile/main/remote-install.sh | bash
set -euo pipefail

REPO="https://github.com/yarikleto/claude-profile.git"
CLONE_DIR="$(mktemp -d)"
trap 'rm -rf "$CLONE_DIR"' EXIT

echo "Installing claude-profile..."
git clone --depth 1 "$REPO" "$CLONE_DIR/claude-profile" 2>/dev/null
bash "$CLONE_DIR/claude-profile/install.sh"
