#!/usr/bin/env bats
load test_helper

@test "empty state shows hint" {
  run_cli list
  [ "$status" -eq 0 ]
  [[ "$output" == *"No profiles yet"* ]]
}

@test "shows created profiles" {
  run_cli_ok fork alpha
  run_cli_ok fork beta
  run_cli list
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"beta"* ]]
}

@test "marks active profile" {
  run_cli_ok fork alpha
  run_cli_ok fork beta
  run_cli_ok use alpha
  run_cli list
  [[ "$output" == *"●"*"alpha"*"(active)"* ]]
  [[ "$output" == *"○"*"beta"* ]]
}
