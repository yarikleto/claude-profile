#!/usr/bin/env bats
load test_helper

@test "displays profile contents" {
  run_cli_ok fork default
  run_cli show default
  [ "$status" -eq 0 ]
  [[ "$output" == *"settings.json"* ]]
  [[ "$output" == *".claude.json"* ]]
}

@test "shows active live contents after profile directory is moved thin" {
  run_cli_ok fork alpha
  run_cli_ok fork beta
  run_cli_ok use alpha

  run_cli show alpha
  [[ "$status" -eq 0 \
    && "$output" == *"alpha"* \
    && "$output" == *"settings.json"* \
    && "$output" == *"skills"* \
    && "$output" == *".claude.json"* ]]
}

@test "fails on nonexistent" {
  run_cli show nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
