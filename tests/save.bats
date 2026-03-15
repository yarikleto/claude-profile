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
