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

@test "ignores gitignored data dirs for a moved-thin active profile" {
  run_cli_ok fork alpha
  run_cli_ok fork beta
  run_cli_ok use alpha

  # Untracked data that the static .gitignore excludes (see GITIGNORE_CONTENT)
  mkdir -p "$CLAUDE_CODE_HOME/projects/big"
  echo "huge" > "$CLAUDE_CODE_HOME/projects/big/data.bin"
  echo "log" > "$CLAUDE_CODE_HOME/history.jsonl"
  # ...plus one real, tracked change
  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"

  run_cli diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"settings.json"* ]]
  [[ "$output" != *"projects"* ]]
  [[ "$output" != *"history.jsonl"* ]]
}

@test "non-active profile reports its own state, not live" {
  run_cli_ok fork alpha
  run_cli_ok fork beta   # beta is now active; alpha is not

  # Mutate the ACTIVE profile's live state
  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"

  # Diffing the NON-active alpha must reflect alpha's own git state,
  # not pick up beta's live changes
  run_cli diff alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"no changes"* ]]
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
