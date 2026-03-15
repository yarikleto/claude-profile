#!/usr/bin/env bats
load test_helper

@test "copies profile files into live location" {
  run_cli_ok fork default
  run_cli_ok new clean
  run_cli_ok use clean

  [ ! -f "$CLAUDE_CODE_HOME/settings.json" ]
  [ ! -f "$HOME/.claude.json" ]
}

@test "switches back restores files" {
  run_cli_ok fork default
  run_cli_ok new clean
  run_cli_ok use clean
  run_cli_ok use default

  [ -f "$CLAUDE_CODE_HOME/settings.json" ]
  grep -q '"effortLevel"' "$CLAUDE_CODE_HOME/settings.json"
}

@test "auto-saves current profile before switching" {
  run_cli_ok fork default
  # fork auto-activates default
  echo '{"changed_while_active": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok new other
  # new auto-saves default before activating other

  local dir="$(profile_dir default)"
  grep -q '"changed_while_active"' "$dir/settings.json"
}

@test "sets current profile marker" {
  run_cli_ok fork default
  run_cli_ok use default

  [ -f "$CLAUDE_CODE_HOME/profiles/.current" ]
  [ "$(cat "$CLAUDE_CODE_HOME/profiles/.current")" = "default" ]
}

@test "no-op when already active" {
  run_cli_ok fork default
  run_cli_ok use default
  run_cli use default
  [ "$status" -eq 0 ]
  [[ "$output" == *"already active"* ]]
}

@test "fails on nonexistent profile" {
  run_cli use nonexistent
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "MCP config switches correctly" {
  run_cli_ok fork default
  run_cli_ok new nomcp
  run_cli_ok use nomcp
  [ ! -f "$HOME/.claude.json" ]

  run_cli_ok use default
  [ -f "$HOME/.claude.json" ]
  grep -q '"mcpServers"' "$HOME/.claude.json"
}
