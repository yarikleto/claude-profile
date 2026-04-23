#!/usr/bin/env bats
load test_helper

# Tests for hardening against a corrupted .current file.
# If an attacker (or filesystem corruption) plants a path-traversal value
# like "../../evil" into $PROFILES_DIR/.current, commands that use the value
# in path construction must detect it and exit with a clear error rather than
# writing files outside $PROFILES_DIR.

_plant_corrupt_current() {
  mkdir -p "$CLAUDE_PROFILE_HOME"
  echo "../../evil" > "$CLAUDE_PROFILE_HOME/.current"
}

@test "use: corrupt .current triggers clear error, not traversal" {
  run_cli_ok fork target
  _plant_corrupt_current

  run_cli use target
  [ "$status" -ne 0 ]
  [[ "$output" == *"corrupt"* ]] || [[ "$output" == *"invalid"* ]]

  # Nothing written outside PROFILES_DIR
  [ ! -d "$HOME/evil" ]
  [ ! -d "$BATS_TEST_TMPDIR/evil" ]
}

@test "new: corrupt .current triggers clear error, not traversal" {
  _plant_corrupt_current

  run_cli new legitprofile
  [ "$status" -ne 0 ]
  [[ "$output" == *"corrupt"* ]] || [[ "$output" == *"invalid"* ]]

  [ ! -d "$HOME/evil" ]
}

@test "fork: corrupt .current triggers clear error, not traversal" {
  _plant_corrupt_current

  run_cli fork legitprofile
  [ "$status" -ne 0 ]
  [[ "$output" == *"corrupt"* ]] || [[ "$output" == *"invalid"* ]]

  [ ! -d "$HOME/evil" ]
}

@test "deactivate: corrupt .current triggers clear error, not traversal" {
  # Create a backup so deactivate reaches the path-construction code
  mkdir -p "$CLAUDE_PROFILE_HOME/.pre-profiles-backup"
  _plant_corrupt_current

  run_cli deactivate
  [ "$status" -ne 0 ]
  [[ "$output" == *"corrupt"* ]] || [[ "$output" == *"invalid"* ]]

  [ ! -d "$HOME/evil" ]
}

@test "save: corrupt .current triggers clear error when defaulting to current" {
  _plant_corrupt_current

  run_cli save -m "should fail"
  [ "$status" -ne 0 ]
  [[ "$output" == *"corrupt"* ]] || [[ "$output" == *"invalid"* ]]

  [ ! -d "$HOME/evil" ]
}

@test "corrupt .current error message points to recovery" {
  # Create a real profile so use reaches the get_current_validated call
  mkdir -p "$CLAUDE_PROFILE_HOME/target"
  _plant_corrupt_current

  run_cli use target
  [ "$status" -ne 0 ]
  [[ "$output" == *"claude-profile list"* ]] || [[ "$output" == *"claude-profile use"* ]]
}
