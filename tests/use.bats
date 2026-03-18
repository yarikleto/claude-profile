#!/usr/bin/env bats
load test_helper

@test "copies profile files into live location" {
  run_cli_ok fork default
  run_cli_ok new clean
  run_cli_ok use clean

  # New profile has minimal seeded config
  [ -f "$CLAUDE_CODE_HOME/settings.json" ]
  [ -f "$HOME/.claude.json" ]
  [[ "$(cat "$HOME/.claude.json")" == "{}" ]]
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

  [ -f "$CLAUDE_PROFILE_HOME/.current" ]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.current")" = "default" ]
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

@test "use: clears .claude.json when target profile has none" {
  run_cli_ok fork with-mcp
  run_cli_ok new no-mcp
  # Switch away so auto-save of no-mcp is done
  run_cli_ok use with-mcp
  [ -f "$HOME/.claude.json" ]

  # Remove .claude.json from no-mcp AFTER auto-save has run
  rm -f "$(profile_dir no-mcp)/.claude.json"

  run_cli_ok use no-mcp
  # .claude.json should be gone since no-mcp profile doesn't have it
  [ ! -f "$HOME/.claude.json" ]
}

@test "MCP config switches correctly" {
  run_cli_ok fork default
  run_cli_ok new nomcp
  run_cli_ok use nomcp
  # New profile has minimal seeded .claude.json (no MCP servers)
  [[ "$(cat "$HOME/.claude.json")" == "{}" ]]

  run_cli_ok use default
  [ -f "$HOME/.claude.json" ]
  grep -q '"mcpServers"' "$HOME/.claude.json"
}
