#!/usr/bin/env bats
load test_helper

@test "commits changes to profile git history" {
  run_cli_ok fork default
  run_cli_ok use default
  echo '{"v2": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Updated settings"

  local dir="$(profile_dir default)"
  local log
  log="$(git -C "$dir" log --oneline)"
  [[ "$log" == *"Updated settings"* ]]
}

@test "with explicit name" {
  run_cli_ok fork default
  run_cli_ok use default
  echo '{"explicit": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save default -m "Explicit save"

  local dir="$(profile_dir default)"
  local log
  log="$(git -C "$dir" log --oneline)"
  [[ "$log" == *"Explicit save"* ]]
}

@test "save as first command creates backup so deactivate works" {
  run_cli_ok save myprofile -m "First save"
  [ -d "$(backup_dir)" ]
  [ -f "$(backup_dir)/settings.json" ]

  run_cli_ok use myprofile
  echo '{"modified": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok deactivate

  grep -q '"effortLevel"' "$CLAUDE_CODE_HOME/settings.json"
  ! grep -q '"modified"' "$CLAUDE_CODE_HOME/settings.json"
}

@test "no-op when nothing changed" {
  run_cli_ok fork default
  run_cli_ok use default
  run_cli_ok save -m "No changes"

  local dir="$(profile_dir default)"
  local count
  count="$(git -C "$dir" log --oneline | wc -l | tr -d ' ')"
  # Only initial commit — "No changes" was skipped
  [ "$count" -eq 1 ]
}
