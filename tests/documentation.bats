#!/usr/bin/env bats
load test_helper

@test "docs: explain the official config directory and safe test isolation" {
  local repo_root
  repo_root="$(dirname "$CLAUDE_PROFILE")"

  grep -F '| `CLAUDE_CONFIG_DIR` |' "$repo_root/docs/configuration.md"
  grep -F '$CLAUDE_CONFIG_DIR/.claude.json' "$repo_root/docs/configuration.md"
  grep -F 'unset CLAUDE_CODE_HOME' "$repo_root/docs/configuration.md"
  grep -F 'export CLAUDE_CONFIG_DIR=' "$repo_root/README.md"
  grep -F 'unset CLAUDE_CONFIG_DIR' "$repo_root/CLAUDE.md"
  ! grep -F 'which `claude-profile` does not read' "$repo_root/docs/configuration.md"
}

@test "docs: custom config upgrades preserve the original backup" {
  local repo_root
  repo_root="$(dirname "$CLAUDE_PROFILE")"

  grep -F '### Upgrading with a custom config directory' "$repo_root/docs/configuration.md"
  grep -F 'one stable live directory per profile store' "$repo_root/docs/configuration.md"
  grep -F 'export CLAUDE_PROFILE_HOME="$HOME/.local/share/claude-profile-work"' "$repo_root/README.md"
  grep -F 'fresh `CLAUDE_PROFILE_HOME`' "$repo_root/docs/configuration.md"
}

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
