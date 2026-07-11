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

@test "statusline install refuses to run while another holds the lock" {
  # statusline install mutates both the store and live settings.json, so it
  # must take the same exclusive lock as a switch or it can race one.
  run_cli_ok fork default
  mkdir -p "$CLAUDE_PROFILE_HOME/.lock"
  echo "$$" > "$CLAUDE_PROFILE_HOME/.lock/pid"

  run_cli statusline install
  [ "$status" -ne 0 ]
  [[ "$output" == *"in progress"* ]]
}

@test "lock: release only removes a lock this process owns" {
  export PROFILES_DIR="$CLAUDE_PROFILE_HOME"
  mkdir -p "$PROFILES_DIR"
  source "$(dirname "$CLAUDE_PROFILE")/lib/output.sh"
  source "$(dirname "$CLAUDE_PROFILE")/lib/state.sh"

  # A lock owned by another process (token mismatch)
  mkdir -p "$PROFILES_DIR/.lock"
  echo 99999 > "$PROFILES_DIR/.lock/pid"
  echo "someone-elses-token" > "$PROFILES_DIR/.lock/token"

  _LOCK_TOKEN="my-token"
  _release_lock

  # Must not remove a lock we don't own — otherwise a process that lost a
  # takeover race would delete the new owner's lock on EXIT.
  [ -d "$PROFILES_DIR/.lock" ]
  [ "$(cat "$PROFILES_DIR/.lock/token")" = "someone-elses-token" ]
}

@test "lock: release removes a lock whose token matches this process" {
  export PROFILES_DIR="$CLAUDE_PROFILE_HOME"
  mkdir -p "$PROFILES_DIR"
  source "$(dirname "$CLAUDE_PROFILE")/lib/output.sh"
  source "$(dirname "$CLAUDE_PROFILE")/lib/state.sh"

  mkdir -p "$PROFILES_DIR/.lock"
  echo $$ > "$PROFILES_DIR/.lock/pid"
  echo "my-token" > "$PROFILES_DIR/.lock/token"

  _LOCK_TOKEN="my-token"
  _release_lock

  [ ! -d "$PROFILES_DIR/.lock" ]
}

@test "lock: a refused command does not disturb the live lock it failed to take" {
  run_cli_ok fork default
  mkdir -p "$CLAUDE_PROFILE_HOME/.lock"
  echo "$$" > "$CLAUDE_PROFILE_HOME/.lock/pid"
  echo "held-by-live-process" > "$CLAUDE_PROFILE_HOME/.lock/token"

  run_cli save -m x
  [ "$status" -ne 0 ]
  [ -d "$CLAUDE_PROFILE_HOME/.lock" ]
  [ "$(cat "$CLAUDE_PROFILE_HOME/.lock/token")" = "held-by-live-process" ]
}

@test "read-only commands run despite the lock" {
  run_cli_ok fork default
  mkdir -p "$CLAUDE_PROFILE_HOME/.lock"
  echo "$$" > "$CLAUDE_PROFILE_HOME/.lock/pid"

  run_cli list
  [ "$status" -eq 0 ]
  [[ "$output" == *"default"* ]]
}
