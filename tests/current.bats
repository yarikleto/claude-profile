#!/usr/bin/env bats
load test_helper

@test "returns nothing when no profile active" {
  run_cli current
  [ "$status" -ne 0 ]
  [[ "$output" == *"no active profile"* ]]
}

@test "returns active profile name" {
  run_cli_ok fork default
  run_cli_ok use default
  run_cli current
  [ "$status" -eq 0 ]
  [[ "$output" == "default" ]]
}
