#!/usr/bin/env bash
# Remote installer for claude-profile
# Usage: curl -fsSL https://raw.githubusercontent.com/yarikleto/claude-profile/main/remote-install.sh | bash
set -euo pipefail

REPO="https://github.com/yarikleto/claude-profile.git"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "Installing claude-profile..."
git clone --depth 1 "$REPO" "$TMPDIR/claude-profile" 2>/dev/null
bash "$TMPDIR/claude-profile/install.sh"
