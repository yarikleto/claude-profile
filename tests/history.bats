#!/usr/bin/env bats
load test_helper

@test "shows initial commit after fork" {
  run_cli_ok fork default
  run_cli history default
  [ "$status" -eq 0 ]
  [[ "$output" == *"Profile created"* ]]
}

@test "shows save commits" {
  run_cli_ok fork default
  run_cli_ok use default
  echo '{"v2": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Version 2"
  echo '{"v3": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Version 3"

  run_cli history
  [ "$status" -eq 0 ]
  [[ "$output" == *"Version 2"* ]]
  [[ "$output" == *"Version 3"* ]]
  [[ "$output" == *"Profile created"* ]]
}

@test "no git shows warning" {
  run_cli_ok fork default
  rm -rf "$(profile_dir default)/.git"
  run_cli history default
  [ "$status" -eq 0 ]
  [[ "$output" == *"No history"* ]]
}
