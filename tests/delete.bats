#!/usr/bin/env bats
load test_helper

@test "removes profile directory" {
  run_cli_ok fork to-delete
  # fork auto-activates, so switch away first
  run_cli_ok fork other
  run_cli_ok delete to-delete -f

  [ ! -d "$(profile_dir to-delete)" ]
}

@test "refuses to delete active profile" {
  run_cli_ok fork active
  run_cli_ok use active
  run_cli delete active -f
  [ "$status" -ne 0 ]
  [[ "$output" == *"Cannot delete the active"* ]]
}

@test "fails on nonexistent" {
  run_cli delete nope -f
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
