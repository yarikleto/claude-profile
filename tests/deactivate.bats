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

  [ ! -f "$CLAUDE_CODE_HOME/profiles/.current" ]
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
  [ ! -f "$HOME/.claude.json" ]

  run_cli_ok deactivate
  [ -f "$HOME/.claude.json" ]
  grep -q '"mcpServers"' "$HOME/.claude.json"
}
