#!/usr/bin/env bats
load test_helper

@test "creates empty profile and activates it" {
  run_cli_ok new clean

  local dir="$(profile_dir clean)"
  [ -d "$dir" ]
  [ -d "$dir/.git" ]
  [ ! -f "$dir/settings.json" ]
  [ ! -d "$dir/skills" ]
  [[ "$(cat "$CLAUDE_CODE_HOME/profiles/.current")" == "clean" ]]
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
