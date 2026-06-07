#!/usr/bin/env bats
load test_helper

@test "no changes when profile matches live" {
  run_cli_ok fork default
  run_cli_ok use default
  run_cli diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"no changes"* ]]
}

@test "no changes after switching into a moved-thin active profile" {
  run_cli_ok fork alpha
  run_cli_ok fork beta
  run_cli_ok use alpha

  run_cli diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"no changes"* ]]
}

@test "detects unsaved changes" {
  run_cli_ok fork default
  run_cli_ok use default
  echo '{"unsaved": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"settings.json"* ]]
}

@test "detects deleted files after switching into a moved-thin active profile" {
  run_cli_ok fork alpha
  run_cli_ok fork beta
  run_cli_ok use alpha

  rm "$CLAUDE_CODE_HOME/settings.json"

  run_cli diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"settings.json"* ]]
}

@test "with commit ref shows git diff" {
  run_cli_ok fork default
  run_cli_ok use default

  local dir="$(profile_dir default)"
  local initial
  initial="$(git -C "$dir" log --format='%H' -1)"

  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Changed"

  run_cli diff default "$initial"
  [ "$status" -eq 0 ]
  [[ "$output" == *"settings.json"* ]]
}
