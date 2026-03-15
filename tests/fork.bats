#!/usr/bin/env bats
load test_helper

@test "copies current state" {
  run_cli_ok fork default

  local dir="$(profile_dir default)"
  [ -f "$dir/settings.json" ]
  [ -d "$dir/skills/my-skill" ]
  [ -f "$dir/.claude.json" ]
  [ -d "$dir/.git" ]
}

@test "settings content matches original" {
  run_cli_ok fork default

  local dir="$(profile_dir default)"
  grep -q '"effortLevel"' "$dir/settings.json"
  grep -q '"mcpServers"' "$dir/.claude.json"
}

@test "creates original backup" {
  run_cli_ok fork default

  local backup="$(backup_dir)"
  [ -d "$backup" ]
  [ -f "$backup/settings.json" ]
  [ -f "$backup/.claude.json" ]
}

@test "backup happens only once" {
  run_cli_ok fork first
  echo '{"modified": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok fork second

  local backup="$(backup_dir)"
  grep -q '"effortLevel"' "$backup/settings.json"
  ! grep -q '"modified"' "$backup/settings.json"
}

@test "from active profile copies active state" {
  run_cli_ok fork default
  # fork auto-activates, so default is already active
  echo '{"active_change": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok fork forked

  local dir="$(profile_dir forked)"
  grep -q '"active_change"' "$dir/settings.json"
}

@test "rejects duplicate name" {
  run_cli_ok fork default
  run_cli fork default
  [ "$status" -ne 0 ]
}
