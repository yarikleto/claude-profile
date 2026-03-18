#!/usr/bin/env bats
load test_helper

@test "creates empty profile and activates it" {
  run_cli_ok new clean

  local dir="$(profile_dir clean)"
  [ -d "$dir" ]
  [ -d "$dir/.git" ]
  # Seeded with minimal config so Claude Code doesn't complain
  [ -f "$dir/settings.json" ]
  [ ! -d "$dir/skills" ]
  [[ "$(cat "$CLAUDE_PROFILE_HOME/.current")" == "clean" ]]
}

@test "rejects duplicate name" {
  run_cli_ok new test1
  run_cli new test1
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "requires a name" {
  run_cli new
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "uses custom .seed/ directory when present" {
  mkdir -p "$CLAUDE_PROFILE_HOME/.seed"
  echo '{"custom": true}' > "$CLAUDE_PROFILE_HOME/.seed/settings.json"
  echo '{"mcpServers": {"default": {}}}' > "$CLAUDE_PROFILE_HOME/.seed/.claude.json"

  run_cli_ok new seeded

  local dir="$(profile_dir seeded)"
  grep -q '"custom"' "$dir/settings.json"
  grep -q '"default"' "$dir/.claude.json"
}

@test "custom .seed/ overrides built-in defaults" {
  mkdir -p "$CLAUDE_PROFILE_HOME/.seed"
  echo '{"only": "this"}' > "$CLAUDE_PROFILE_HOME/.seed/settings.json"
  # No .claude.json in seed — should not be created

  run_cli_ok new custom

  local dir="$(profile_dir custom)"
  [[ "$(cat "$dir/settings.json")" == '{"only": "this"}' ]]
  [ ! -f "$dir/.claude.json" ]
}
