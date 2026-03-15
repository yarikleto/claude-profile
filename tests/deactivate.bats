#!/usr/bin/env bats
load test_helper

@test "restores original state" {
  run_cli_ok fork default
  run_cli_ok use default
  echo '{"modified": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok deactivate

  grep -q '"effortLevel"' "$CLAUDE_CODE_HOME/settings.json"
  ! grep -q '"modified"' "$CLAUDE_CODE_HOME/settings.json"
}

@test "auto-saves before restoring" {
  run_cli_ok fork default
  run_cli_ok use default
  echo '{"saved_before_deactivate": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok deactivate

  local dir="$(profile_dir default)"
  grep -q '"saved_before_deactivate"' "$dir/settings.json"
}

@test "clears current marker" {
  run_cli_ok fork default
  run_cli_ok use default
  run_cli_ok deactivate

  [ ! -f "$CLAUDE_CODE_HOME/__profiles__/.current" ]
}

@test "no-op when no profile active" {
  run_cli deactivate
  [ "$status" -eq 0 ]
  [[ "$output" == *"No profile is active"* ]]
}

@test "restores MCP config" {
  run_cli_ok fork default
  run_cli_ok new nomcp
  run_cli_ok use nomcp
  # New profile has minimal seeded .claude.json (no MCP servers)
  [[ "$(cat "$HOME/.claude.json")" == "{}" ]]

  run_cli_ok deactivate
  [ -f "$HOME/.claude.json" ]
  grep -q '"mcpServers"' "$HOME/.claude.json"
}

@test "--keep: keeps current config instead of restoring backup" {
  run_cli_ok fork default
  run_cli_ok use default
  echo '{"custom": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok deactivate --keep

  # Current config should be kept, not restored from backup
  grep -q '"custom"' "$CLAUDE_CODE_HOME/settings.json"
  ! grep -q '"effortLevel"' "$CLAUDE_CODE_HOME/settings.json"
  # Profile marker should be cleared
  [ ! -f "$CLAUDE_CODE_HOME/__profiles__/.current" ]
}

@test "--keep: bulk items are restored to live" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/myproject"
  echo "data" > "$CLAUDE_CODE_HOME/projects/myproject/file.txt"
  run_cli_ok fork default
  run_cli_ok use default
  run_cli_ok deactivate --keep

  # Bulk items should be back in live location
  [ -f "$CLAUDE_CODE_HOME/projects/myproject/file.txt" ]
}

@test "--keep: profile is saved before detaching" {
  run_cli_ok fork default
  run_cli_ok use default
  echo '{"keep_saved": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok deactivate --keep

  # Profile should have the latest state saved
  grep -q '"keep_saved"' "$(profile_dir default)/settings.json"
}
