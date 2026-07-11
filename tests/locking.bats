#!/usr/bin/env bats
load test_helper

@test "mutating command refuses to run while another holds the lock" {
  run_cli_ok fork default
  mkdir -p "$CLAUDE_PROFILE_HOME/.lock"
  echo "$$" > "$CLAUDE_PROFILE_HOME/.lock/pid"

  run_cli save -m x
  [ "$status" -ne 0 ]
  [[ "$output" == *"in progress"* ]]
}

@test "stale lock from a dead process is taken over" {
  run_cli_ok fork default
  local dead_pid
  dead_pid="$(bash -c 'echo $$')"
  mkdir -p "$CLAUDE_PROFILE_HOME/.lock"
  echo "$dead_pid" > "$CLAUDE_PROFILE_HOME/.lock/pid"

  echo '{"after_stale": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli save -m "stale lock"
  [ "$status" -eq 0 ]
  [ ! -d "$CLAUDE_PROFILE_HOME/.lock" ]
}

@test "lock is released after a mutating command finishes" {
  run_cli_ok fork default
  [ ! -d "$CLAUDE_PROFILE_HOME/.lock" ]
  run_cli_ok save -m x
  [ ! -d "$CLAUDE_PROFILE_HOME/.lock" ]
}

@test "read-only commands run despite the lock" {
  run_cli_ok fork default
  mkdir -p "$CLAUDE_PROFILE_HOME/.lock"
  echo "$$" > "$CLAUDE_PROFILE_HOME/.lock/pid"

  run_cli list
  [ "$status" -eq 0 ]
  [[ "$output" == *"default"* ]]
}
