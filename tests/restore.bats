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

@test "restore accepts bare YYYY-MM-DD date" {
  run_cli_ok fork default
  run_cli_ok use default

  local dir="$(profile_dir default)"
  echo '{"changed": true}' > "$CLAUDE_CODE_HOME/settings.json"
  run_cli_ok save -m "Changed"

  # Make unsaved change so restore has visible effect
  echo '{"unsaved": true}' > "$CLAUDE_CODE_HOME/settings.json"

  local commit_date
  commit_date="$(git -C "$dir" log --format='%cs' -1)"

  run_cli_ok restore "$commit_date"

  # Date resolves to end-of-day → matches "Changed" commit
  # Live state should reflect "Changed", NOT the unsaved state
  grep -q '"changed"' "$CLAUDE_CODE_HOME/settings.json"
  ! grep -q '"unsaved"' "$CLAUDE_CODE_HOME/settings.json"
}

@test "restore removes files added after target commit" {
  run_cli_ok fork default
  run_cli_ok use default

  local dir="$(profile_dir default)"
  local initial
  initial="$(git -C "$dir" log --format='%h' -1)"

  # Add a new file and save
  mkdir -p "$CLAUDE_CODE_HOME/agents"
  echo "extra agent" > "$CLAUDE_CODE_HOME/agents/extra.md"
  run_cli_ok save -m "Added extra agent"

  # Restore to initial commit — the extra file should be gone
  run_cli_ok restore "$initial"

  [ ! -f "$(profile_dir default)/agents/extra.md" ]
  [ ! -f "$CLAUDE_CODE_HOME/agents/extra.md" ]
}

@test "requires a ref" {
  run_cli_ok fork default
  run_cli restore
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* ]]
}
