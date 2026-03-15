#!/usr/bin/env bats
load test_helper

@test "reverts to initial commit" {
  run_cli_ok fork default
  run_cli_ok use default

  local dir="$(profile_dir default)"
  local initial
  initial="$(git -C "$dir" log --format='%h' -1)"

  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Changed"

  run_cli_ok restore "$initial"

  grep -q '"effortLevel"' "$CLAUDE_CODE_HOME/settings.json"
  ! grep -q '"changed"' "$CLAUDE_CODE_HOME/settings.json"
}

@test "creates a new commit (non-destructive)" {
  run_cli_ok fork default
  run_cli_ok use default

  local dir="$(profile_dir default)"
  local initial
  initial="$(git -C "$dir" log --format='%h' -1)"

  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Changed"
  run_cli_ok restore "$initial"

  # History: restore, changed, initial = 3 commits (auto-save is no-op since we just saved)
  local count
  count="$(git -C "$dir" log --oneline | wc -l | tr -d ' ')"
  [ "$count" -eq 3 ]
}

@test "auto-saves unsaved live changes before restoring active profile" {
  run_cli_ok fork default
  run_cli_ok use default
  local dir="$(profile_dir default)"
  local initial
  initial="$(git -C "$dir" log --format='%h' -1)"

  echo '{"saved_change": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Saved change"
  echo '{"unsaved_change": true}' > "$CLAUDE_CODE_HOME/settings.json"

  run_cli_ok restore "$initial"

  local log
  log="$(git -C "$dir" log --oneline)"
  [[ "$log" == *"Auto-save before restore"* ]]
}

@test "profile dir not left empty if checkout target is invalid" {
  run_cli_ok fork default
  run_cli_ok use default
  echo '{"v2": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Version 2"

  # Date before any commit exists — _git_resolve_ref will fail
  run_cli restore "1970-01-01"
  [ "$status" -ne 0 ]
  [ -f "$(profile_dir default)/settings.json" ]
}

@test "warns that bulk items are not affected by restore" {
  mkdir -p "$CLAUDE_CODE_HOME/projects/myproject"
  echo "data" > "$CLAUDE_CODE_HOME/projects/myproject/file.txt"
  run_cli_ok fork default
  run_cli_ok use default
  local dir="$(profile_dir default)"
  local initial
  initial="$(git -C "$dir" log --format='%h' -1)"
  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Changed"
  run_cli_ok restore "$initial"
  [[ "$output" == *"bulk"* ]] || [[ "$output" == *"Bulk"* ]]
}

@test "requires a ref" {
  run_cli_ok fork default
  run_cli restore
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}
