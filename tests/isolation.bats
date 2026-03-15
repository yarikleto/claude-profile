#!/usr/bin/env bats
# Tests that verify profile isolation — changes in one profile
# never leak to another or to the original backup.

load test_helper

@test "isolation: changing active profile doesn't affect other profiles" {
  run_cli_ok fork alpha
  run_cli_ok fork beta
  run_cli_ok use alpha

  # Modify alpha's working state
  echo '{"alpha_only": true}' > "$CLAUDE_CODE_HOME/settings.json"

  # Switch to beta — alpha should be saved, beta loaded
  run_cli_ok use beta

  # Beta should have the original settings, NOT alpha's change
  grep -q '"effortLevel"' "$CLAUDE_CODE_HOME/settings.json"
  ! grep -q '"alpha_only"' "$CLAUDE_CODE_HOME/settings.json"

  # Alpha's profile dir should have its change
  grep -q '"alpha_only"' "$(profile_dir alpha)/settings.json"
}

@test "isolation: original backup never changes" {
  run_cli_ok fork default
  run_cli_ok use default

  local backup="$(backup_dir)"
  local original_md5
  original_md5="$(cat "$backup/settings.json" | md5sum)"

  # Make multiple changes and saves
  echo '{"v1": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "v1"
  echo '{"v2": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "v2"

  # Backup must be unchanged
  local current_md5
  current_md5="$(cat "$backup/settings.json" | md5sum)"
  [ "$original_md5" = "$current_md5" ]
}

@test "isolation: new profile is truly empty" {
  run_cli_ok new empty
  run_cli_ok use empty

  # Nothing should exist
  [ ! -f "$CLAUDE_CODE_HOME/settings.json" ]
  [ ! -f "$CLAUDE_CODE_HOME/CLAUDE.md" ]
  [ ! -d "$CLAUDE_CODE_HOME/agents" ]
  [ ! -d "$CLAUDE_CODE_HOME/skills" ]
  [ ! -d "$CLAUDE_CODE_HOME/rules" ]
  [ ! -f "$CLAUDE_CODE_HOME/keybindings.json" ]
  [ ! -f "$HOME/.claude.json" ]
}

@test "isolation: deactivate fully restores after multiple switches" {
  run_cli_ok fork alpha
  run_cli_ok new beta

  # Switch around, modifying state each time
  run_cli_ok use alpha
  echo '{"alpha": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok use beta
  echo '{"beta": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok use alpha
  run_cli_ok deactivate

  # Original state should be back
  grep -q '"effortLevel"' "$CLAUDE_CODE_HOME/settings.json"
  ! grep -q '"alpha"' "$CLAUDE_CODE_HOME/settings.json"
  ! grep -q '"beta"' "$CLAUDE_CODE_HOME/settings.json"
}

@test "isolation: MCP config is per-profile" {
  run_cli_ok fork with-mcp
  run_cli_ok new without-mcp
  run_cli_ok use with-mcp

  # Modify MCP in with-mcp
  echo '{"mcpServers": {"custom": {}}}' > "$HOME/.claude.json"
  run_cli_ok save -m "Custom MCP"

  # Switch to without-mcp
  run_cli_ok use without-mcp
  [ ! -f "$HOME/.claude.json" ]

  # Switch back
  run_cli_ok use with-mcp
  grep -q '"custom"' "$HOME/.claude.json"
}

@test "isolation: tests don't touch real home directory" {
  # HOME should be inside BATS temp dir
  [[ "$HOME" == *"bats"* ]] || [[ "$HOME" == */tmp/* ]]
  [[ "$CLAUDE_CODE_HOME" == *"bats"* ]] || [[ "$CLAUDE_CODE_HOME" == */tmp/* ]]
}
