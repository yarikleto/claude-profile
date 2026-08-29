#!/usr/bin/env bats
load test_helper

@test "docs: home-file recovery matches the current store format" {
  local repo_root stored_name
  repo_root="$(dirname "$CLAUDE_PROFILE")"
  stored_name="$(sed -n 's/^CLAUDE_HOME_JSON="\([^"]*\)"/\1/p' "$repo_root/lib/config.sh")"

  [ -n "$stored_name" ]
  grep -F "YOUR_PROFILE/$stored_name ~/.claude.json" "$repo_root/docs/migration.md"
  grep -F "$stored_name" "$repo_root/docs/configuration.md" \
    | grep -F 'stored copy of ~/.claude.json'
  grep -F "$stored_name" "$repo_root/docs/configuration.md" \
    | grep -F '**Git-tracked**'
  [ "$(grep -F "$stored_name" "$repo_root/docs/architecture.md" \
    | grep -Fc 'stored copy of ~/.claude.json')" -eq 2 ]
  grep -F '.claude.json                        # template for ~/.claude.json' \
    "$repo_root/docs/architecture.md"
  grep -F "$stored_name" "$repo_root/docs/uninstall.md"
  grep -F 'rm -f ~/.claude.json' "$repo_root/docs/uninstall.md"

  ! grep -F "YOUR_PROFILE/.claude.json ~/.claude.json" "$repo_root/docs/migration.md"
  ! grep -F 'stored as `.claude.json` inside each profile directory' "$repo_root/docs/architecture.md"
  ! grep -E '^[[:space:]]*mv -f ~/\.claude/\.claude\.json ~/\.claude\.json' "$repo_root/docs/uninstall.md"
}
