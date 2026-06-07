#!/usr/bin/env bash
# One-time developer setup: activate the version-controlled git hooks in hooks/.
#
#     ./scripts/setup-hooks.sh
#
# This points git at the tracked hooks directory so pre-push runs the bats suite.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

git config core.hooksPath hooks
chmod +x hooks/* 2>/dev/null || true

echo "✓ Git hooks activated (core.hooksPath=hooks)."
echo "  pre-push will now run 'bats tests/' and block pushes on failure."
echo "  Bypass in an emergency with: git push --no-verify"
